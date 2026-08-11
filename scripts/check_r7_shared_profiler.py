#!/usr/bin/env python3
"""Fail-closed checker for the repaired exact shared-path profiler evidence."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path


def fail(message: str) -> None:
    raise SystemExit(f"FAIL r7 shared profiler: {message}")


EXPECTED_SOURCE_EXPORT_SHA256 = {
    "trace_toc": "f6c70b539f2f70481a169541af859a55571b77c98c05b378a35d575046a92a41",
    "command_events": "cb31c002c4b0f21e03c699b70a276fccf091aa5e0de9f701541062f56fe12097",
    "gpu_events": "cb4ae56ef21da2d70e2671c05e7037b10702460a945d0db93d03380b263010e9",
    "encoder_events": "5de72d4723e633ba1512a5d8de527a0facbacd6783f451d4ab17461e5ef10c91",
    "submission_map": "133433771e53ac0dfccfe61c0a79cdb0c04c97809877e2bf555196fdda2cf6a2",
}


def canonical_hash(payload: dict) -> str:
    canonical = json.dumps(payload, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(canonical).hexdigest()


def validate_event_export(data: dict, *, expected_commit: str | None = None, profile_commit: str | None = None) -> None:
    payload = data.get("payload", {})
    if data.get("canonical_payload_sha256") is None:
        fail("event export hash is missing")
    if canonical_hash(payload) != data["canonical_payload_sha256"]:
        fail("event export canonical hash mismatch")
    if payload.get("status") != "r7_sanitized_metal_event_rows":
        fail("event export status is not sanitized Metal event rows")
    tables = payload.get("event_tables", {})
    required = {
        "metal_application_command_buffer_submissions": 50,
        "metal_gpu_execution_points": 100,
        "metal_application_encoders_list": 50,
        "metal_gpu_submission_to_command_buffer_id": 100,
    }
    for name, minimum in required.items():
        table = tables.get(name, {})
        if table.get("row_count") != minimum or len(table.get("rows", [])) != minimum:
            fail(f"event table {name} does not have exact expected cardinality {minimum}")
    workload = payload.get("workload", {})
    if (workload.get("observed_command_buffer_rows"), workload.get("observed_gpu_execution_rows"), workload.get("observed_encoder_rows")) != (50, 100, 50):
        fail("workload event counts do not match exact observed 50/100/50 rows")
    if (workload.get("warmup_iterations"), workload.get("measured_iterations")) != (5, 20):
        fail("profiler workload configuration must be exactly 5 warmups and 20 measured iterations")
    command_rows = tables["metal_application_command_buffer_submissions"]["rows"]
    encoder_rows = tables["metal_application_encoders_list"]["rows"]
    gpu_rows = tables["metal_gpu_execution_points"]["rows"]
    mapping_rows = tables["metal_gpu_submission_to_command_buffer_id"]["rows"]
    if any(not row.get("command_buffer_id") or not row.get("event_label") for row in command_rows):
        fail("command rows lack observed command-buffer IDs or labels")
    if any(row.get("encoder_count") != 1 for row in command_rows):
        fail("command rows do not contain the canonical encoder count 1")
    if any(not row.get("command_buffer_id") or not row.get("command_buffer_label") or not row.get("encoder_label") for row in encoder_rows):
        fail("encoder rows are blank/generic-only or lack observed labels")
    if any(row.get("timestamp", 0) in (None, 0) or row.get("gpu_submission_id") in (None, 0) for row in gpu_rows):
        fail("GPU rows lack nonzero observed timestamps or submission IDs")
    if any(not row.get("command_buffer_id") or not row.get("gpu_submission_id") for row in mapping_rows):
        fail("submission mapping rows lack observed command/submission IDs")
    command_by_id = {row["command_buffer_id"]: row for row in command_rows}
    encoder_by_id = {row["command_buffer_id"]: row for row in encoder_rows}
    if len(command_by_id) != 50 or len(encoder_by_id) != 50 or set(command_by_id) != set(encoder_by_id):
        fail("observed command/encoder ID join is incomplete or duplicated")
    observed_paths = []
    for command_id, command in command_by_id.items():
        event_label = command["event_label"]
        encoder = encoder_by_id[command_id]
        if '" planefuse.b2.shared "' in event_label:
            observed_paths.append("B2")
            if encoder["command_buffer_label"] != "planefuse.b2.shared" or encoder["encoder_label"] != "planefuse.b2.rgb & planefuse.b2.stem":
                fail("observed B2 encoder structure is not the expected ordered RGB/stem pair")
        elif '" planefuse.c1.shared "' in event_label:
            observed_paths.append("C1")
            if encoder["command_buffer_label"] != "planefuse.c1.shared" or encoder["encoder_label"] != "planefuse.c1.native_stem":
                fail("observed C1 encoder structure is not the expected native stem")
        else:
            fail("command row has no observed B2/C1 path label")
    if observed_paths.count("B2") != 25 or observed_paths.count("C1") != 25:
        fail("observed command-buffer labels do not show 25 B2 and 25 C1 events")
    if observed_paths != ["B2" if index % 2 == 0 else "C1" for index in range(50)]:
        fail("observed command-buffer labels do not preserve the alternating B2/C1 profiler schedule")
    mapped_ids = {row["command_buffer_id"] for row in mapping_rows}
    if mapped_ids != set(command_by_id):
        fail("observed submission mapping does not cover every command buffer")
    mapping_by_command = {}
    for row in mapping_rows:
        mapping_by_command.setdefault(row["command_buffer_id"], []).append(row)
    if set(mapping_by_command) != set(command_by_id) or any(len(rows) != 2 for rows in mapping_by_command.values()):
        fail("each observed command buffer must have exactly two submission mappings")
    mapped_submissions = {row["gpu_submission_id"] for row in mapping_rows}
    gpu_by_submission = {}
    for row in gpu_rows:
        gpu_by_submission.setdefault(row["gpu_submission_id_text"], []).append(row)
    if not set(gpu_by_submission).issubset(mapped_submissions) or any(len(rows) != 2 for rows in gpu_by_submission.values()):
        fail("GPU rows do not form a complete two-point join with observed submission mappings")
    for command_id, mappings in mapping_by_command.items():
        gpu_mappings = [row for row in mappings if row["gpu_submission_id"] in gpu_by_submission]
        if len(gpu_mappings) != 1:
            fail("each command buffer must have exactly one mapped GPU submission with two observed execution points")
    expected = payload.get("expected_path_structure", {})
    invocations = workload.get("invocations", [])
    if len(invocations) != 50:
        fail("complete invocation attribution is missing")
    if len(mapped_submissions) != len(mapping_rows):
        fail("mapped GPU submissions are not unique across command buffers")
    if len({entry.get("command_buffer_id") for entry in invocations}) != 50:
        fail("invocations do not contain one unique command buffer each")
    paths = [entry.get("path") for entry in invocations]
    if paths.count("B2") != 25 or paths.count("C1") != 25:
        fail("B2/C1 attribution does not reconstruct 25 observed events per path")
    if any(entry.get("command_buffer_event_index") != index or not entry.get("command_buffer_id") or not entry.get("observed_encoder_label") for index, entry in enumerate(invocations)):
        fail("invocation attribution does not bind observed command and encoder rows")
    for entry in invocations:
        expected_submission_ids = {row["gpu_submission_id"] for row in mapping_by_command[entry["command_buffer_id"]]}
        if set(entry.get("gpu_submission_ids", [])) != expected_submission_ids or len(entry.get("gpu_submission_ids", [])) != 2:
            fail("invocation GPU submission IDs do not bind to that command buffer's observed mappings")
    if [command_by_id[entry["command_buffer_id"]]["event_label"] for entry in invocations] != [command["event_label"] for command in command_rows]:
        fail("invocation order is not the observed command-buffer order")
    if expected.get("b2", {}).get("command_submissions") != 25 or expected.get("c1", {}).get("command_submissions") != 25:
        fail("expected B2/C1 path counts are missing")
    if expected.get("b2", {}).get("ordered_compute_encoders") != ["planefuse.b2.rgb", "planefuse.b2.stem"]:
        fail("B2 expected two-encoder structure is missing")
    if expected.get("c1", {}).get("ordered_compute_encoders") != ["planefuse.c1.native_stem"]:
        fail("C1 expected native-stem structure is missing")
    if payload.get("source_export_sha256") != EXPECTED_SOURCE_EXPORT_SHA256:
        fail("source export hashes are missing, malformed, or do not match the captured exports")
    if not re.fullmatch(r"[0-9a-f]{40}", payload.get("generating_commit", "")):
        fail("generating commit is not a valid full Git commit")
    if expected_commit is not None and payload.get("generating_commit") != expected_commit:
        fail("event export generating commit does not match the requested commit")
    if profile_commit is not None and payload.get("generating_commit") != profile_commit:
        fail("event export generating commit does not match the profile artifact")
    capture = payload.get("capture", {})
    if capture.get("target_exit") != "exit(0); Target app exited":
        fail("profiler workload completion is not recorded as clean")
    if capture.get("status") != "metal-system-trace-captured-naturally-terminated":
        fail("profiler capture status is not the clean terminating status")


def run_negative_schema_only_test(expected_commit: str, profile_commit: str) -> None:
    schema_only = {
        "payload": {
            "status": "r7_sanitized_metal_event_rows",
            "event_tables": {
                "metal_application_command_buffer_submissions": {"row_count": 0, "rows": []},
                "metal_gpu_execution_points": {"row_count": 0, "rows": []},
                "metal_application_encoders_list": {"row_count": 0, "rows": []},
            },
        },
        "canonical_payload_sha256": canonical_hash({
            "status": "r7_sanitized_metal_event_rows",
            "event_tables": {
                "metal_application_command_buffer_submissions": {"row_count": 0, "rows": []},
                "metal_gpu_execution_points": {"row_count": 0, "rows": []},
                "metal_application_encoders_list": {"row_count": 0, "rows": []},
            },
        }),
    }
    expect_semantic_rejection("schema-only", schema_only, expected_commit, profile_commit, "event table")


def expect_semantic_rejection(label: str, data: dict, expected_commit: str, profile_commit: str, expected_reason: str | None = None) -> None:
    data["canonical_payload_sha256"] = canonical_hash(data["payload"])
    try:
        validate_event_export(data, expected_commit=expected_commit, profile_commit=profile_commit)
    except SystemExit as error:
        if "canonical hash mismatch" in str(error):
            fail(f"negative {label} test failed only at the integrity layer")
        if expected_reason is not None and expected_reason not in str(error):
            fail(f"negative {label} test failed for an unexpected reason: {error}")
        return
    fail(f"negative {label} export test did not fail semantic validation")


def run_negative_attribution_tests(data: dict, expected_commit: str, profile_commit: str) -> None:
    altered = json.loads(json.dumps(data))
    altered["payload"]["workload"]["invocations"] = altered["payload"]["workload"]["invocations"][:-1]
    expect_semantic_rejection("truncated-attribution", altered, expected_commit, profile_commit, "complete invocation attribution")
    altered = json.loads(json.dumps(data))
    altered["payload"]["event_tables"]["metal_application_command_buffer_submissions"]["rows"][1]["event_label"] = 'Committed " planefuse.b2.shared " with  1  encoders'
    expect_semantic_rejection("wrong-observed-path", altered, expected_commit, profile_commit, "observed B2 encoder structure")
    altered = json.loads(json.dumps(data))
    gpu_table = altered["payload"]["event_tables"]["metal_gpu_execution_points"]
    gpu_table["rows"] = gpu_table["rows"][:2]
    gpu_table["row_count"] = 2
    altered["payload"]["workload"]["observed_gpu_execution_rows"] = 2
    expect_semantic_rejection("wrong-GPU-cardinality", altered, expected_commit, profile_commit, "exact expected cardinality")
    altered = json.loads(json.dumps(data))
    map_table = altered["payload"]["event_tables"]["metal_gpu_submission_to_command_buffer_id"]
    map_table["rows"] = map_table["rows"][:50]
    map_table["row_count"] = 50
    expect_semantic_rejection("incomplete-submission-join", altered, expected_commit, profile_commit, "exact expected cardinality")
    altered = json.loads(json.dumps(data))
    altered["payload"]["source_export_sha256"]["gpu_events"] = "0" * 64
    expect_semantic_rejection("fake-source-hash", altered, expected_commit, profile_commit, "source export hashes")
    altered = json.loads(json.dumps(data))
    altered["payload"]["generating_commit"] = "0" * 40
    expect_semantic_rejection("wrong-generating-commit", altered, expected_commit, profile_commit, "generating commit")
    altered = json.loads(json.dumps(data))
    for row in altered["payload"]["event_tables"]["metal_application_command_buffer_submissions"]["rows"]:
        row["encoder_count"] = 999
    expect_semantic_rejection("wrong-encoder-count", altered, expected_commit, profile_commit, "canonical encoder count")
    altered = json.loads(json.dumps(data))
    altered["payload"]["workload"]["warmup_iterations"] = 999
    altered["payload"]["workload"]["measured_iterations"] = 999
    expect_semantic_rejection("wrong-workload-counts", altered, expected_commit, profile_commit, "workload configuration")
    altered = json.loads(json.dumps(data))
    for row in altered["payload"]["event_tables"]["metal_application_command_buffer_submissions"]["rows"]:
        row["encoder_count"] = None
    expect_semantic_rejection("null-encoder-count", altered, expected_commit, profile_commit, "canonical encoder count")
    altered = json.loads(json.dumps(data))
    mapping_rows = altered["payload"]["event_tables"]["metal_gpu_submission_to_command_buffer_id"]["rows"]
    mapping_rows[0]["gpu_submission_id"], mapping_rows[2]["gpu_submission_id"] = mapping_rows[2]["gpu_submission_id"], mapping_rows[0]["gpu_submission_id"]
    expect_semantic_rejection("cardinality-preserving-broken-join", altered, expected_commit, profile_commit, "invocation GPU submission IDs")
    altered = json.loads(json.dumps(data))
    altered["payload"]["workload"]["invocations"][0]["command_buffer_id"], altered["payload"]["workload"]["invocations"][1]["command_buffer_id"] = altered["payload"]["workload"]["invocations"][1]["command_buffer_id"], altered["payload"]["workload"]["invocations"][0]["command_buffer_id"]
    expect_semantic_rejection("order-preserving-count", altered, expected_commit, profile_commit, "invocation GPU submission IDs")
    altered = json.loads(json.dumps(data))
    for table in altered["payload"]["event_tables"].values():
        table["rows"] = [{} for _ in table["rows"]]
    altered["payload"]["workload"]["invocations"] = [{} for _ in altered["payload"]["workload"]["invocations"]]
    expect_semantic_rejection("blank-generic-event-row", altered, expected_commit, profile_commit, "command rows lack")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("artifact", nargs="?", default="proof/r7-final-shared-path-profile-repaired-labeled.json")
    parser.add_argument("--events", default="proof/profiler/r7-b2-c1-shared-repaired-events-full.json")
    parser.add_argument("--expected-commit")
    args = parser.parse_args()
    artifact_path = Path(args.artifact)
    event_path = Path(args.events)
    if not artifact_path.is_file():
        fail(f"missing profile artifact {artifact_path}")
    if not event_path.is_file():
        fail(f"missing sanitized event export {event_path}")
    data = json.loads(artifact_path.read_text())
    if data.get("status") != "r7_final_shared_path_profiler":
        fail(f"unexpected status {data.get('status')!r}")
    expected_commit = args.expected_commit or subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()
    if data.get("commit") != expected_commit:
        fail(f"artifact commit {data.get('commit')} does not match requested {expected_commit}")
    if data.get("environment", {}).get("build_configuration") != "release":
        fail("profile is not marked release")
    if data.get("requested_core_ml_compute_units") != "all":
        fail("Core ML compute-unit policy is not explicit .all")
    if data.get("top1_agreement") != 1 or data.get("activation_max_absolute_error", 1) > 1e-5:
        fail("profile quality gate failed")
    resources = data.get("resources", {})
    if resources.get("b2_rgb_logical_payload_bytes") != 602112 or resources.get("b2_rgb_metal_allocated_bytes", 0) <= 0:
        fail("B2 RGB resource evidence is missing")
    if resources.get("c1_rgb_logical_payload_bytes") != 0 or resources.get("c1_rgb_metal_allocated_bytes") != 0:
        fail("C1 RGB absence is not recorded")
    if resources.get("cpu_element_by_element_activation_copy_bytes") != 0:
        fail("CPU element-by-element copy is nonzero")
    handoff = data.get("persistent_activation_handoff", {})
    if handoff.get("shape") != [48, 112, 112] or handoff.get("strides") != [12544, 112, 1] or "BufferBackedMultiArray(dataPointer:)" not in handoff.get("bridge", ""):
        fail("persistent shared activation handoff is not canonical")
    for key in ("pipeline_b2_shared", "pipeline_c1_shared"):
        if data.get(key, {}).get("gpu_timestamp_samples", 0) <= 0 or data.get(key, {}).get("input_to_result", {}).get("count", 0) <= 0:
            fail(f"{key} lacks measured GPU/input-to-result samples")
    event_data = json.loads(event_path.read_text())
    validate_event_export(event_data, expected_commit=expected_commit, profile_commit=data.get("commit"))
    run_negative_schema_only_test(expected_commit, data.get("commit"))
    run_negative_attribution_tests(event_data, expected_commit, data.get("commit"))
    print(f"PASS r7 shared profiler: {artifact_path}")
    print(f"head: {expected_commit}; event export: {event_path}")
    print("complete event rows, derived B2/C1 attribution, clean completion, source hashes, and negative tests verified")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
