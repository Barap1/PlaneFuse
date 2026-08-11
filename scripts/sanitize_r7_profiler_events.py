#!/usr/bin/env python3
"""Create a privacy-safe, fully resolved event export from xctrace XML."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import xml.etree.ElementTree as ET
from pathlib import Path


def table(path: Path) -> tuple[list[str], list[ET.Element]]:
    node = ET.parse(path).getroot().find(".//node")
    if node is None or node.find("schema") is None:
        raise SystemExit(f"FAIL profiler sanitizer: missing schema in {path}")
    columns = [column.findtext("mnemonic") or "" for column in node.find("schema")]
    return columns, node.findall("row")


def resolver(rows: list[ET.Element]) -> dict[str, str]:
    values: dict[str, str] = {}
    for row in rows:
        for child in row:
            if "id" in child.attrib:
                values[child.attrib["id"]] = child.attrib.get("fmt") or child.text or ""
    return values


def row_values(columns: list[str], row: ET.Element, values: dict[str, str]) -> dict[str, str]:
    result: dict[str, str] = {}
    for column, child in zip(columns, row):
        if "fmt" in child.attrib:
            value = child.attrib["fmt"]
        elif "ref" in child.attrib:
            value = values.get(child.attrib["ref"], "")
        else:
            value = child.text or ""
        result[column] = value
    return result


def numeric(value: str) -> int | None:
    hexadecimal = re.fullmatch(r"0x[0-9a-fA-F]+", value.strip())
    if hexadecimal:
        return int(hexadecimal.group(0), 16)
    timestamp = re.fullmatch(r"(\d+):(\d+)\.(\d+)\.(\d+)", value.strip())
    if timestamp:
        minutes, seconds, millis, micros = (int(part) for part in timestamp.groups())
        return (((minutes * 60) + seconds) * 1_000 + millis) * 1_000 + micros
    match = re.search(r"-?\d+", value)
    return int(match.group(0)) if match else None


def resolved_command_rows(path: Path) -> list[dict]:
    columns, raw = table(path)
    values = resolver(raw)
    result = []
    for index, row in enumerate(raw):
        fields = row_values(columns, row, values)
        result.append({
            "event_index": index,
            "start": numeric(fields.get("start", "")),
            "duration": numeric(fields.get("duration", "")),
            "encoder_count": numeric(fields.get("num-encoders", "")),
            "frame_number": numeric(fields.get("frame-number", "")),
            "event_type": fields.get("event-type", ""),
            "event_label": fields.get("event-label", ""),
            "command_buffer_id": fields.get("cmdbuffer-id", ""),
        })
    return result


def resolved_gpu_rows(path: Path) -> list[dict]:
    columns, raw = table(path)
    values = resolver(raw)
    result = []
    for index, row in enumerate(raw):
        fields = row_values(columns, row, values)
        result.append({
            "event_index": index,
            "timestamp": numeric(fields.get("timestamp", "")),
            "gpu_submission_id": numeric(fields.get("gpu-submission-id", "")),
            "gpu_submission_id_text": fields.get("gpu-submission-id", ""),
            "note": fields.get("note", ""),
        })
    return result


def resolved_encoder_rows(path: Path) -> list[dict]:
    columns, raw = table(path)
    values = resolver(raw)
    result = []
    for index, row in enumerate(raw):
        fields = row_values(columns, row, values)
        result.append({
            "event_index": index,
            "frame_number": numeric(fields.get("frame-number", "")),
            "event_type": fields.get("event-type", ""),
            "command_buffer_label": fields.get("cmdbuffer-label", ""),
            "encoder_label": fields.get("encoder-label", ""),
            "command_buffer_id": fields.get("cmdbuffer-id", ""),
            "encoder_id": fields.get("encoder-id", ""),
        })
    return result


def resolved_mapping_rows(path: Path) -> list[dict]:
    columns, raw = table(path)
    values = resolver(raw)
    result = []
    for index, row in enumerate(raw):
        fields = row_values(columns, row, values)
        result.append({
            "event_index": index,
            "timestamp": numeric(fields.get("timestamp", "")),
            "command_buffer_id": fields.get("cmdbuffer-id", ""),
            "gpu_submission_id": fields.get("gpu-submission-id", ""),
            "encoder_id": fields.get("encoder-id", ""),
        })
    return result


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--profile", type=Path, required=True)
    parser.add_argument("--toc", type=Path, required=True)
    parser.add_argument("--command-events", type=Path, required=True)
    parser.add_argument("--gpu-events", type=Path, required=True)
    parser.add_argument("--encoder-events", type=Path, required=True)
    parser.add_argument("--submission-map", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    profile = json.loads(args.profile.read_text())
    toc = args.toc.read_text(errors="replace")
    if 'return-exit-status="0"' not in toc or "Target app exited" not in toc:
        raise SystemExit("FAIL profiler sanitizer: trace does not show clean target exit")
    command_rows = resolved_command_rows(args.command_events)
    gpu_rows = resolved_gpu_rows(args.gpu_events)
    encoder_rows = resolved_encoder_rows(args.encoder_events)
    mapping_rows = resolved_mapping_rows(args.submission_map)
    if not command_rows or not gpu_rows or not encoder_rows or not mapping_rows:
        raise SystemExit("FAIL profiler sanitizer: one or more event exports has no rows")
    total_invocations = profile["configuration"]["warmup_iterations"] + profile["configuration"]["measured_iterations"]
    if len(command_rows) != total_invocations * 2 or len(encoder_rows) != total_invocations * 2:
        raise SystemExit("FAIL profiler sanitizer: event row cardinality does not match the profiler schedule")

    command_ids = {row["command_buffer_id"] for row in command_rows}
    mapping_rows = [row for row in mapping_rows if row["command_buffer_id"] in command_ids]
    submission_ids = {row["gpu_submission_id"] for row in mapping_rows}
    gpu_rows = [row for row in gpu_rows if row["gpu_submission_id_text"] in submission_ids]
    if len(mapping_rows) != len(command_rows) * 2 or not gpu_rows:
        raise SystemExit("FAIL profiler sanitizer: observed submission join is incomplete")

    # Attribution is reconstructed from observed Metal labels and command-buffer
    # IDs. The profile's alternating call order is retained only as an ordering
    # check; it is not the source of B2/C1 identity.
    encoder_by_command = {row["command_buffer_id"]: row for row in encoder_rows}
    invocations = []
    for index, command in enumerate(command_rows):
        event_label = command["event_label"]
        encoder = encoder_by_command.get(command["command_buffer_id"])
        if '" planefuse.b2.shared "' in event_label:
            path = "B2"
            expected_encoder = "planefuse.b2.rgb & planefuse.b2.stem"
            source_encoder_labels = ["planefuse.b2.rgb", "planefuse.b2.stem"]
        elif '" planefuse.c1.shared "' in event_label:
            path = "C1"
            expected_encoder = "planefuse.c1.native_stem"
            source_encoder_labels = ["planefuse.c1.native_stem"]
        else:
            raise SystemExit("FAIL profiler sanitizer: command row has no observed B2/C1 label")
        if encoder is None or encoder["command_buffer_label"] != f"planefuse.{path.lower()}.shared" or encoder["encoder_label"] != expected_encoder:
            raise SystemExit("FAIL profiler sanitizer: command/encoder observed-label join failed")
        related_gpu = [row for row in mapping_rows if row["command_buffer_id"] == command["command_buffer_id"]]
        invocations.append({
            "invocation_index": index,
            "path": path,
            "command_buffer_event_index": index,
            "command_buffer_id": command["command_buffer_id"],
            "encoder_event_indices": [encoder["event_index"]],
            "source_encoder_labels": source_encoder_labels,
            "observed_encoder_label": encoder["encoder_label"],
            "gpu_submission_ids": [row["gpu_submission_id"] for row in related_gpu],
        })

    payload = {
        "schema_version": 2,
        "status": "r7_sanitized_metal_event_rows",
        "generating_commit": profile["commit"],
        "profile_artifact": args.profile.as_posix(),
        "environment": profile["environment"],
        "capture": {
            "format": profile["trace"]["format"],
            "status": profile["trace"]["status"],
            "command": profile["trace"]["capture_command"],
            "raw_trace_path": "proof/profiler/r7-b2-c1-shared-repaired-labeled.trace",
            "target_exit": "exit(0); Target app exited",
            "metadata_policy": "sanitized; no device nickname, UUID, PID, username, local path, or process inventory",
        },
        "source_export_sha256": {
            "trace_toc": sha256(args.toc),
            "command_events": sha256(args.command_events),
            "gpu_events": sha256(args.gpu_events),
            "encoder_events": sha256(args.encoder_events),
            "submission_map": sha256(args.submission_map),
        },
        "event_tables": {
            "metal_application_command_buffer_submissions": {
                "schema": "metal-application-command-buffer-submissions",
                "row_count": len(command_rows),
                "rows": command_rows,
            },
            "metal_gpu_execution_points": {
                "schema": "metal-gpu-execution-points",
                "row_count": len(gpu_rows),
                "rows": gpu_rows,
            },
            "metal_application_encoders_list": {
                "schema": "metal-application-encoders-list",
                "row_count": len(encoder_rows),
                "rows": encoder_rows,
            },
            "metal_gpu_submission_to_command_buffer_id": {
                "schema": "metal-gpu-submission-to-command-buffer-id",
                "row_count": len(mapping_rows),
                "rows": mapping_rows,
            },
        },
        "workload": {
            "warmup_iterations": profile["configuration"]["warmup_iterations"],
            "measured_iterations": profile["configuration"]["measured_iterations"],
            "observed_command_buffer_rows": len(command_rows),
            "observed_gpu_execution_rows": len(gpu_rows),
            "observed_encoder_rows": len(encoder_rows),
            "invocations": invocations,
            "attribution_basis": "observed Metal command-buffer and encoder labels joined by observed command-buffer IDs; GPU rows are joined through the observed submission-to-command-buffer table. Alternating call order is a consistency check only.",
        },
        "expected_path_structure": {
            "b2": {
                "command_submissions": total_invocations,
                "ordered_compute_encoders": ["planefuse.b2.rgb", "planefuse.b2.stem"],
                "source_symbols": "MetalMobileNetV2RGBPipeline.executeCHWTimed -> encodeCHWConversion -> encodeCHWStem",
                "materialized_rgb_bytes": profile["resources"]["b2_rgb_logical_payload_bytes"],
            },
            "c1": {
                "command_submissions": total_invocations,
                "ordered_compute_encoders": ["planefuse.c1.native_stem"],
                "source_symbols": "MetalMobileNetV2NativeStem.executeTimed -> encode",
                "materialized_rgb_bytes": profile["resources"]["c1_rgb_logical_payload_bytes"],
            },
            "label_note": "The Metal System Trace export observed the profiler-only command-buffer labels and combined ordered encoder label for B2, plus the native-stem encoder label for C1.",
        },
        "resource_evidence": profile["resources"],
        "persistent_activation_handoff": profile["persistent_activation_handoff"],
    }
    canonical = json.dumps(payload, sort_keys=True, separators=(",", ":")).encode()
    output = {"payload": payload, "canonical_payload_sha256": hashlib.sha256(canonical).hexdigest()}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(output, indent=2, sort_keys=True) + "\n")
    print(f"PASS profiler sanitizer: {args.output}")
    print(f"complete command rows: {len(command_rows)}; GPU rows: {len(gpu_rows)}; encoder rows: {len(encoder_rows)}")
    print(f"canonical_payload_sha256: {output['canonical_payload_sha256']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
