# PlaneFuse public claims ledger

Nothing quantitative may be presented in README, Devpost, screenshots, or video as a fact unless it is recorded here with evidence.

## Claim status values

- PROPOSED - desired claim, not yet proven.
- VERIFIED - backed by committed reproducible evidence.
- REJECTED - measured false or misleading; do not use.
- QUALIFIED - true only under stated conditions.

## C001 - No full RGB intermediate in PlaneFuse Pipeline C

Status: VERIFIED

Claim wording: "For the supported four-output stem, PlaneFuse's native path produces the first model features directly from Y and UV planes without materializing a full RGB intermediate."

Required evidence:

- implementation/dataflow inspection;
- allocation/buffer graph or profiler capture;
- supported format/model scope documented.

Evidence files: `Sources/PlaneFuseCore/Shaders/NV12NativeStem.metal`, `Sources/PlaneFuseCore/MetalNativeStem.swift`, `Tests/PlaneFuseCoreTests/MetalNativeStemTests.swift`, `benchmarks/results/m4-fair-abc-confirm.json`

## C002 - PlaneFuse improves frontend latency vs optimized RGB

Status: REJECTED

Claim wording: "PlaneFuse improves isolated frontend latency vs optimized RGB." This is not supported by confirmation data: C was 0.74% and 1.03% slower in the two 100-iteration confirmation batches.

Required evidence:

- Pipeline B and C same-work benchmark;
- confirmation/final run;
- commit/system metadata;
- correctness pass.

Evidence files: `benchmarks/results/m4-fair-abc-confirm.json`, `benchmarks/results/m4-fair-abc-confirm2.json`

## C003 - PlaneFuse improves end-to-end inference latency

Status: VERIFIED

Claim wording: "On the supported 640x480 M1 four-output stem fixture, Pipeline C reduced end-to-end frontend-plus-stem p50 latency by 51.55% versus Pipeline B in confirmation batch 1; the second batch measured 50.93%."

Required evidence:

- real-model B/C benchmark;
- same model/input/build;
- quality agreement;
- final repeated results.

Evidence files: `benchmarks/results/m4-fair-abc-confirm.json`, `benchmarks/results/m4-fair-abc-confirm2.json`, `benchmarks/best.json`

## C004 - Model behavior is preserved

Status: QUALIFIED

Claim wording: "The supported four-output stem produced max absolute feature error 1.4305115e-6 against the paired B output in both 100-iteration confirmation batches, below the 1e-5 GPU parity threshold." This is a fixed-stem equivalence result, not real-model/task quality.

Required evidence:

- activation comparison;
- fixed validation corpus;
- task/output agreement report.

Evidence files: `benchmarks/results/m4-fair-abc-confirm.json`, `benchmarks/results/m4-fair-abc-confirm2.json`

## C005 - Fully local Mobile AI experience

Status: PROPOSED

Claim wording target: "PlaneFuse Live performs the demonstrated vision inference locally on Apple Silicon without a cloud inference dependency."

Required evidence:

- architecture/runtime inspection;
- demo with networking not required for inference;
- setup docs.

Evidence files: TBD
