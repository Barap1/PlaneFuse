#!/usr/bin/env python3
"""Fail-closed structural checker for the separate R7 B2/C1 profiler packet."""

from __future__ import annotations

import argparse
import json
import subprocess
from pathlib import Path


def fail(message: str) -> None:
    raise SystemExit(f"FAIL r7 shared profiler: {message}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("artifact", nargs="?", default="proof/r7-final-shared-path-profile.json")
    parser.add_argument("--expected-commit")
    args = parser.parse_args()
    artifact_path = Path(args.artifact)
    if not artifact_path.is_file():
        fail(f"missing artifact {artifact_path}")
    data = json.loads(artifact_path.read_text())
    if data.get("status") != "r7_final_shared_path_profiler":
        fail(f"unexpected status {data.get('status')!r}")
    expected_commit = args.expected_commit
    if expected_commit is None:
        expected_commit = subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()
    if data.get("commit") != expected_commit:
        fail(f"artifact commit {data.get('commit')} does not match requested {expected_commit}")
    if data.get("environment", {}).get("build_configuration") != "release":
        fail("profile is not marked release")
    if data.get("requested_core_ml_compute_units") != "all":
        fail("Core ML compute-unit policy is not explicit .all")
    if data.get("top1_agreement") != 1:
        fail("top-1 agreement failed")
    if data.get("activation_max_absolute_error", 1) > 1e-5:
        fail("activation parity exceeded 1e-5")

    resources = data.get("resources", {})
    if resources.get("b2_rgb_logical_payload_bytes") != 602112:
        fail("B2 logical RGB payload is not 602112 bytes")
    if resources.get("b2_rgb_metal_allocated_bytes", 0) <= 0:
        fail("B2 Metal RGB allocation was not recorded")
    if resources.get("c1_rgb_logical_payload_bytes") != 0 or resources.get("c1_rgb_metal_allocated_bytes") != 0:
        fail("C1 RGB resource is not recorded as absent")
    if resources.get("cpu_element_by_element_activation_copy_bytes") != 0:
        fail("CPU element-by-element activation copy is nonzero")

    handoff = data.get("persistent_activation_handoff", {})
    if handoff.get("shape") != [48, 112, 112] or handoff.get("strides") != [12544, 112, 1]:
        fail("persistent activation shape/strides are not canonical")
    if "BufferBackedMultiArray(dataPointer:)" not in handoff.get("bridge", ""):
        fail("shared activation handoff is not identified")

    for key in ("pipeline_b2_shared", "pipeline_c1_shared"):
        path = data.get(key, {})
        if path.get("gpu_timestamp_samples", 0) <= 0:
            fail(f"{key} has no GPU timestamp samples")
        if path.get("input_to_result", {}).get("count", 0) <= 0:
            fail(f"{key} has no frontend samples")

    trace = data.get("trace", {})
    raw_trace = Path(trace.get("raw_trace_path", ""))
    toc = Path(trace.get("exported_summary_path", ""))
    if not raw_trace.exists():
        fail(f"missing raw trace {raw_trace}")
    if not toc.is_file():
        fail(f"missing exported trace summary {toc}")
    toc_text = toc.read_text(errors="replace")
    for required in ("Metal System Trace", "profile mobilenetv2 shared", "metal-application-command-buffer-submissions", "metal-gpu-execution-points"):
        if required not in toc_text:
            fail(f"trace summary lacks {required!r}")

    print(f"PASS r7 shared profiler: {artifact_path}")
    print(f"head: {expected_commit}")
    print(f"trace: {raw_trace} ({'directory' if raw_trace.is_dir() else 'file'})")
    print(f"toc: {toc}")
    print("resources: B2 RGB recorded; C1 RGB absent; CPU activation copy 0")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
