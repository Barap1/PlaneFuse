# PlaneFuse benchmark and correctness contract

This file defines what counts as a defensible performance result.

## 1. Core rule

Never optimize against an unfair baseline.

Every important performance claim should distinguish:

- Pipeline A: representative ordinary/reference pipeline;
- Pipeline B: properly optimized RGB/Metal pipeline;
- Pipeline C: PlaneFuse native-plane pipeline.

The strongest PlaneFuse claim is C vs B.

## 2. Same-work comparison

A/B/C comparisons must use, as closely as technically possible:

- same device;
- same OS/Xcode/runtime versions;
- same model weights;
- same input frames;
- same image size;
- same color/range semantics;
- same output/task;
- same numerical precision unless the precision change is itself explicit;
- same build optimization level;
- same measurement region definition.

Do not compare Debug B against Release C.

## 3. Environment record

Every confirmation/full result must record:

- Git commit hash;
- timestamp;
- `uname -m`;
- Mac model/chip if obtainable without private identifiers;
- physical memory size;
- macOS version;
- Xcode version;
- Swift version;
- Metal feature/runtime details needed to reproduce;
- build configuration;
- model identifier/version/license source;
- input dimensions/format;
- benchmark iteration settings.

Do not store serial numbers, usernames, absolute home paths, or other personal identifiers in committed benchmark artifacts.

## 4. Benchmark tiers

Exact iteration counts may be adjusted if an iteration is unusually long, but the tier intent must remain.

### Quick

Purpose: answer "did this change obviously help or hurt?"

Suggested default:

- enough warmup to eliminate compilation/cache startup;
- ~20-50 measured iterations;
- report median/p50 and p95;
- compact output only.

Use during normal experiments.

### Confirm

Purpose: verify an apparent improvement before accepting a performance claim.

Suggested default:

- larger warmup;
- multiple independent batches;
- ~100-300 measured iterations total when runtime permits;
- report p50, p95, mean, and a robust dispersion statistic;
- compare candidate to best/baseline under the same run conditions.

### Full/final

Purpose: final proof artifacts.

Requirements:

- repeated batches;
- stable system conditions;
- A, B, and C in an order that avoids systematic bias when practical;
- distribution metrics, not one cherry-picked run;
- correctness checked on the same build;
- system metadata captured;
- raw machine-readable results preserved.

## 5. Thermal and power conditions

For latency benchmarking, prefer stable reproducible conditions:

- record whether Mac is on AC power;
- record Low Power Mode state if relevant/accessible;
- avoid starting immediately after a heavy compile if thermals are obviously elevated;
- do not intentionally cool/heat one pipeline differently from another;
- interleave or repeat A/B/C if drift is visible.

If the project makes energy/power claims, define a separate energy measurement protocol rather than inferring power from speed.

## 6. Measurement boundaries

Report both isolated and user-level costs when possible.

### Frontend/stem latency

Measure the region PlaneFuse directly changes. Clearly define start/end points.

### End-to-end inference latency

Measure from the same input-ready point through the same final model output for B and C.

### Capture-to-result latency

If the final demo can measure real camera capture-to-result latency reliably, treat it as a separate user-experience metric.

Never mix boundaries in one speedup percentage.

## 7. Memory/allocation claims

The statement "PlaneFuse materializes zero full RGB intermediate tensors" must be established structurally/instrumentally, not assumed.

Evidence can include:

- code/dataflow inspection;
- allocation instrumentation;
- Metal/Xcode captures;
- known buffer graph;
- memory trace screenshots.

Peak-memory claims require actual measurement.

## 8. Bandwidth claims

Do not calculate a speculative "bandwidth reduction" from tensor sizes and present it as measured GPU bandwidth.

Distinguish:

- theoretical bytes avoided;
- allocated bytes observed;
- profiler-estimated/recorded bandwidth;
- measured end-to-end effect.

Label each clearly.

## 9. Correctness tiers

### Reference math parity

For algebraic transforms implemented at comparable precision, target very tight numerical agreement. Initial goal:

- max absolute activation error <= 1e-4 when the same floating-point semantics make that reasonable;
- investigate any systematic mismatch.

This threshold is a starting target, not permission to hide differences caused by actual color/sampling semantics.

### GPU/native-stem parity

GPU precision, interpolation, and fused arithmetic may change floating-point ordering.

Initial requirements should include:

- high activation/embedding cosine similarity;
- bounded max/mean error;
- no visible systematic spatial/color failure;
- documented difference from reference precision.

The exact threshold must be established during M1/M3 and recorded in `DECISIONS.md` before performance optimization begins.

### Task-level quality

For the real model, collect a fixed validation corpus and report metrics appropriate to the workload, such as:

- top-1/top-k agreement;
- embedding cosine similarity;
- retrieval ranking agreement;
- accuracy delta if ground truth is available.

A useful initial target for an equivalence-style optimization is >=99.5% task/output agreement or an equivalently strong model-specific quality measure. Do not silently accept a lower quality tradeoff.

## 10. Acceptance of a performance change

An experiment may be accepted only if:

1. correctness passes;
2. quick benchmark shows an improvement beyond obvious noise;
3. important wins receive a confirmation run;
4. improvement does not merely move cost outside the measured region;
5. code complexity is justified by the gain;
6. result is recorded with commit hash.

For tiny changes around the noise floor, reject or mark inconclusive.

## 11. `benchmarks/best.json`

This file represents the best verified result, not the most recent run.

It should eventually include fields similar to:

```json
{
  "schema_version": 1,
  "commit": "...",
  "device_class": "Apple Silicon",
  "model": "...",
  "input": "NV12 ...",
  "correctness": {
    "pass": true,
    "metric": "...",
    "value": 0.0
  },
  "pipeline_b": {
    "frontend_p50_ms": 0.0,
    "e2e_p50_ms": 0.0
  },
  "pipeline_c": {
    "frontend_p50_ms": 0.0,
    "e2e_p50_ms": 0.0
  },
  "delta": {
    "frontend_percent": 0.0,
    "e2e_percent": 0.0
  },
  "evidence": []
}
```

Do not populate fake zeros and call them results. Until measurements exist, use null values/status fields.

## 12. Final result presentation

The README should show:

- hardware/software test environment;
- A/B/C definitions;
- actual measured table;
- quality/parity table;
- concise explanation of what changed;
- how to reproduce;
- links/paths to raw result artifacts.

Every headline percentage must be traceable to committed raw evidence.
