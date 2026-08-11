#!/usr/bin/env python3
"""Fail-closed checker for the repaired five-process R7 B2/C1 artifact."""

from __future__ import annotations

import argparse
import json
import math
from collections import Counter, defaultdict
from pathlib import Path

from aggregate_r7_shared_batches import BATCH_COUNT, BOOTSTRAP_REPLICATES, BOOTSTRAP_SEED, BLOCK_SIZE, PAIRS_PER_BATCH, WARMUPS, bootstrap, summary


def fail(message: str) -> None:
    raise SystemExit(f"FAIL R7 repaired shared benchmark: {message}")


def same(actual: float, expected: float) -> bool:
    return math.isclose(actual, expected, rel_tol=1e-12, abs_tol=1e-12)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("artifact", nargs="?", default="proof/r7-final-b2-c1-shared-repaired.json")
    parser.add_argument("--expected-commit", required=True)
    args = parser.parse_args()
    path = Path(args.artifact)
    if not path.is_file():
        fail(f"missing artifact {path}")
    data = json.loads(path.read_text())
    if data.get("status") != "r7_final_b2_c1_shared_repaired":
        fail(f"unexpected status {data.get('status')!r}")
    if data.get("commit") != args.expected_commit:
        fail(f"commit mismatch: {data.get('commit')} != {args.expected_commit}")
    measurement = data.get("measurement", {})
    config = measurement.get("configuration", {})
    if config.get("batch_execution_mode") != "five-separate-release-processes":
        fail("batch execution mode is not five separate Release processes")
    if config.get("batch_count") != BATCH_COUNT or config.get("measured_pairs_per_batch") != PAIRS_PER_BATCH:
        fail("fixed five-by-200 cardinality is missing")
    if config.get("warmup_iterations_per_batch", 0) < WARMUPS:
        fail("per-batch warmup count is below 20")
    executions = measurement.get("batch_executions", [])
    if len(executions) != BATCH_COUNT:
        fail("batch execution identity count is not five")
    identities = [entry.get("execution_identity") for entry in executions]
    if len(set(identities)) != BATCH_COUNT or any(not identity for identity in identities):
        fail("batch execution identities are missing or duplicated")

    records = measurement.get("raw_paired_records", [])
    if len(records) != BATCH_COUNT * PAIRS_PER_BATCH:
        fail("raw record count is not 1,000")
    by_batch: dict[str, list[dict]] = defaultdict(list)
    by_source: dict[str, set[str]] = defaultdict(set)
    for record in records:
        batch_id = record.get("batch_id")
        if batch_id not in {f"batch-{index:02d}" for index in range(BATCH_COUNT)}:
            fail(f"unknown raw batch ID {batch_id!r}")
        if record.get("execution_order") not in {"B2_then_C1", "C1_then_B2"}:
            fail("unknown execution order")
        by_batch[batch_id].append(record)
        by_source[record["source_sample_id"]].add(record["execution_order"])
    if set(by_batch) != {f"batch-{index:02d}" for index in range(BATCH_COUNT)}:
        fail("not all five batch IDs appear in raw records")
    for index in range(BATCH_COUNT):
        batch_id = f"batch-{index:02d}"
        batch_records = by_batch[batch_id]
        if len(batch_records) != PAIRS_PER_BATCH:
            fail(f"{batch_id} does not contain exactly 200 records")
        counts = Counter(record["execution_order"] for record in batch_records)
        if counts != Counter({"B2_then_C1": 100, "C1_then_B2": 100}):
            fail(f"{batch_id} order balance is {dict(counts)}")
        execution = executions[index]
        if execution.get("batch_id") != batch_id or execution.get("measured_pairs") != PAIRS_PER_BATCH:
            fail(f"{batch_id} execution identity/provenance mismatch")
        if execution.get("order_counts") != {"B2_then_C1": 100, "C1_then_B2": 100}:
            fail(f"{batch_id} stored order counts mismatch")
    if len(by_source) != 64:
        fail(f"expected 64 unique source samples, got {len(by_source)}")
    if any(len(orders) != 2 for orders in by_source.values()):
        fail("at least one repeated source sample lacks both execution orders")

    b2 = [record["b2_milliseconds"] for record in records]
    c1 = [record["c1_milliseconds"] for record in records]
    differences = [record["b2_minus_c1_milliseconds"] for record in records]
    for key, values in (("b2_statistics", b2), ("c1_statistics", c1), ("b2_minus_c1_statistics", differences)):
        expected = summary(values)
        actual = measurement.get(key, {})
        for metric, value in expected.items():
            if not same(actual.get(metric), value):
                fail(f"{key}.{metric} was not recomputed from raw samples")
    expected_percentage = ((summary(b2)["p50"] - summary(c1)["p50"]) / summary(b2)["p50"]) * 100
    if not same(measurement.get("aggregate_percentage"), expected_percentage):
        fail("aggregate percentage was not recomputed from raw samples")
    expected_batches = [{"batch_id": f"batch-{index:02d}", "differences": [record["b2_minus_c1_milliseconds"] for record in by_batch[f"batch-{index:02d}"]]} for index in range(BATCH_COUNT)]
    if measurement.get("batch_differences") != expected_batches:
        fail("stored batch differences do not match raw samples")
    expected_bootstrap = bootstrap(expected_batches)
    if measurement.get("paired_bootstrap_confidence_interval") != expected_bootstrap:
        fail("paired bootstrap interval does not match deterministic raw-sample recomputation")
    if measurement.get("bootstrap_seed") != BOOTSTRAP_SEED or measurement.get("bootstrap_replicate_count") != BOOTSTRAP_REPLICATES or measurement.get("bootstrap_block_size") != BLOCK_SIZE:
        fail("bootstrap metadata is not deterministic contract metadata")
    for execution in executions:
        artifact_name = execution.get("artifact", "")
        if artifact_name.startswith("/") or "/Users/" in artifact_name or "\\" in artifact_name:
            fail("batch artifact path leaks a local absolute path")
    print(f"PASS R7 repaired shared benchmark: {path}")
    print(f"commit: {args.expected_commit}; batches: 5; pairs: 1000; both-order samples: 64/64")
    print("statistics, paired bootstrap, order balance, and batch provenance recomputed from raw records")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
