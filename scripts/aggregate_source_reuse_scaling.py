#!/usr/bin/env python3
"""Aggregate the controlled, stem-only C1/C1-SR channel-width experiment."""
import argparse
import json
import math
from pathlib import Path


WIDTHS = [8, 16, 24, 32, 40, 48]
TILES = 28 * 28
OUTPUTS_PER_TILE = 4 * 4
TAPS_PER_OUTPUT = 3 * 3


def nearest(values, percentile):
    ordered = sorted(values)
    return ordered[max(1, math.ceil(percentile * len(ordered))) - 1]


def summary(values):
    median = nearest(values, 0.5)
    return {
        "count": len(values),
        "p50_ms": nearest(values, 0.5),
        "p95_ms": nearest(values, 0.95),
        "mean_ms": sum(values) / len(values),
        "median_absolute_deviation_ms": nearest([abs(value - median) for value in values], 0.5),
    }


def staged_samples():
    luma = 0
    chroma = 0
    for tile_y in range(28):
        for tile_x in range(28):
            source_x = tile_x * 8
            source_y = tile_y * 8
            luma += sum(1 for local_y in range(9) for local_x in range(9)
                        if source_x + local_x < 224 and source_y + local_y < 224)
            chroma += sum(1 for local_y in range(5) for local_x in range(5)
                          if tile_x * 4 + local_x < 112 and tile_y * 4 + local_y < 112)
    return luma, chroma


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-dir", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--expected-commit", required=True)
    parser.add_argument("--run-id", required=True)
    args = parser.parse_args()

    paths = sorted(args.input_dir.glob("batch-*.json"))
    if len(paths) != 3:
        raise SystemExit(f"expected 3 raw scaling batches, found {len(paths)}")
    batches = [json.loads(path.read_text()) for path in paths]
    if any(batch.get("commit") != args.expected_commit for batch in batches):
        raise SystemExit("raw scaling batch commit mismatch")
    if [batch.get("batch_index") for batch in batches] != [0, 1, 2]:
        raise SystemExit("raw scaling batch indices are not 0, 1, 2")
    if any(batch.get("input_count") != 16 for batch in batches):
        raise SystemExit("raw scaling input count mismatch")

    luma_staged, chroma_staged = staged_samples()
    widths = []
    for width in WIDTHS:
        records = []
        for batch in batches:
            record = next((item for item in batch["widths"] if item["active_output_channels"] == width), None)
            if record is None:
                raise SystemExit(f"missing width {width}")
            if record["activation_max_absolute_error"] > 1e-4:
                raise SystemExit(f"parity failure at width {width}")
            records.append(record)
        c1_wall = [sample for record in records for sample in record["c1"]["wall_milliseconds"]]
        sr_wall = [sample for record in records for sample in record["c1_source_reuse"]["wall_milliseconds"]]
        c1_gpu = [sample for record in records for sample in record["c1"]["gpu_milliseconds"]]
        sr_gpu = [sample for record in records for sample in record["c1_source_reuse"]["gpu_milliseconds"]]
        original_luma = width * 112 * 112 * TAPS_PER_OUTPUT
        original_chroma = original_luma
        staged_total = luma_staged + chroma_staged
        original_total = original_luma + original_chroma
        widths.append({
            "active_output_channels": width,
            "c1": {"wall": summary(c1_wall), "gpu": summary(c1_gpu)},
            "c1_source_reuse": {"wall": summary(sr_wall), "gpu": summary(sr_gpu)},
            "speedup_percent_by_wall_p50": ((summary(c1_wall)["p50_ms"] - summary(sr_wall)["p50_ms"]) / summary(c1_wall)["p50_ms"]) * 100,
            "parity": {"max_activation_absolute_error": max(record["activation_max_absolute_error"] for record in records), "status": "PASS"},
            "analytical_scaling": {
                "luma_samples_staged_per_source_tile": 81,
                "chroma_samples_staged_per_source_tile": 25,
                "output_spatial_positions_sharing_tile": OUTPUTS_PER_TILE,
                "active_output_channels_sharing_tile": width,
                "original_luma_source_reads_approx": original_luma,
                "original_chroma_source_reads_approx": original_chroma,
                "source_tile_luma_reads_total": luma_staged,
                "source_tile_chroma_reads_total": chroma_staged,
                "source_read_reuse_factor_approx": original_total / staged_total,
                "note": "Counts follow the shader's 28x28 tile grid and exclude invalid edge loads; they describe source sampling, not total instructions."
            }
        })

    artifact = {
        "schema_version": 1,
        "status": "source_reuse_scaling_stem_only",
        "run_id": args.run_id,
        "commit": args.expected_commit,
        "experiment": {
            "name": "stem-only source-reuse scaling microbenchmark",
            "purpose": "isolate C1-SR source-tile reuse as active output-channel width increases",
            "active_output_channel_widths": WIDTHS,
            "input_geometry": "224x224 NV12 BT.601 video-range",
            "tail_included": False,
            "fixed_source_set": "first 48 samples in proof/m5-validation-corpus.json, split into three deterministic 16-sample batches",
            "warmup_iterations_per_sample": 4,
            "measured_iterations_per_sample": 4,
            "execution_order": "C1 and C1-SR alternate first position by batch and iteration",
            "release_build": True,
        },
        "source_reuse_geometry": {
            "tile_grid": [28, 28],
            "output_tile": [4, 4],
            "luma_tile": [9, 9],
            "chroma_tile": [5, 5],
            "luma_samples_staged_per_tile": 81,
            "chroma_samples_staged_per_tile": 25,
            "luma_samples_staged_total": luma_staged,
            "chroma_samples_staged_total": chroma_staged,
            "explanation": "C1 repeats source sampling per output channel and spatial position. C1-SR stages each tile once, then shares it across 16 output positions and the active channel groups."
        },
        "batches": [f"proof/final/source-reuse-scaling-batches/{args.run_id}/{path.name}" for path in paths],
        "widths": widths,
        "quality": {"status": "PASS", "maximum_allowed_activation_error": 1e-4},
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(artifact, indent=2, sort_keys=True) + "\n")
    print(f"PASS source-reuse scaling aggregate: {args.output}")
    for result in widths:
        print(f"channels={result['active_output_channels']} c1_p50_ms={result['c1']['wall']['p50_ms']:.4f} c1_sr_p50_ms={result['c1_source_reuse']['wall']['p50_ms']:.4f} speedup_percent={result['speedup_percent_by_wall_p50']:.2f}")


if __name__ == "__main__":
    main()
