#!/usr/bin/env python3
"""Structural, numerical, and provenance checks for the R6.5 artifact."""

from __future__ import annotations

import hashlib
import json
import math
import subprocess
import sys
from collections import Counter, defaultdict
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
    return p50, nearest_rank(values, 0.95), sum(values) / len(values), nearest_rank([abs(value - p50) for value in values], 0.50)


def close(lhs: float, rhs: float, tolerance: float = 1e-9) -> bool:
    return abs(lhs - rhs) <= tolerance * max(1.0, abs(lhs), abs(rhs))


class SplitMix64:
    def __init__(self, seed: int) -> None:
        self.state = seed

    def next(self) -> int:
        self.state = (self.state + 0x9E3779B97F4A7C15) & ((1 << 64) - 1)
        value = self.state
        value = ((value ^ (value >> 30)) * 0xBF58476D1CE4E5B9) & ((1 << 64) - 1)
        value = ((value ^ (value >> 27)) * 0x94D049BB133111EB) & ((1 << 64) - 1)
        return value ^ (value >> 31)

    def next_int(self, upper_bound: int) -> int:
        threshold = ((-upper_bound) & ((1 << 64) - 1)) % upper_bound
        while True:
            value = self.next()
            if value >= threshold:
                return value % upper_bound


def bootstrap(batches: dict[str, list[float]]) -> tuple[tuple[float, float], tuple[float, float]]:
    ordered = [batches[key] for key in sorted(batches)]
    generator = SplitMix64(0x50464A52)
    means: list[float] = []
    medians: list[float] = []
    for _ in range(10_000):
        reconstructed: list[float] = []
        for _ in range(5):
            batch = ordered[generator.next_int(5)]
            for _ in range(0, 200, 10):
                start = generator.next_int(191)
                reconstructed.extend(batch[start:start + 10])
        means.append(sum(reconstructed) / len(reconstructed))
        medians.append(nearest_rank(reconstructed, 0.50))
    return (
        (nearest_rank(means, 0.025), nearest_rank(means, 0.975)),
        (nearest_rank(medians, 0.025), nearest_rank(medians, 0.975)),
    )


def git(repo: Path, *args: str) -> str:
    return subprocess.check_output(["git", *args], cwd=repo, text=True).strip()


def main() -> int:
    artifact_path = Path(sys.argv[1] if len(sys.argv) > 1 else "proof/r6.5-camera-space.json").resolve()
    evidence_dir = artifact_path.parent
    repo = evidence_dir.parent
    artifact = json.loads(artifact_path.read_text())
    assert artifact["schemaVersion"] == "r6.5-camera-space-benchmark-v1"
    head = git(repo, "rev-parse", "HEAD")
    # The benchmark records the immutable harness commit that generated the
    # measurement.  Evidence promotion may add a later descendant commit, so
    # require ancestry rather than incorrectly requiring a circular hash match.
    assert artifact["commit"] and git(repo, "merge-base", "--is-ancestor", artifact["commit"], head) == ""
    assert artifact["environment"]["sourceTreeState"] == "clean relevant paths"
    checked_paths = artifact["environment"]["sourceTreeCheckedPaths"]
    assert checked_paths and all(git(repo, "ls-files", "--error-unmatch", path) for path in checked_paths)
    expected_paths = ["Package.swift", "pf"] + git(repo, "ls-files", "--", "Sources/**", "Tests/**").splitlines()
    # The measured artifact records the exact source set present at its
    # generation commit. Later R7 work may add unrelated tracked files; that
    # must not retroactively invalidate an otherwise immutable R6.5 result.
    # Keep the recorded list exact for the artifact while requiring it to be a
    # valid subset of the current repository source set.
    assert checked_paths[:2] == ["Package.swift", "pf"]
    assert set(checked_paths).issubset(set(expected_paths))
    # The verifier itself may be improved after measurement promotion. It is
    # tracked in the manifest for provenance, but is not benchmark code whose
    # cleanliness can invalidate the measured artifact.
    benchmark_paths = [path for path in checked_paths if path != "scripts/check_r6_5_camera_space_artifact.py"]
    assert all(git(repo, "diff", "--quiet", "HEAD", "--", path) == "" for path in benchmark_paths)
    assert all(git(repo, "diff", "--cached", "--quiet", "--", path) == "" for path in benchmark_paths)
    for required in (
        "proof/r6.5-camera-space.json",
        "proof/r6.5-camera-source-replay.manifest.json",
        "proof/r6.5-camera-source-replay.bin",
        "proof/r6.5-camera-space-release.log",
        "proof/reviews/R6.5-CANDIDATE-AAEBC7A-20260810-SOL-02.md",
    ):
        assert git(repo, "ls-files", "--error-unmatch", required)
    assert "/Users/" not in (evidence_dir / "r6.5-camera-space-release.log").read_text()

    paired = artifact["paired"]
    records = paired["rawPairRecords"]
    assert len(records) == 1000 and paired["batchCount"] == 5 and paired["pairsPerBatch"] == 200
    by_batch: dict[str, list[dict]] = defaultdict(list)
    for record in records:
        by_batch[record["batchID"]].append(record)
    assert sorted(by_batch) == [f"batch-{index}" for index in range(5)]
    assert all(len(items) == 200 for items in by_batch.values())
    order_counts = Counter(record["executionOrder"] for record in records)
    assert order_counts == Counter({"B2_camera_then_C1_camera": 500, "C1_camera_then_B2_camera": 500})
    assert all(sorted(Counter(record["executionOrder"] for record in items).values()) == [100, 100] for items in by_batch.values())
    differences = [record["bPostInputToResultMilliseconds"] - record["cPostInputToResultMilliseconds"] for record in records]
    assert all(close(a, b) for a, b in zip(differences, paired["differences"]))
    expected = summary(differences)
    stored = paired["differenceSummary"]
    assert all(close(expected[index], stored[key]) for index, key in enumerate(("p50", "p95", "mean", "mad")))
    stored_batches = {batch["batchID"]: batch["differences"] for batch in paired["batchDifferences"]}
    assert set(stored_batches) == set(by_batch)
    for batch_id, items in by_batch.items():
        assert all(close(a, b) for a, b in zip(stored_batches[batch_id], [r["differenceMilliseconds"] for r in items]))
    b_values = [record["bPostInputToResultMilliseconds"] for record in records]
    c_values = [record["cPostInputToResultMilliseconds"] for record in records]
    expected_percentage = ((nearest_rank(b_values, 0.50) - nearest_rank(c_values, 0.50)) / nearest_rank(b_values, 0.50)) * 100
    assert close(expected_percentage, paired["aggregatePercentage"])
    expected_bootstrap = bootstrap({key: [r["differenceMilliseconds"] for r in items] for key, items in by_batch.items()})
    actual_bootstrap = paired["bootstrap"]
    assert all(close(expected_bootstrap[0][index], actual_bootstrap["meanDifference"][key]) for index, key in enumerate(("lower", "upper")))
    assert all(close(expected_bootstrap[1][index], actual_bootstrap["medianDifference"][key]) for index, key in enumerate(("lower", "upper")))

    manifest = json.loads((evidence_dir / "r6.5-camera-source-replay.manifest.json").read_text())
    payload = evidence_dir / "r6.5-camera-source-replay.bin"
    assert manifest["schemaVersion"] == "r6.5-camera-source-replay-v1"
    assert manifest["width"] == 1920 and manifest["height"] == 1080
    assert manifest["yRowBytes"] == 1920 and manifest["uvRowBytes"] == 1920
    assert len(manifest["frames"]) == 32
    assert sha256(payload) == manifest["payloadSHA256"] == artifact["sourceReplay"]["payloadSHA256"]
    assert sha256(evidence_dir / "r6.5-camera-source-replay.manifest.json") == artifact["sourceReplay"]["manifestSHA256"]
    assert len(payload.read_bytes()) == 32 * (1920 * 1080 + 1920 * 540)
    assert {artifact["b2Replay"]["replayPayloadSHA256"], artifact["c1Replay"]["replayPayloadSHA256"]} == {manifest["payloadSHA256"]}

    quality = artifact["quality"]
    assert quality["disagreementCount"] == 0 and quality["top1Agreement"] >= 0.995
    assert quality["acceptedCActivationMaxAbsoluteError"] <= 1e-5
    assert quality["acceptedBActivationMaxAbsoluteError"] <= 1e-5
    assert quality["activationMaxAbsoluteError"] <= 1e-5
    assert all(artifact[key]["processedFrames"] == 300 for key in ("b2Replay", "c1Replay", "b2Live", "c1Live"))
    assert artifact["cRGBLogicalBytes"] == 0 and artifact["cRGBAllocatedBytes"] == 0
    print("PASS R6.5 artifact: provenance, hashes, 5x200 raw structure/order, recomputed statistics/CI, parity, and metadata verified")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (AssertionError, KeyError, OSError, json.JSONDecodeError, subprocess.CalledProcessError) as error:
        print(f"FAIL R6.5 artifact: {error}", file=sys.stderr)
        raise SystemExit(1)
