#!/usr/bin/env python3
"""Structural and numerical checks for the R6.5 camera-space artifact."""

from __future__ import annotations

import hashlib
import json
import math
import sys
from pathlib import Path


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def nearest_rank(values: list[float], percentile: float) -> float:
    ordered = sorted(values)
    return ordered[max(1, math.ceil(percentile * len(ordered))) - 1]


def summary(values: list[float]) -> tuple[float, float, float, float]:
    p50 = nearest_rank(values, 0.50)
    p95 = nearest_rank(values, 0.95)
    mean = sum(values) / len(values)
    mad = nearest_rank([abs(value - p50) for value in values], 0.50)
    return p50, p95, mean, mad


def close(lhs: float, rhs: float, tolerance: float = 1e-9) -> bool:
    return abs(lhs - rhs) <= tolerance * max(1.0, abs(lhs), abs(rhs))


def main() -> int:
    artifact_path = Path(sys.argv[1] if len(sys.argv) > 1 else "proof/r6.5-camera-space.json")
    evidence_dir = artifact_path.resolve().parent
    artifact = json.loads(artifact_path.read_text())
    paired = artifact["paired"]
    records = paired["rawPairRecords"]
    assert artifact["schemaVersion"] == "r6.5-camera-space-benchmark-v1"
    assert len(records) == 1000
    assert paired["batchCount"] == 5 and paired["pairsPerBatch"] == 200
    assert paired["firstOrderPairs"] == 500 and paired["secondOrderPairs"] == 500
    assert len(paired["differences"]) == len(records)
    assert artifact["quality"]["disagreementCount"] == 0
    assert artifact["quality"]["top1Agreement"] >= 0.995
    assert artifact["quality"]["acceptedCActivationMaxAbsoluteError"] <= 1e-5
    assert artifact["quality"]["acceptedBActivationMaxAbsoluteError"] <= 1e-5
    assert artifact["quality"]["activationMaxAbsoluteError"] <= 1e-5
    differences = [
        record["bPostInputToResultMilliseconds"] - record["cPostInputToResultMilliseconds"]
        for record in records
    ]
    assert all(close(a, b) for a, b in zip(differences, paired["differences"]))
    expected = summary(differences)
    stored = paired["differenceSummary"]
    assert all(close(expected[index], stored[key]) for index, key in enumerate(("p50", "p95", "mean", "mad")))
    hashes = {artifact["b2Replay"]["replayPayloadSHA256"], artifact["c1Replay"]["replayPayloadSHA256"], artifact["sourceReplay"]["payloadSHA256"]}
    assert len(hashes) == 1
    manifest = evidence_dir / "r6.5-camera-source-replay.manifest.json"
    payload = evidence_dir / "r6.5-camera-source-replay.bin"
    assert sha256(manifest) == artifact["sourceReplay"]["manifestSHA256"]
    assert sha256(payload) == artifact["sourceReplay"]["payloadSHA256"]
    environment = artifact["environment"]
    for key in ("timestampUTC", "architecture", "operatingSystem", "physicalMemoryBytes", "swiftVersion", "xcodeVersion", "modelIdentifier", "sourceTreeState"):
        assert environment.get(key) not in (None, "", "unknown")
    assert artifact["b2Replay"]["processedFrames"] == 300
    assert artifact["c1Replay"]["processedFrames"] == 300
    assert artifact["b2Live"]["processedFrames"] == 300
    assert artifact["c1Live"]["processedFrames"] == 300
    assert artifact["cRGBLogicalBytes"] == 0 and artifact["cRGBAllocatedBytes"] == 0
    print("PASS R6.5 artifact: 1000 paired records, balanced order, hashes, statistics, parity, and required metadata verified")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (AssertionError, KeyError, OSError, json.JSONDecodeError) as error:
        print(f"FAIL R6.5 artifact: {error}", file=sys.stderr)
        raise SystemExit(1)
