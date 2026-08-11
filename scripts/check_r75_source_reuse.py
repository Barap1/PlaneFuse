#!/usr/bin/env python3
"""Fail-closed checker for the authoritative R7.5 three-way artifact."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from collections import Counter, defaultdict
from pathlib import Path

BATCHES = 5
TRIPLES = 240
BLOCK = 10
REPLICATES = 10_000
SEED = 0x50373542
PERMUTATIONS = {
    ("B2", "C1", "C1-SR"), ("B2", "C1-SR", "C1"),
    ("C1", "B2", "C1-SR"), ("C1", "C1-SR", "B2"),
    ("C1-SR", "B2", "C1"), ("C1-SR", "C1", "B2"),
}


def fail(message: str) -> None:
    raise SystemExit(f"FAIL R7.5 checker: {message}")


def near(actual: float, expected: float) -> bool:
    return math.isclose(actual, expected, rel_tol=1e-12, abs_tol=1e-12)


def nearest(values: list[float], percentile: float) -> float:
    return sorted(values)[math.ceil(percentile * len(values)) - 1]


def summary(values: list[float]) -> dict[str, float]:
    p50 = nearest(values, 0.5)
    return {"p50": p50, "p95": nearest(values, 0.95), "mean": sum(values) / len(values),
            "median_absolute_deviation": nearest([abs(value - p50) for value in values], 0.5)}


class SplitMix64:
    mask = (1 << 64) - 1

    def __init__(self) -> None:
        self.state = SEED

    def next(self) -> int:
        self.state = (self.state + 0x9E3779B97F4A7C15) & self.mask
        value = self.state
        value = ((value ^ (value >> 30)) * 0xBF58476D1CE4E5B9) & self.mask
        value = ((value ^ (value >> 27)) * 0x94D049BB133111EB) & self.mask
        return (value ^ (value >> 31)) & self.mask

    def index(self, upper: int) -> int:
        threshold = ((1 << 64) - upper) % upper
        while True:
            value = self.next()
            if value >= threshold:
                return value % upper


def bootstrap(batches: list[list[float]]) -> dict[str, dict[str, float]]:
    generator = SplitMix64()
    means, medians = [], []
    for _ in range(REPLICATES):
        reconstructed = []
        for _ in range(BATCHES):
            batch = batches[generator.index(len(batches))]
            for _ in range(0, TRIPLES, BLOCK):
                start = generator.index(len(batch) - BLOCK + 1)
                reconstructed.extend(batch[start : start + BLOCK])
        means.append(sum(reconstructed) / len(reconstructed))
        medians.append(nearest(reconstructed, 0.5))
    return {"mean_difference": {"lower": nearest(means, .025), "upper": nearest(means, .975)},
            "median_difference": {"lower": nearest(medians, .025), "upper": nearest(medians, .975)}}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("artifact", type=Path)
    parser.add_argument("--expected-commit", required=True)
    args = parser.parse_args()
    data = json.loads(args.artifact.read_text())
    if data.get("status") != "r7_5_source_reuse_final" or data.get("commit") != args.expected_commit:
        fail("status or generating commit mismatch")
    if (data.get("batch_count"), data.get("warmup_triples_per_batch"), data.get("measured_triples_per_batch")) != (BATCHES, 20, TRIPLES):
        fail("batch/warmup/triple protocol mismatch")
    if data.get("compute_units_policy") != "all" or data.get("statistics_algorithm_version") != "r7.5-three-way-block-bootstrap-v1":
        fail("protocol metadata mismatch")
    if (data.get("bootstrap_seed"), data.get("bootstrap_replicate_count"), data.get("bootstrap_block_size")) != (SEED, REPLICATES, BLOCK):
        fail("bootstrap metadata mismatch")
    source_ids = data.get("source_sample_ids", [])
    records = data.get("raw_triple_records", [])
    if len(source_ids) != 64 or len(set(source_ids)) != 64 or len(records) != BATCHES * TRIPLES:
        fail("fixed corpus or raw-record cardinality mismatch")

    by_batch: dict[str, list[dict]] = defaultdict(list)
    by_source: dict[str, set[tuple[str, ...]]] = defaultdict(set)
    for record in records:
        order = tuple(record.get("execution_order", []))
        if order not in PERMUTATIONS or record.get("source_sample_id") not in source_ids:
            fail("invalid raw source/order record")
        if not all(isinstance(record.get(key), (int, float)) and math.isfinite(record[key]) and record[key] > 0 for key in ("b2_milliseconds", "c1_milliseconds", "c1_source_reuse_milliseconds")):
            fail("invalid raw timing")
        by_batch[record["batch_id"]].append(record)
        by_source[record["source_sample_id"]].add(order)
    if set(by_batch) != {f"batch-{i:02d}" for i in range(BATCHES)} or any(len(v) != TRIPLES for v in by_batch.values()):
        fail("batch IDs/cardinality mismatch")
    if set(by_source) != set(source_ids) or any(len(v) < 2 for v in by_source.values()):
        fail("repeated source samples lack multiple execution orders")
    for batch_id, batch in by_batch.items():
        counts = Counter(tuple(record["execution_order"]) for record in batch)
        if counts != Counter({permutation: 40 for permutation in PERMUTATIONS}):
            fail(f"six-permutation balance mismatch in {batch_id}")

    paths = {"B2": [r["b2_milliseconds"] for r in records], "C1": [r["c1_milliseconds"] for r in records], "C1-SR": [r["c1_source_reuse_milliseconds"] for r in records]}
    differences = {"B2_minus_C1": [b - c for b, c in zip(paths["B2"], paths["C1"])],
                   "C1_minus_C1-SR": [c - sr for c, sr in zip(paths["C1"], paths["C1-SR"])],
                   "B2_minus_C1-SR": [b - sr for b, sr in zip(paths["B2"], paths["C1-SR"])]}
    aggregate = data.get("aggregate", {})
    for name, values in paths.items():
        for key, expected in summary(values).items():
            if not near(aggregate.get("statistics", {}).get(name, {}).get(key), expected):
                fail(f"statistics not recomputed for {name}.{key}")
    for name, values in differences.items():
        for key, expected in summary(values).items():
            if not near(aggregate.get("paired_statistics", {}).get(name, {}).get(key), expected):
                fail(f"paired statistics not recomputed for {name}.{key}")
        batch_values = [values[i * TRIPLES : (i + 1) * TRIPLES] for i in range(BATCHES)]
        if aggregate.get("paired_bootstrap_confidence_intervals", {}).get(name) != bootstrap(batch_values):
            fail(f"bootstrap not recomputed for {name}")
    expected_c1 = ((summary(paths["C1"])["p50"] - summary(paths["C1-SR"])["p50"]) / summary(paths["C1"])["p50"]) * 100
    expected_b2 = ((summary(paths["B2"])["p50"] - summary(paths["C1-SR"])["p50"]) / summary(paths["B2"])["p50"]) * 100
    if not near(aggregate.get("c1_source_reuse_percentage_vs_c1"), expected_c1) or not near(aggregate.get("c1_source_reuse_percentage_vs_b2"), expected_b2):
        fail("percentage comparison not recomputed")

    quality = data.get("quality", {})
    if quality.get("activation_max_absolute_error", 1) > 1e-5 or quality.get("c1_source_reuse_top1_agreement", 0) < .995:
        fail("R7.5 quality threshold failed")
    if not all(math.isfinite(quality.get(key, float("nan"))) for key in ("c1_source_reuse_top5_set_agreement", "c1_source_reuse_top5_ranking_agreement", "c1_source_reuse_probability_maximum_absolute_error", "c1_source_reuse_probability_mean_l1_distance")):
        fail("full top-5/probability quality summary is missing")
    if len(quality.get("samples", [])) != 64:
        fail("full per-sample quality report is missing")
    print(f"PASS R7.5 source-reuse checker: {args.artifact}")
    print(f"commit: {args.expected_commit}; raw triples: {len(records)}; source orders: 64/64")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
