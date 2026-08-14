#!/usr/bin/env python3
"""Fail-closed checker for the retained sanitized public-clone run."""

from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RECORD_PATH = ROOT / "proof/final/public-clone-reproduction.json"
EVIDENCE_ROOT = ROOT / "proof/final/public-clone-reproduction/7eb1c3d30424adb6aff844ed950e98d5a036b9f3"
AGGREGATE_PATH = EVIDENCE_ROOT / "r7.5-final.json"
FROZEN_PATH = ROOT / "proof/r7.5-source-reuse-final-52db138-20260811T1605Z-confirm.json"


def fail(message: str) -> None:
    raise SystemExit(f"FAIL public clone reproduction: {message}")


def p50(values: list[float]) -> float:
    return sorted(values)[math.ceil(len(values) * 0.5) - 1]


def main() -> int:
    record = json.loads(RECORD_PATH.read_text())
    aggregate = json.loads(AGGREGATE_PATH.read_text())
    frozen = json.loads(FROZEN_PATH.read_text())

    if record.get("tested_commit") != aggregate.get("commit"):
        fail("record and retained aggregate commits differ")
    if aggregate.get("status") != "r7_5_source_reuse_final":
        fail("retained aggregate has unexpected status")
    if (aggregate.get("batch_count"), aggregate.get("warmup_triples_per_batch"), aggregate.get("measured_triples_per_batch")) != (5, 20, 240):
        fail("retained aggregate protocol mismatch")
    if len(aggregate.get("source_sample_ids", [])) != 64 or len(aggregate.get("raw_triple_records", [])) != 1200:
        fail("retained aggregate corpus or raw-record count mismatch")

    permutations = {
        ("B2", "C1", "C1-SR"), ("B2", "C1-SR", "C1"),
        ("C1", "B2", "C1-SR"), ("C1", "C1-SR", "B2"),
        ("C1-SR", "B2", "C1"), ("C1-SR", "C1", "B2"),
    }
    records = aggregate["raw_triple_records"]
    if {tuple(item["execution_order"]) for item in records} != permutations:
        fail("retained raw records do not contain all six execution permutations")
    for batch_index, expected_hash in enumerate(aggregate["raw_batch_sha256"]):
        batch_path = EVIDENCE_ROOT / "batches" / f"batch-{batch_index:02d}.json"
        if not batch_path.is_file():
            fail(f"missing retained raw batch {batch_path.relative_to(ROOT)}")
        actual_hash = hashlib.sha256(batch_path.read_bytes()).hexdigest()
        if actual_hash != expected_hash:
            fail(f"raw batch hash mismatch for batch-{batch_index:02d}")

    paths = {
        "B2": [item["b2_milliseconds"] for item in records],
        "C1": [item["c1_milliseconds"] for item in records],
        "C1-SR": [item["c1_source_reuse_milliseconds"] for item in records],
    }
    for key, values in paths.items():
        if not math.isclose(p50(values), aggregate["aggregate"]["statistics"][key]["p50"], rel_tol=0, abs_tol=1e-12):
            fail(f"retained p50 mismatch for {key}")

    full = record["full_reproduction"]
    expected = {"B2": full["b2_p50_ms"], "C1": full["c1_p50_ms"], "C1-SR": full["c1_sr_p50_ms"]}
    for key, value in expected.items():
        if not math.isclose(value, aggregate["aggregate"]["statistics"][key]["p50"], rel_tol=0, abs_tol=1e-9):
            fail(f"public record p50 mismatch for {key}")
    if not (expected["C1-SR"] < expected["C1"] < expected["B2"]):
        fail("fresh public ordering is not C1-SR < C1 < B2")
    if frozen.get("status") != "r7_5_source_reuse_final":
        fail("frozen comparison artifact has unexpected status")

    # The public record may mention the ephemeral output location produced by
    # the clone run. The retained aggregate and raw batches must be portable.
    for path in (AGGREGATE_PATH, *sorted((EVIDENCE_ROOT / "batches").glob("batch-*.json"))):
        text = path.read_text()
        if "/Users/" in text or "/private/" in text or "artifacts/reproduction/" in text:
            fail(f"retained proof contains a machine-local path: {path.relative_to(ROOT)}")
    print("PASS public clone reproduction: retained aggregate, hashes, protocol, and frozen comparison are consistent")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
