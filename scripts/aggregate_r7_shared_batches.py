#!/usr/bin/env python3
"""Aggregate five independent repaired R7 B2/C1 batch artifacts.

The script deliberately recomputes all descriptive and paired-bootstrap values
from raw records. It never imports the historical aggregate artifact.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path


BATCH_COUNT = 5
PAIRS_PER_BATCH = 200
WARMUPS = 20
BLOCK_SIZE = 10
BOOTSTRAP_REPLICATES = 10_000
BOOTSTRAP_SEED = 0x50464A52


def nearest(values: list[float], percentile: float) -> float:
    ordered = sorted(values)
    return ordered[math.ceil(percentile * len(ordered)) - 1]


def summary(values: list[float]) -> dict[str, float]:
    p50 = nearest(values, 0.5)
    return {
        "p50": p50,
        "p95": nearest(values, 0.95),
        "mean": sum(values) / len(values),
        "median_absolute_deviation": nearest(sorted(abs(value - p50) for value in values), 0.5),
    }


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

    def next_int(self, upper_bound: int) -> int:
        threshold = ((1 << 64) - upper_bound) % upper_bound
        while True:
            value = self.next()
            if value >= threshold:
                return value % upper_bound


def bootstrap(batches: list[dict]) -> dict[str, dict[str, float]]:
    generator = SplitMix64(BOOTSTRAP_SEED)
    means: list[float] = []
    medians: list[float] = []
    for _ in range(BOOTSTRAP_REPLICATES):
        reconstructed: list[float] = []
        for _ in range(BATCH_COUNT):
            batch = batches[generator.next_int(len(batches))]["differences"]
            for start in range(0, PAIRS_PER_BATCH, BLOCK_SIZE):
                block_start = generator.next_int(len(batch) - BLOCK_SIZE + 1)
                reconstructed.extend(batch[block_start : block_start + BLOCK_SIZE])
        means.append(sum(reconstructed) / len(reconstructed))
        medians.append(nearest(reconstructed, 0.5))
    return {
        "mean_difference": {"lower": nearest(means, 0.025), "upper": nearest(means, 0.975)},
        "median_difference": {"lower": nearest(medians, 0.025), "upper": nearest(medians, 0.975)},
    }


def fail(message: str) -> None:
    raise SystemExit(f"FAIL R7 repaired aggregation: {message}")


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
        if data.get("status") != "mobilenetv2_direct_b2_c1_shared_batch":
            fail(f"unexpected status in {path}")
        if data.get("commit") != args.expected_commit:
            fail(f"commit mismatch in {path}")
        if config.get("batch_index") != index or config.get("measured_pairs") != PAIRS_PER_BATCH:
            fail(f"batch configuration mismatch in {path}")
        if config.get("warmup_iterations", 0) < WARMUPS:
            fail(f"warmups below contract in {path}")
        if len(measurement.get("raw_paired_records", [])) != PAIRS_PER_BATCH:
            fail(f"pair count mismatch in {path}")
        artifacts.append((path, data))

    commits = {data["commit"] for _, data in artifacts}
    if commits != {args.expected_commit}:
        fail("batch commits are not identical")
    source_ids = artifacts[0][1]["measurement"]["source_sample_ids"]
    if len(source_ids) != 64 or len(set(source_ids)) != 64:
        fail("fixed 64-input corpus provenance is missing")
    for _, data in artifacts[1:]:
        if data["measurement"]["source_sample_ids"] != source_ids:
            fail("batch corpus provenance differs")

    records: list[dict] = []
    batches: list[dict] = []
    batch_executions: list[dict] = []
    for path, data in artifacts:
        measurement = data["measurement"]
        batch_records = measurement["raw_paired_records"]
        orders = {"B2_then_C1": 0, "C1_then_B2": 0}
        source_counts: dict[str, int] = {}
        for record in batch_records:
            if record["batch_id"] != f"batch-{int(measurement['configuration']['batch_index']):02d}":
                fail(f"raw batch ID mismatch in {path}")
            if record["execution_order"] not in orders:
                fail(f"unknown execution order in {path}")
            orders[record["execution_order"]] += 1
            source_counts[record["source_sample_id"]] = source_counts.get(record["source_sample_id"], 0) + 1
            records.append(record)
        if orders != {"B2_then_C1": 100, "C1_then_B2": 100}:
            fail(f"order balance mismatch in {path}: {orders}")
        config = measurement["configuration"]
        batches.append({
            "batch_id": f"batch-{int(config['batch_index']):02d}",
            "differences": [record["b2_minus_c1_milliseconds"] for record in batch_records],
        })
        batch_executions.append({
            "batch_id": f"batch-{int(config['batch_index']):02d}",
            "execution_identity": data["execution_identity"],
            "artifact": str(path),
            "warmup_iterations": config["warmup_iterations"],
            "measured_pairs": config["measured_pairs"],
            "source_offset": config["source_offset"],
            "order_phase": config["order_phase"],
            "order_counts": orders,
            "source_counts": source_counts,
        })

    by_source: dict[str, set[str]] = {source_id: set() for source_id in source_ids}
    for record in records:
        by_source[record["source_sample_id"]].add(record["execution_order"])
    missing_both = [source_id for source_id, orders in by_source.items() if len(orders) != 2]
    if missing_both:
        fail(f"repeated samples missing both execution orders: {missing_both[:5]}")

    b2 = [record["b2_milliseconds"] for record in records]
    c1 = [record["c1_milliseconds"] for record in records]
    differences = [record["b2_minus_c1_milliseconds"] for record in records]
    first_measurement = artifacts[0][1]["measurement"]
    for _, data in artifacts[1:]:
        measurement = data["measurement"]
        for key in (
            "activation_max_absolute_error", "top1_agreement", "b2_rgb_logical_bytes",
            "b2_rgb_allocated_bytes", "c1_rgb_logical_bytes", "c1_rgb_allocated_bytes",
            "cpu_element_by_element_activation_copy_bytes", "compute_units_policy",
        ):
            if measurement[key] != first_measurement[key]:
                fail(f"batch resource/quality field differs: {key}")

    measurement = {
        "schema_version": 2,
        "configuration": {
            "warmup_iterations_per_batch": WARMUPS,
            "measured_pairs_per_batch": PAIRS_PER_BATCH,
            "batch_count": BATCH_COUNT,
            "validation_samples": 64,
            "batch_execution_mode": "five-separate-release-processes",
            "source_offsets": [entry["source_offset"] for entry in batch_executions],
            "order_phases": [entry["order_phase"] for entry in batch_executions],
        },
        "batch_executions": batch_executions,
        "raw_paired_records": records,
        "batch_differences": batches,
        "paired_bootstrap_confidence_interval": bootstrap(batches),
        "b2_statistics": summary(b2),
        "c1_statistics": summary(c1),
        "b2_minus_c1_statistics": summary(differences),
        "aggregate_percentage": ((nearest(b2, 0.5) - nearest(c1, 0.5)) / nearest(b2, 0.5)) * 100,
        "activation_max_absolute_error": first_measurement["activation_max_absolute_error"],
        "top1_agreement": first_measurement["top1_agreement"],
        "b2_rgb_logical_bytes": first_measurement["b2_rgb_logical_bytes"],
        "b2_rgb_allocated_bytes": first_measurement["b2_rgb_allocated_bytes"],
        "c1_rgb_logical_bytes": first_measurement["c1_rgb_logical_bytes"],
        "c1_rgb_allocated_bytes": first_measurement["c1_rgb_allocated_bytes"],
        "cpu_element_by_element_activation_copy_bytes": first_measurement["cpu_element_by_element_activation_copy_bytes"],
        "cpu_element_by_element_activation_copy_status": first_measurement["cpu_element_by_element_activation_copy_status"],
        "device_name": first_measurement["device_name"],
        "compute_units_policy": first_measurement["compute_units_policy"],
        "source_sample_ids": source_ids,
        "source_order_coverage": {source_id: sorted(by_source[source_id]) for source_id in source_ids},
        "validation_sample_count": 64,
        "statistics_algorithm_version": first_measurement["statistics_algorithm_version"],
        "bootstrap_seed": first_measurement["bootstrap_seed"],
        "bootstrap_replicate_count": first_measurement["bootstrap_replicate_count"],
        "bootstrap_batch_count": first_measurement["bootstrap_batch_count"],
        "bootstrap_pairs_per_batch": first_measurement["bootstrap_pairs_per_batch"],
        "bootstrap_block_size": first_measurement["bootstrap_block_size"],
        "aggregate_source": "recomputed from raw paired records by scripts/aggregate_r7_shared_batches.py",
    }
    output = {
        "schema_version": 2,
        "status": "r7_final_b2_c1_shared_repaired",
        "commit": args.expected_commit,
        "run_id": args.run_id,
        "environment": artifacts[0][1]["environment"],
        "model": artifacts[0][1]["model"],
        "measurement": measurement,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(output, indent=2, sort_keys=True) + "\n")
    print(f"PASS R7 repaired aggregation: {args.output}")
    print(f"commit: {args.expected_commit}")
    print(f"batches: {BATCH_COUNT} separate processes; records: {len(records)}")
    print(f"order balance: 100/100 per batch; both-order samples: {len(source_ids)}/{len(source_ids)}")
    print(f"b2_p50_ms: {summary(b2)['p50']:.6f}; c1_p50_ms: {summary(c1)['p50']:.6f}; aggregate_percent: {measurement['aggregate_percentage']:.6f}")
    print(f"sha256: {hashlib.sha256(args.output.read_bytes()).hexdigest()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
