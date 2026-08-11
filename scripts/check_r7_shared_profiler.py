#!/usr/bin/env python3
"""Fail-closed checker for the repaired exact shared-path profiler evidence."""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
from pathlib import Path


def fail(message: str) -> None:
    raise SystemExit(f"FAIL r7 shared profiler: {message}")


def validate_event_export(data: dict) -> None:
    payload = data.get("payload", {})
    if data.get("canonical_payload_sha256") is None:
        fail("event export hash is missing")
    canonical = json.dumps(payload, sort_keys=True, separators=(",", ":")).encode()
    if hashlib.sha256(canonical).hexdigest() != data["canonical_payload_sha256"]:
        fail("event export canonical hash mismatch")
    if payload.get("status") != "r7_sanitized_metal_event_rows":
        fail("event export status is not sanitized Metal event rows")
    tables = payload.get("event_tables", {})
    required = {
        "metal_application_command_buffer_submissions": 1,
        "metal_gpu_execution_points": 1,
        "metal_application_encoders_list": 1,
        "metal_gpu_submission_to_command_buffer_id": 1,
    }
    for name, minimum in required.items():
        table = tables.get(name, {})
        if table.get("row_count", 0) < minimum or len(table.get("rows", [])) != table.get("row_count"):
            fail(f"event table {name} is empty, truncated, or schema-only")
    workload = payload.get("workload", {})
    if workload.get("observed_command_buffer_rows") != 50:
        fail("expected 50 shared B2/C1 command submissions was not observed")
    if workload.get("observed_gpu_execution_rows", 0) <= 0 or workload.get("observed_encoder_rows", 0) <= 0:
        fail("GPU/encoder event rows are not nonzero")
    command_rows = tables["metal_application_command_buffer_submissions"]["rows"]
    encoder_rows = tables["metal_application_encoders_list"]["rows"]
    gpu_rows = tables["metal_gpu_execution_points"]["rows"]
    mapping_rows = tables["metal_gpu_submission_to_command_buffer_id"]["rows"]
    if any(not row.get("command_buffer_id") or not row.get("event_label") for row in command_rows):
        fail("command rows lack observed command-buffer IDs or labels")
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
    mapped_ids = {row["command_buffer_id"] for row in mapping_rows}
    if mapped_ids != set(command_by_id):
        fail("observed submission mapping does not cover every command buffer")
    mapped_submissions = {row["gpu_submission_id"] for row in mapping_rows}
    if not mapped_submissions or not any(row.get("gpu_submission_id_text") in mapped_submissions for row in gpu_rows):
        fail("GPU rows are not joined to observed submission mappings")
    expected = payload.get("expected_path_structure", {})
    invocations = workload.get("invocations", [])
    if len(invocations) != 50:
        fail("complete invocation attribution is missing")
    paths = [entry.get("path") for entry in invocations]
    if paths.count("B2") != 25 or paths.count("C1") != 25:
        fail("B2/C1 attribution does not reconstruct 25 observed events per path")
    if any(entry.get("command_buffer_event_index") != index or not entry.get("command_buffer_id") or not entry.get("observed_encoder_label") for index, entry in enumerate(invocations)):
        fail("invocation attribution does not bind observed command and encoder rows")
    if [command_by_id[entry["command_buffer_id"]]["event_label"] for entry in invocations] != [command["event_label"] for command in command_rows]:
        fail("invocation order is not the observed command-buffer order")
    if expected.get("b2", {}).get("command_submissions") != 25 or expected.get("c1", {}).get("command_submissions") != 25:
        fail("expected B2/C1 path counts are missing")
    if expected.get("b2", {}).get("ordered_compute_encoders") != ["planefuse.b2.rgb", "planefuse.b2.stem"]:
        fail("B2 expected two-encoder structure is missing")
    if expected.get("c1", {}).get("ordered_compute_encoders") != ["planefuse.c1.native_stem"]:
        fail("C1 expected native-stem structure is missing")
    if set(payload.get("source_export_sha256", {})) != {"trace_toc", "command_events", "gpu_events", "encoder_events", "submission_map"}:
        fail("source export hashes are missing")
    capture = payload.get("capture", {})
    if capture.get("target_exit") != "exit(0); Target app exited":
        fail("profiler workload completion is not recorded as clean")
    if capture.get("status") != "metal-system-trace-captured-naturally-terminated":
        fail("profiler capture status is not the clean terminating status")


def run_negative_schema_only_test() -> None:
    schema_only = {
        "payload": {
            "status": "r7_sanitized_metal_event_rows",
            "event_tables": {
                "metal_application_command_buffer_submissions": {"row_count": 0, "rows": []},
                "metal_gpu_execution_points": {"row_count": 0, "rows": []},
                "metal_application_encoders_list": {"row_count": 0, "rows": []},
            },
        },
        "canonical_payload_sha256": hashlib.sha256(b"{}").hexdigest(),
    }
    try:
        validate_event_export(schema_only)
    except SystemExit:
        return
    fail("negative schema-only export test did not fail")


def run_negative_attribution_tests(data: dict) -> None:
    altered = json.loads(json.dumps(data))
    altered["payload"]["workload"]["invocations"] = altered["payload"]["workload"]["invocations"][:-1]
    try:
        validate_event_export(altered)
    except SystemExit:
        pass
    else:
        fail("negative truncated-attribution export test did not fail")
    altered = json.loads(json.dumps(data))
    altered["payload"]["workload"]["invocations"][1]["path"] = "B2"
    try:
        validate_event_export(altered)
    except SystemExit:
        pass
    else:
        fail("negative wrong-path attribution export test did not fail")
    altered = json.loads(json.dumps(data))
    for table in altered["payload"]["event_tables"].values():
        table["rows"] = [{} for _ in table["rows"]]
    altered["payload"]["workload"]["invocations"] = [{} for _ in altered["payload"]["workload"]["invocations"]]
    try:
        validate_event_export(altered)
    except SystemExit:
        return
    fail("negative blank/generic event-row export test did not fail")


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
    validate_event_export(json.loads(event_path.read_text()))
    run_negative_schema_only_test()
    run_negative_attribution_tests(json.loads(event_path.read_text()))
    print(f"PASS r7 shared profiler: {artifact_path}")
    print(f"head: {expected_commit}; event export: {event_path}")
    print("complete event rows, derived B2/C1 attribution, clean completion, source hashes, and negative tests verified")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
