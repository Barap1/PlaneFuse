#!/usr/bin/env python3
"""Aggregate the five independent R7.5 three-way source-reuse batches."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from collections import Counter, defaultdict
from pathlib import Path

BATCH_COUNT = 5
TRIPLES_PER_BATCH = 240
WARMUPS = 20
BLOCK_SIZE = 10
BOOTSTRAP_REPLICATES = 10_000
BOOTSTRAP_SEED = 0x50373542
PERMUTATIONS = {
    ("B2", "C1", "C1-SR"), ("B2", "C1-SR", "C1"),
    ("C1", "B2", "C1-SR"), ("C1", "C1-SR", "B2"),
    ("C1-SR", "B2", "C1"), ("C1-SR", "C1", "B2"),
}


def fail(message: str) -> None:
    raise SystemExit(f"FAIL R7.5 source-reuse aggregation: {message}")


def nearest(values: list[float], percentile: float) -> float:
    return sorted(values)[math.ceil(percentile * len(values)) - 1]


def summary(values: list[float]) -> dict[str, float]:
    p50 = nearest(values, 0.5)
    return {"p50": p50, "p95": nearest(values, 0.95), "mean": sum(values) / len(values),
            "median_absolute_deviation": nearest([abs(value - p50) for value in values], 0.5)}


class SplitMix64:
    mask = (1 << 64) - 1

    def __init__(self, seed: int) -> None:
        self.state = seed & self.mask

    def next(self) -> int:
        self.state = (self.state + 0x9E3779B97F4A7C15) & self.mask
        value = self.state
        value = ((value ^ (value >> 30)) * 0xBF58476D1CE4E5B9) & self.mask
        value = ((value ^ (value >> 27)) * 0x94D049BB133111EB) & self.mask
        return (value ^ (value >> 31)) & self.mask

    def next_int(self, upper: int) -> int:
        threshold = ((1 << 64) - upper) % upper
        while True:
            value = self.next()
            if value >= threshold:
                return value % upper


def bootstrap(batches: list[list[float]]) -> dict[str, dict[str, float]]:
    generator = SplitMix64(BOOTSTRAP_SEED)
    means: list[float] = []
    medians: list[float] = []
    for _ in range(BOOTSTRAP_REPLICATES):
        reconstructed: list[float] = []
        for _ in range(BATCH_COUNT):
            batch = batches[generator.next_int(len(batches))]
            for _ in range(0, TRIPLES_PER_BATCH, BLOCK_SIZE):
                block_start = generator.next_int(len(batch) - BLOCK_SIZE + 1)
                reconstructed.extend(batch[block_start : block_start + BLOCK_SIZE])
        means.append(sum(reconstructed) / len(reconstructed))
        medians.append(nearest(reconstructed, 0.5))
    return {"mean_difference": {"lower": nearest(means, 0.025), "upper": nearest(means, 0.975)},
            "median_difference": {"lower": nearest(medians, 0.025), "upper": nearest(medians, 0.975)}}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-dir", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--expected-commit", required=True)
    parser.add_argument("--run-id", required=True)
    args = parser.parse_args()

    artifacts = []
    for index in range(BATCH_COUNT):
        path = args.input_dir / f"batch-{index:02d}.json"
        if not path.is_file():
            fail(f"missing batch artifact {path}")
        data = json.loads(path.read_text())
        measurement = data.get("measurement", {})
        config = measurement.get("configuration", {})
        records = measurement.get("raw_triple_records", [])
        if data.get("status") != "r7_5_source_reuse_batch" or data.get("commit") != args.expected_commit:
            fail(f"status/commit mismatch in {path}")
        if config.get("batch_index") != index or config.get("warmup_triples", 0) < WARMUPS or config.get("measured_triples") != TRIPLES_PER_BATCH:
            fail(f"configuration mismatch in {path}")
        if len(records) != TRIPLES_PER_BATCH or measurement.get("compute_units_policy") != "all":
            fail(f"triple count or compute-unit policy mismatch in {path}")
        if len(measurement.get("source_sample_i_ds", [])) != 64:
            fail(f"fixed 64-input provenance missing in {path}")
        for key in ("conditions_at_start", "conditions_at_end"):
            condition = measurement.get(key, {})
            if condition.get("ac_power_state") not in {"AC Power", "Battery Power"} or condition.get("low_power_mode") not in {"0", "1"}:
                fail(f"invalid power/low-power condition in {path}")
        artifacts.append(data)

    source_ids = artifacts[0]["measurement"]["source_sample_i_ds"]
    if len(set(source_ids)) != 64 or any(a["measurement"]["source_sample_i_ds"] != source_ids for a in artifacts):
        fail("batch corpus provenance differs")
    all_records = [record for artifact in artifacts for record in artifact["measurement"]["raw_triple_records"]]
    for record in all_records:
        if tuple(record["execution_order"]) not in PERMUTATIONS:
            fail("unknown path permutation")
        if len(record["execution_order"]) != 3 or len(set(record["execution_order"])) != 3:
            fail("path permutation is not a three-way order")
        if not all(math.isfinite(record[key]) and record[key] > 0 for key in ("b2_milliseconds", "c1_milliseconds", "c1_source_reuse_milliseconds")):
            fail("non-positive/non-finite timing in raw records")

    for index, artifact in enumerate(artifacts):
        counts = Counter(tuple(record["execution_order"]) for record in artifact["measurement"]["raw_triple_records"])
        if counts != Counter({permutation: 40 for permutation in PERMUTATIONS}):
            fail(f"six-way order balance mismatch in batch {index}: {counts}")

    by_source: dict[str, set[tuple[str, ...]]] = defaultdict(set)
    for record in all_records:
        by_source[record["source_sample_id"]].add(tuple(record["execution_order"]))
    if set(by_source) != set(source_ids) or any(len(orders) < 2 for orders in by_source.values()):
        fail("repeated source samples do not span multiple execution orders")

    paths = {
        "B2": [record["b2_milliseconds"] for record in all_records],
        "C1": [record["c1_milliseconds"] for record in all_records],
        "C1-SR": [record["c1_source_reuse_milliseconds"] for record in all_records],
    }
    differences = {
        "B2_minus_C1": [b - c for b, c in zip(paths["B2"], paths["C1"])],
        "C1_minus_C1-SR": [c - sr for c, sr in zip(paths["C1"], paths["C1-SR"])],
        "B2_minus_C1-SR": [b - sr for b, sr in zip(paths["B2"], paths["C1-SR"])],
    }
    batches = {name: [values[index * TRIPLES_PER_BATCH : (index + 1) * TRIPLES_PER_BATCH] for index in range(BATCH_COUNT)] for name, values in differences.items()}
    statistics = {name: summary(values) for name, values in paths.items()}
    aggregate = {
        "statistics": statistics,
        "paired_statistics": {name: summary(values) for name, values in differences.items()},
        "paired_bootstrap_confidence_intervals": {name: bootstrap(batch_values) for name, batch_values in batches.items()},
        "c1_source_reuse_percentage_vs_c1": ((statistics["C1"]["p50"] - statistics["C1-SR"]["p50"]) / statistics["C1"]["p50"]) * 100,
        "c1_source_reuse_percentage_vs_b2": ((statistics["B2"]["p50"] - statistics["C1-SR"]["p50"]) / statistics["B2"]["p50"]) * 100,
    }
    output = {
        "schema_version": 1,
        "status": "r7_5_source_reuse_final",
        "run_id": args.run_id,
        "commit": args.expected_commit,
        "batch_count": BATCH_COUNT,
        "warmup_triples_per_batch": WARMUPS,
        "measured_triples_per_batch": TRIPLES_PER_BATCH,
        "permutation_repeats": 40,
        "permutations": [list(permutation) for permutation in sorted(PERMUTATIONS)],
        "compute_units_policy": "all",
        "timing_boundary": "one accepted NV12 input -> one stem submission -> persistent shared activation -> Core ML tail prediction; wall time per path",
        "environment": artifacts[0].get("environment", {}),
        "source_sample_ids": source_ids,
        "batch_execution_identities": [a["execution_identity"] for a in artifacts],
        "batch_artifacts": [str((args.input_dir / f"batch-{index:02d}.json").resolve().relative_to(Path(__file__).resolve().parents[1])) for index in range(BATCH_COUNT)],
        "aggregate": aggregate,
        "raw_triple_records": all_records,
        "quality": {"activation_max_absolute_error": max(a["measurement"]["activation_max_absolute_error"] for a in artifacts),
                    "c1_top1_agreement": min(a["measurement"]["c1_top1_agreement"] for a in artifacts),
                    "c1_source_reuse_top1_agreement": min(a["measurement"]["c1_source_reuse_top1_agreement"] for a in artifacts)},
        "raw_batch_sha256": [hashlib.sha256(json.dumps(a, sort_keys=True, separators=(",", ":")).encode()).hexdigest() for a in artifacts],
        "statistics_algorithm_version": "r7.5-three-way-block-bootstrap-v1",
        "bootstrap_seed": BOOTSTRAP_SEED,
        "bootstrap_replicate_count": BOOTSTRAP_REPLICATES,
        "bootstrap_block_size": BLOCK_SIZE,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(output, indent=2, sort_keys=True) + "\n")
    print(f"PASS R7.5 source-reuse aggregate: {args.output}")
    print(f"commit: {args.expected_commit}; batches: {BATCH_COUNT}; triples: {len(all_records)}")
    print(f"C1-SR vs C1 p50 percentage: {aggregate['c1_source_reuse_percentage_vs_c1']:.4f}")
    print(f"C1-SR vs C1 paired median CI: {aggregate['paired_bootstrap_confidence_intervals']['C1_minus_C1-SR']['median_difference']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
