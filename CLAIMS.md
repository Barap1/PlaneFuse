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

Status: VERIFIED

Claim wording target: "PlaneFuse Live performs the demonstrated vision inference locally on Apple Silicon without a cloud inference dependency."

Required evidence:

- architecture/runtime inspection;
- real local sample inference with networking not required;
- camera path that reports no metrics when permission or assets are unavailable;
- setup docs.

Evidence files: `Sources/PlaneFuseLive/main.swift`, `proof/m9-live.md`, `proof/m8-developer-workflow.md`

## C009 - PlaneFuse Live preserves the native-plane claim at camera input

Status: QUALIFIED

Claim wording: "The PlaneFuse Live camera adapter captures video-range NV12, performs the supported center-crop/nearest resize directly on Y and UV planes, then compares the same local MobileNetV2 tail after B and C stems. It does not claim a camera result when permission, assets, or the input contract is unavailable."

Evidence files: `Sources/PlaneFuseLive/main.swift`, `DEMO_PLAN_V2.md`, `proof/m9-live.md`

## C010 - Current release-state MobileNetV2 confirmation

Status: VERIFIED

Claim wording: "At release-state commit `139c92a`, the current 100-iteration MobileNetV2 confirmation measured equal-submission Pipeline C p50 at 50.8605 ms versus Pipeline B at 51.8460 ms (1.90098% lower); frontend p50 was 0.22821 ms versus 0.50075 ms (54.4267% lower). B's logical RGBA32Float intermediate payload was 802,816 bytes and C recorded zero bytes for that intermediate, with B/C max activation error 9.298325e-6 and 100% top-1 agreement over four hashed corpus images. Actual Metal allocation is not asserted by this artifact."

Evidence files: `benchmarks/results/m10-mobilenetv2-confirm-current.json`, `benchmarks/final-matrix.json`, `proof/m10-evidence-index.md`

## C006 - MobileNetV2 native-plane stem preserves the real pretrained tail

Status: VERIFIED

Claim wording: "For Apple’s MobileNetV2 ImageNet model, PlaneFuse transforms the pretrained 3x3 stride-2 Conv+BatchNorm+ReLU6 input stem to read NV12 planes directly, then runs the unchanged compiled model tail."

Required evidence:

- exact source-model hash and graph boundary;
- generated stem coefficients and compiled tail;
- same-tail B/C benchmark;
- parity and output-agreement report.

Evidence files: `proof/m5-mobilenetv2.md`, `proof/m5-validation-corpus.json`, `proof/m5-corpus/`, `scripts/prepare_mobilenetv2.py`, `models/derived/manifest.json`, `benchmarks/results/m5-mobilenetv2-confirm1.json`, `benchmarks/results/m5-mobilenetv2-confirm2.json`

## C007 - MobileNetV2 B/C parity and task agreement

Status: VERIFIED

Claim wording: "Across two 100-iteration M5 confirmation batches, Pipeline B and Pipeline C had 100% top-1 agreement over four hashed real-image NV12 samples; maximum first-activation absolute difference was 9.298325e-6, below the unchanged 1e-5 GPU threshold. The independent original-derived CPU-only Core ML stem reference differed by at most 3.904105e-5, within the repository's 1e-4 reference-math tier, and FullArray versus split StemArray+tail agreement was 100%."

Evidence files: `proof/m5-validation-corpus.json`, `benchmarks/results/m5-mobilenetv2-confirm1.json`, `benchmarks/results/m5-mobilenetv2-confirm2.json`, `Tests/PlaneFuseCoreTests/MobileNetV2PretrainedParityTests.swift`

## C008 - MobileNetV2 Pipeline C eliminates the full RGB intermediate

Status: VERIFIED

Claim wording: "At the 224x224 MobileNetV2 stem boundary, Pipeline B has an 802,816-byte logical RGBA32Float intermediate payload while Pipeline C records zero RGBA32Float intermediate bytes. This is not a peak-memory or runtime-allocation claim."

Evidence files: `Sources/PlaneFuseCore/Shaders/NV12MobileNetV2RGB.metal`, `Sources/PlaneFuseCore/Shaders/NV12MobileNetV2Stem.metal`, `benchmarks/results/m5-mobilenetv2-confirm1.json`, `benchmarks/results/m5-mobilenetv2-confirm2.json`, `benchmarks/artifact-index.json`

## C011 - R0 source-model lineage closure

Status: VERIFIED

Claim wording: "With the declared CPU-only backend and deterministic 224x224 sRGB image preparation, the original Apple MobileNetV2 image-input model and derived FullArray agree on all 32 top-1 and top-5 results in the R0 corpus; maximum probability-vector absolute error was 8.3e-7."

Evidence files: `proof/r0-source-lineage.json`, `Sources/PlaneFuseCore/MobileNetV2Integration.swift`, `Sources/PlaneFuseCore/MobileNetV2Corpus.swift`

## C012 - R0 expanded quality corpus

Status: VERIFIED

Claim wording: "The R0 quality harness contains four provenance-bearing CC0/public-domain real images and 28 deterministic repository-generated stress inputs covering luma extremes, chroma extremes, gradients, checkerboards, edges, padding boundaries, and chroma phases."

Evidence files: `proof/m5-validation-corpus.json`, `proof/m5-corpus/`, `scripts/generate_stress_corpus.py`

## C013 - R0 physical-camera smoke

Status: QUALIFIED

Claim wording: "On one permitted physical camera frame, PlaneFuse captured 1920x1080 NV12 video-range input, performed native-plane crop/resize, ran real local B/C inference, and measured top-1 agreement 1.0. This is not continuous throughput or video evidence."

Evidence files: `proof/r0-camera-smoke.md`, `Sources/PlaneFuseLive/main.swift`

## C014 - R0 clean-clone reproduction

Status: VERIFIED

Claim wording: "A fresh local clone of the Phase 2 branch reproduced project-local MobileNetV2 setup, artifact/docs checks, build, 31 tests, quick benchmark, source lineage, and the sample demo in 83 seconds on arm64 macOS 26.6/Xcode 26.6 with pinned coremltools 9.0."

Evidence files: `proof/r0-clean-clone.json`, `scripts/release_validate.sh`, `requirements-lock.txt`

## C015 - Actual Metal allocation is distinguished from logical payload

Status: VERIFIED

Claim wording: "The R0 MobileNetV2 artifact records B's 802,816-byte logical RGBA32Float payload separately from its measured 819,200-byte Metal allocation, and records matched 2,408,448-byte B/C activation allocations."

Evidence files: `proof/r0-mobilenetv2-allocation.md`, `benchmarks/results/r0-mobilenetv2-quick.json`

## C016 - R1 component bottleneck profile

Status: VERIFIED

Claim wording: "On the declared Apple M5 Pro environment, the reproducible R1 component profile measures the current bridge's element-by-element MLMultiArray population/boxing at 48.5663 ms p50 for B1 and 48.4957 ms p50 for C0, dominating the 51.6957/50.6009 ms input-ready-to-result paths."

Evidence files: `proof/r1-bottleneck-profile.md`, `proof/r1-gpu-evidence.json`, `benchmarks/results/r1-mobilenetv2-components.json`, `Sources/PlaneFuseCore/MobileNetV2ComponentProfile.swift`

## C017 - R1 strongest conventional B2 baseline

Status: VERIFIED

Claim wording: "The R1 B2 baseline materializes planar Float32 RGB without an alpha channel, preserves the same Float32 stem and Core ML tail, passes 32-sample top-1 parity with maximum activation error 9.2983e-6, and records a 51.3243 ms p50 versus C0 at 51.3800 ms in the quick paired run; the near-tie is not claimed as an optimization win."

Evidence files: `proof/r1-bottleneck-profile.md`, `benchmarks/results/r1-mobilenetv2-b2.json`, `Sources/PlaneFuseCore/Shaders/NV12MobileNetV2RGB.metal`

## C018 - R2 persistent buffer-backed Core ML view

Status: VERIFIED

Claim wording: "Across three independent 200-iteration R2 confirmation batches, the persistent buffer-backed MLMultiArray view reduced the matched handoff-to-result p50 by approximately 97.3% for both B2 and C0, reduced end-to-end p50 by approximately 95.6%-95.8%, and preserved 100% boxed/shared top-1 agreement with maximum B/C activation error below 1e-5."

Evidence files: `proof/r2-shared-bridge.md`, `benchmarks/results/r2-mobilenetv2-shared-bridge-confirm.json`, `Sources/PlaneFuseCore/MobileNetV2Integration.swift`, `Tests/PlaneFuseCoreTests/MobileNetV2IntegrationTests.swift`

## C019 - R2 bridge terminology and lifetime boundary

Status: VERIFIED

Claim wording: "PlaneFuse retains each shared MTLBuffer through the buffer-backed MLMultiArray deallocator closure, validates canonical `[48,112,112]` / `[12544,112,1]` layout, awaits GPU completion before Core ML prediction, and reports view construction separately; it does not claim hidden Core ML copies are absent."

Evidence files: `proof/r2-shared-bridge.md`, `proof/r1-gpu-evidence.json`, `Sources/PlaneFuseCore/MobileNetV2SharedBridgeBenchmark.swift`
