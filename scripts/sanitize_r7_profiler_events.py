#!/usr/bin/env python3
"""Create a small privacy-safe event-row summary from xctrace XML exports."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import xml.etree.ElementTree as ET
from pathlib import Path


def rows(path: Path) -> list[ET.Element]:
    return ET.parse(path).getroot().findall(".//row")


def direct(row: ET.Element, tag: str) -> dict[str, str] | None:
    child = row.find(tag)
    if child is None:
        return None
    return {"fmt": child.attrib.get("fmt", ""), "value": child.text or ""}


def command_row(row: ET.Element) -> dict:
    encoder_count = None
    for narrative in row.findall("narrative"):
        match = re.search(r"with\s+(\d+)\s+encoders", narrative.attrib.get("fmt", ""))
        if match:
            encoder_count = int(match.group(1))
            break
    return {
        "start": direct(row, "start-time"),
        "duration": direct(row, "duration"),
        "encoder_count_when_exported": encoder_count,
        "command_buffer_id": direct(row, "metal-command-buffer-id"),
    }


def gpu_row(row: ET.Element) -> dict:
    return {
        "timestamp": direct(row, "start-time"),
        "channel_id": direct(row, "metal-command-buffer-id"),
        "gpu_submission_id": direct(row, "metal-command-buffer-id"),
    }


def encoder_row(row: ET.Element) -> dict:
    labels = [direct(row, "metal-object-label"), direct(row, "metal-object-label-indexed")]
    return {
        "command_buffer_label": labels[0],
        "encoder_label": labels[1],
        "event_type": direct(row, "metal-event-name"),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--profile", type=Path, required=True)
    parser.add_argument("--toc", type=Path, required=True)
    parser.add_argument("--command-events", type=Path, required=True)
    parser.add_argument("--gpu-events", type=Path, required=True)
    parser.add_argument("--encoder-events", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    profile = json.loads(args.profile.read_text())
    toc = args.toc.read_text(errors="replace")
    if 'return-exit-status="0"' not in toc or "Target app exited" not in toc:
        raise SystemExit("FAIL profiler sanitizer: trace does not show clean target exit")
    command_rows = rows(args.command_events)
    gpu_rows = rows(args.gpu_events)
    encoder_rows = rows(args.encoder_events)
    if not command_rows or not gpu_rows or not encoder_rows:
        raise SystemExit("FAIL profiler sanitizer: one or more event exports has no rows")

    payload = {
        "schema_version": 1,
        "status": "r7_sanitized_metal_event_rows",
        "generating_commit": profile["commit"],
        "profile_artifact": "proof/r7-final-shared-path-profile-repaired-labeled.json",
        "environment": profile["environment"],
        "capture": {
            "format": profile["trace"]["format"],
            "status": profile["trace"]["status"],
            "command": profile["trace"]["capture_command"],
            "raw_trace_path": "proof/profiler/r7-b2-c1-shared-repaired-labeled.trace",
            "target_exit": "exit(0); Target app exited",
            "metadata_policy": "sanitized; no device nickname, UUID, PID, username, local path, or process inventory",
        },
        "event_tables": {
            "metal_application_command_buffer_submissions": {
                "schema": "metal-application-command-buffer-submissions",
                "row_count": len(command_rows),
                "sample_rows": [command_row(row) for row in command_rows[:6] + command_rows[-3:]],
            },
            "metal_gpu_execution_points": {
                "schema": "metal-gpu-execution-points",
                "row_count": len(gpu_rows),
                "sample_rows": [gpu_row(row) for row in gpu_rows[:6] + gpu_rows[-3:]],
            },
            "metal_application_encoders_list": {
                "schema": "metal-application-encoders-list",
                "row_count": len(encoder_rows),
                "sample_rows": [encoder_row(row) for row in encoder_rows[:6] + encoder_rows[-3:]],
            },
        },
        "workload": {
            "warmup_iterations": profile["configuration"]["warmup_iterations"],
            "measured_iterations": profile["configuration"]["measured_iterations"],
            "b2_path_invocations": profile["configuration"]["warmup_iterations"] + profile["configuration"]["measured_iterations"],
            "c1_path_invocations": profile["configuration"]["warmup_iterations"] + profile["configuration"]["measured_iterations"],
            "observed_command_buffer_rows": len(command_rows),
            "observed_gpu_execution_rows": len(gpu_rows),
            "observed_encoder_rows": len(encoder_rows),
            "path_mapping": "The profiler harness executes B2 then C1 for every warmup and measured iteration; 25 expected command submissions per path.",
        },
        "expected_path_structure": {
            "b2": {
                "command_submissions": 25,
                "ordered_compute_encoders": ["planefuse.b2.rgb", "planefuse.b2.stem"],
                "source_symbols": "MetalMobileNetV2RGBPipeline.executeCHWTimed -> encodeCHWConversion -> encodeCHWStem",
                "materialized_rgb_bytes": profile["resources"]["b2_rgb_logical_payload_bytes"],
            },
            "c1": {
                "command_submissions": 25,
                "ordered_compute_encoders": ["planefuse.c1.native_stem"],
                "source_symbols": "MetalMobileNetV2NativeStem.executeTimed -> encode",
                "materialized_rgb_bytes": profile["resources"]["c1_rgb_logical_payload_bytes"],
            },
            "label_note": "Profiler-only labels are bound in source; Metal System Trace exports may normalize object labels to generic Compute Command labels, so source checker plus alternating invocation counts provide the path mapping.",
        },
        "resource_evidence": profile["resources"],
        "persistent_activation_handoff": profile["persistent_activation_handoff"],
    }
    canonical = json.dumps(payload, sort_keys=True, separators=(",", ":")).encode()
    output = {"payload": payload, "canonical_payload_sha256": hashlib.sha256(canonical).hexdigest()}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(output, indent=2, sort_keys=True) + "\n")
    print(f"PASS profiler sanitizer: {args.output}")
    print(f"command rows: {len(command_rows)}; GPU rows: {len(gpu_rows)}; encoder rows: {len(encoder_rows)}")
    print(f"canonical_payload_sha256: {output['canonical_payload_sha256']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
