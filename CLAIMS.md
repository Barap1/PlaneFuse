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

Evidence files: `Sources/PlaneFuseCore/Shaders/NV12NativeStem.metal`, `Sources/PlaneFuseCore/MetalNativeStem.swift`, `Tests/PlaneFuseCoreTests/MetalNativeStemTests.swift`, `benchmarks/results/m4-fair-abc-equal-confirm1.json`

## C002 - PlaneFuse improves frontend latency vs optimized RGB

Status: REJECTED

Claim wording: "PlaneFuse improves isolated frontend latency vs optimized RGB." This is not supported by equal-submission confirmation data: C was 0.82% slower in one batch and 1.40% faster in the other.

Required evidence:

- Pipeline B and C same-work benchmark;
- confirmation/final run;
- commit/system metadata;
- correctness pass.

Evidence files: `benchmarks/results/m4-fair-abc-equal-confirm1.json`, `benchmarks/results/m4-fair-abc-equal-confirm2.json`

## C003 - PlaneFuse improves end-to-end inference latency

Status: VERIFIED

Claim wording: "On the supported 640x480 M1 four-output stem fixture, with equal one-submission B/C boundaries, Pipeline C reduced end-to-end frontend-plus-stem p50 latency by 16.34% versus Pipeline B in confirmation batch 1; the second batch measured 10.24%."

Required evidence:

- same-fixture B/C benchmark;
- same model/input/build;
- quality agreement;
- final repeated results.

Evidence files: `benchmarks/results/m4-fair-abc-equal-confirm1.json`, `benchmarks/results/m4-fair-abc-equal-confirm2.json`, `benchmarks/best.json`

## C004 - Model behavior is preserved

Status: QUALIFIED

Claim wording: "The supported four-output stem produced max absolute feature error 1.4305115e-6 against the paired B output in both 100-iteration confirmation batches, below the 1e-5 GPU parity threshold." This is a fixed-stem equivalence result, not real-model/task quality.

Required evidence:

- activation comparison;
- fixed validation corpus;
- task/output agreement report.

Evidence files: `benchmarks/results/m4-fair-abc-equal-confirm1.json`, `benchmarks/results/m4-fair-abc-equal-confirm2.json`

## C005 - Fully local Mobile AI experience

Status: PROPOSED

Claim wording target: "PlaneFuse Live performs the demonstrated vision inference locally on Apple Silicon without a cloud inference dependency."

Required evidence:

- architecture/runtime inspection;
- demo with networking not required for inference;
- setup docs.

Evidence files: TBD

## C006 - MobileNetV2 native-plane stem preserves the real pretrained tail

Status: VERIFIED

Claim wording: "For Apple’s MobileNetV2 ImageNet model, PlaneFuse transforms the pretrained 3x3 stride-2 Conv+BatchNorm+ReLU6 input stem to read NV12 planes directly, then runs the unchanged compiled model tail."

Required evidence:

- exact source-model hash and graph boundary;
- generated stem coefficients and compiled tail;
- same-tail B/C benchmark;
- parity and output-agreement report.

Evidence files: `proof/m5-mobilenetv2.md`, `proof/m5-validation-corpus.json`, `scripts/prepare_mobilenetv2.py`, `benchmarks/results/m5-mobilenetv2-final.json`, `benchmarks/results/m5-mobilenetv2-final2.json`

## C007 - MobileNetV2 B/C parity and task agreement

Status: VERIFIED

Claim wording: "Across two M5 confirmation batches, Pipeline B and Pipeline C had 100% top-1 output agreement over 8 deterministic NV12 validation samples; maximum first-activation absolute difference was 9.059906e-6, below the 1e-5 GPU threshold."

Evidence files: `proof/m5-validation-corpus.json`, `benchmarks/results/m5-mobilenetv2-final.json`, `benchmarks/results/m5-mobilenetv2-final2.json`

## C008 - MobileNetV2 Pipeline C eliminates the full RGB intermediate

Status: VERIFIED

Claim wording: "At the 224x224 MobileNetV2 stem boundary, Pipeline B allocates an 802,816-byte RGBA32Float intermediate while Pipeline C records zero RGBA32Float intermediate bytes."

Evidence files: `Sources/PlaneFuseCore/Shaders/NV12MobileNetV2RGB.metal`, `Sources/PlaneFuseCore/Shaders/NV12MobileNetV2Stem.metal`, `benchmarks/results/m5-mobilenetv2-final.json`, `benchmarks/results/m5-mobilenetv2-final2.json`
