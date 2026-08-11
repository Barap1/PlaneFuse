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

## C020 - R5 exact polyphase compiler result

Status: VERIFIED

Claim wording: "Under the declared nearest-sited NV12 contract, PlaneFuse's R5 compiler preserves exact Double-reference behavior across procedural chroma-phase and edge cases and reduces generated per-output UV read instructions from 9 to 4 and weighted multiplications from 27 to 17. Three 200-pair confirmation batches did not establish a consistent end-to-end latency improvement, so this is not a runtime speedup claim."

Evidence files: `proof/r5-polyphase.md`, `proof/r5-polyphase.json`, `benchmarks/results/r5-polyphase-corrected-confirm-1.json`, `benchmarks/results/r5-polyphase-corrected-confirm-2.json`, `benchmarks/results/r5-polyphase-corrected-confirm-3.json`, `Sources/PlaneFuseCore/NativePlaneConv3x3.swift`, `Tests/PlaneFuseCoreTests/NativePlaneCompilerTests.swift`

## C021 - R6 continuous native-plane camera delivery

Status: QUALIFIED

Claim wording: "A permitted physical-camera run processed 300 1920x1080 NV12 video-range frames through the CVMetalTextureCache native-plane GPU resize path and persistent local B/C inference resources. The run recorded first-frame activation max error 6.44e-6, 300 processed-frame top-1 agreement 1.0, zero C full-RGB intermediate bytes, and zero element-by-element CPU activation population; its last callback sequence was 317 and drop/late counts were not recorded. This is Debug technical-gate evidence, not a final B-versus-C performance claim or capture-to-result measurement."

Evidence files: `proof/r6-camera-300-frame.json`, `proof/r6-camera-300-frame.log`, `proof/r6-camera-texture.md`

## C022 - R6.1 Release camera benchmark evidence

Status: QUALIFIED

Claim wording: "At committed head `93a7016`, the Release camera benchmark captured and persisted 300 real 1920x1080 NV12 video-range frames (payload SHA-256 `1bf39d0b944aa6f780361134667eed6b01cf3af4a81bfe064ba8a6e6e88c4a3f`), reused the identical replay for B2 and C1, ran exactly five 200-pair alternating batches with explicit `MLComputeUnits.all`, and separately measured 300-frame B2-only and C1-only physical-camera sessions. The direct paired post-resize-input-to-result p50 difference was 0.0460 ms (3.8033% aggregate), with median paired bootstrap 95% CI [-0.0244, 0.1094] ms; the interval crosses zero, so this is not an accepted camera speedup claim. Top-1 agreement was 1.0, activation max absolute error was 8.583068e-6, C full-RGB intermediate bytes were 0, and element-by-element CPU activation population bytes were 0."

Required evidence:

- committed Release command and JSON artifact;
- persisted replay payload and manifest with matching SHA-256;
- exact paired raw records, batch structure, bootstrap, and isolated live-session records;
- parity and task agreement.

Evidence files: `proof/r6.1-camera-benchmark-release.json`, `proof/r6.1-camera-replay.manifest.json`, `proof/r6.1-camera-replay.bin`, `scripts/check_r6_camera_artifact.py`, `Sources/PlaneFuseLive/main.swift`

## C023 - Direct Release B2-shared versus C1-shared result

Status: QUALIFIED

Claim wording: "At committed head `57bcf42`, the direct Release B2-shared versus C1-shared benchmark over the existing 32-sample corpus used exactly five 200-pair alternating batches and the same explicit `.all` Core ML tail. B2 p50 was 1.7264 ms and C1 p50 was 1.6209 ms, a 6.1111% aggregate p50 difference; the paired median 95% CI was [0.0542, 0.0729] ms. Top-1 agreement was 1.0 and maximum B2/C1 activation error was 9.298325e-6. This is below the project's ≥10% competition target and is not a final competition-worthiness claim."

Evidence files: `proof/r6.2-mobilenetv2-direct-shared.json`, `proof/m5-validation-corpus-r6.2.json`, `Sources/PlaneFuseCore/MobileNetV2DirectSharedBenchmark.swift`, `Tests/PlaneFuseCoreTests/MobileNetV2DirectSharedBenchmarkTests.swift`

## C024 - Pipeline A contextual original image-input result

Status: QUALIFIED

Claim wording: "At committed head `9f196b5`, the representative original Apple MobileNetV2 image-input Core ML path, explicitly loaded with `MLComputeUnits.all`, measured p50 1.0891 ms, p95 1.1507 ms, and mean 1.0957 ms over 1,000 calls. Its boundary starts with a pre-rendered 224x224 CGImage and includes BGRA pixel-buffer materialization, original image-input Core ML prediction, and result extraction. This is contextual evidence, not a substitute for the matched B2/C1 comparison; it is faster under its distinct framework-optimized boundary and remains visible in the evaluation matrix."

Evidence files: `proof/r6.3-pipeline-a.json`, `proof/m5-validation-corpus-r6.2.json`, `Sources/PlaneFuseCore/MobileNetV2Integration.swift`, `Sources/PlaneFuseCLI/main.swift`

## C027 - R7 output-blind corpus gate

Status: VERIFIED

Claim wording: "The R7 validation manifest contains 32 provenance-bearing real images and 32 deterministic procedural stress inputs, with exactly four real images in each of the eight preregistered subject buckets. The fail-closed verifier checks file existence, image integrity, hashes, strict real-image provenance/license fields, duplicate local hashes, and real/procedural classification. Selection does not inspect PlaneFuse outputs or benchmark results."

Evidence files: `proof/m5-validation-corpus.json`, `proof/r7-real-corpus-policy.md`, `scripts/acquire_real_corpus.py`, `scripts/check_r7_corpus.py`, `scripts/compose_r7_corpus_manifest.py`, `artifacts/logs/r7-corpus-acquisition.jsonl`, `artifacts/r7-corpus/r7-promoted-real-final2.json`

## C025 - Camera-space fusion go/no-go evidence

Status: QUALIFIED

Claim wording: "At committed head `5ff39fa`, Release camera profiling measured native-plane resize GPU p50 0.0217 ms but synchronized resize wall p50 0.5096 ms (p95 0.6843 ms), materially larger than the direct B2/C1 paired p50 difference of 0.0743 ms. The run passed the declared parity thresholds with top-1 agreement 0.9960 and activation max error 9.059906e-6. This justifies one bounded camera-space fusion experiment; it does not claim that fusion has been implemented or will improve performance."

Evidence files: `proof/r6.1-camera-profiler-go-no-go.md`, `proof/r6.1-camera-profiler-go-no-go.json`, `proof/r6.1-camera-profiler-replay.manifest.json`, `Sources/PlaneFuseLive/main.swift`

## C026 - R6.5 camera-space fusion negative result

Status: QUALIFIED NEGATIVE

Claim wording: "The bounded Release R6.5 experiment, generated by committed harness a665fb4, used a 32-frame, source-resolution 1920x1080 NV12 replay, five alternating 200-pair batches, and the same explicit .all Core ML tail. The fair direct camera-space B materialized planar Float32 RGB and ran the unchanged B2 stem in one ordered submission; direct camera-space C eliminated the resized NV12 intermediate and ran the unchanged native stem in one ordered submission. Correctness passed: accepted-path activation errors were 0, direct B/C activation max error was 8.58306884765625e-06, top-1 agreement was 1.0, and no task disagreements were recorded. Direct B p50 post-input-to-result was 1.5613 ms and direct C p50 was 2.3859 ms; paired B-minus-C p50 was -1.4195 ms with median bootstrap 95% CI [-1.4586, -1.3918] ms. C was slower, so no camera-space fusion speedup claim is made and accepted C1 is retained for R7."

Evidence files: `proof/r6.5-camera-space.json`, `proof/r6.5-camera-source-replay.manifest.json`, `proof/r6.5-camera-source-replay.bin`, `proof/r6.5-camera-space-release.log`, `scripts/check_r6_5_camera_space_artifact.py`, `proof/reviews/R6.5-CANDIDATE-B01B3E1-20260810-SOL-03.md`, `proof/reviews/R6.5-ACCEPTANCE-ED61ADF-20260811-SOL-07.md`

Outcome: QUALIFIED NEGATIVE; no competition-worthiness target met
Lesson: Eliminating the resized NV12 intermediate is not sufficient when the direct transformed native stem costs more than a fair direct source-to-RGB B path. Do not retain the camera-space candidate as the strongest C path.
Accepted status: SHIP review accepted as a qualified negative result; measurement generated by a665fb4 and promoted into the evidence commit. C1 is retained for R7; no camera-space fusion speedup is claimed.

## C028 - R7 pre-repair matched B2/C1 quality and performance

Status: HISTORICAL / SUPERSEDED FOR FINAL PROTOCOL

Claim wording: "At integrated Release commit `8f9e98d`, the strongest matched B2/C1 shared-activation comparison used 32 provenance-bearing real images plus 32 deterministic procedural inputs, exactly five independent 200-pair alternating batches, explicit `MLComputeUnits.all`, and persistent Float32 activation bridges. B2 p50 was 1.6641 ms and C1 p50 was 1.6225 ms; the difference between marginal p50s was 0.0416 ms, the median paired B2-minus-C1 difference was 0.0481 ms, and its paired median bootstrap 95% CI was [0.0415, 0.0543] ms. C1 was 2.5013% lower, below the ≥10% target. Quality evidence recorded top-1 agreement 1.0, top-5 set agreement 0.984375, top-5 ranking agreement 0.96875, activation maximum absolute error 8.583068e-6, minimum activation cosine similarity 0.999999999997659, probability maximum absolute error 0.001953125, mean probability L1 distance 0.001053418, zero C full-RGB bytes, and zero PlaneFuse element-by-element CPU activation-copy bytes. Two real-image top-5 disagreements were retained in the artifact; this is not a competition-worthiness claim."

Evidence files: `proof/r7-final-b2-c1-shared-current.json`, `proof/r7-b2-c1-shared-quality-clean.json`, `proof/r7-competition-targets.json`, `Sources/PlaneFuseCore/MobileNetV2DirectSharedBenchmark.swift`, `Sources/PlaneFuseCore/MobileNetV2SharedQualityEvidence.swift`, `proof/r7-real-corpus-policy.md`

Pipeline A context: `proof/r7-final-pipeline-a-current.json` records the original Apple image-input path at p50 1.1483 ms under its distinct pre-rendered-image boundary and explicit `.all` policy; it remains contextual and is not a substitute for the matched B2/C1 result.

Camera qualification: `proof/r7-camera-evidence.json` preserves the successful prior Release 300-frame replay/live evidence and separately records the fresh R7 zero-callback acquisition attempt. No new camera result is inferred from the failed attempt.

Supersession: F-002 found that the cited implementation used one warmup phase and one continuous run labeled as five batches, and did not provide both execution orders for repeated samples. Preserve this artifact as historical evidence; do not use it for final R7 CI or headline performance selection.

## C031 - R7.5 source-reuse confirmation

Status: QUALIFIED / PENDING FRESH HOSTILE REVIEW

Claim wording: "At confirmation commit `52db138feef3d6fc52bcb5839a419423fd992019`, the one authorized same-workload R7.5 source-reuse experiment used five independent Release processes, 20 warmup triples, 240 measured triples, six balanced B2/C1/C1-SR order permutations per batch, the fixed 64-input corpus, explicit `.all`, and persistent shared activations. B2 p50 was 1.737875 ms, accepted C1 p50 was 1.633458 ms, and C1-SR p50 was 1.532583 ms. C1-SR was 6.1755% lower than C1 and 11.8128% lower than B2; the C1-minus-C1-SR paired median bootstrap 95% CI was [0.091125, 0.101750] ms. Full 64-sample quality recorded activation max error 5.960464e-6, top-1/top-5-set/top-5-ranking agreement 1.0, probability max error 0.001953125, and mean probability L1 0.001176831. This is technically promising evidence pending independent hostile review, not yet an accepted competition claim."

Evidence files: `proof/r7.5-source-reuse-final-52db138-20260811T1605Z-confirm.json`, `proof/r7.5-source-reuse-batches/52db138-20260811T1605Z-confirm/`, `scripts/check_r75_source_reuse.py`, `Sources/PlaneFuseCore/R75SourceReuseBenchmark.swift`, `Sources/PlaneFuseCore/Shaders/NV12MobileNetV2Stem.metal`, `proof/R7.5-PREREGISTRATION.md`

Limitations: The source-reuse result is a same-workload fallback candidate, not a replacement for the repaired R7 evidence until a fresh independent reviewer verifies fairness, quality, source schedule, and target evaluation. The original R7 hard stop and negative R6.5 result remain visible.

## C029 - R7 repaired strongest matched B2/C1 evidence

Status: HISTORICAL / SUPERSEDED BY CONDITION-COMPLETE RERUN

Claim wording: "At repaired Release generating commit `3b62467f6bb4e8b0a95209f23471ecf2de722d3f`, the strongest matched B2/C1 comparison used five separate Release benchmark processes. Each process independently initialized the benchmark, performed 20 warmups, measured exactly 200 pairs, balanced 100 B2-first and 100 C1-first pairs, and rotated source offset/order phase across the fixed 64-input output-blind corpus. B2 p50 was 2.483208 ms and C1 p50 was 2.413458 ms. The difference between marginal p50s was 0.069750 ms, or 2.808866% in C1's favor; the median paired B2-minus-C1 difference was 0.077167 ms with paired-median bootstrap 95% CI [0.068625, 0.091542] ms. The repaired result remains below the ≥10% target. Quality was regenerated at the profiler/source repair commit with top-1 agreement 1.0, top-5 set agreement 0.984375, top-5 ranking agreement 0.96875, activation maximum absolute error 8.583068e-6, probability maximum absolute error 0.001953125, zero C RGB bytes, and zero PlaneFuse element-by-element CPU activation-copy bytes. The two real-image top-5 disagreements remain retained."

Evidence files: `proof/r7-final-b2-c1-shared-repaired.json`, `proof/r7-repaired-batches/3b62467607ba29b58c0d7205dfec06f8f7b909c4/`, `proof/r7-b2-c1-shared-quality-repaired.json`, `proof/r7-competition-targets-repaired.json`, `scripts/check_r7_repaired_shared_benchmark.py`, `scripts/check_r7_repaired_targets.py`

Limitations: This is not a competition-worthiness claim until fresh hostile review; the prior successful camera evidence remains historical and the fresh R7 physical-camera attempt had zero callbacks. The repaired paired CI and difference of marginal p50s are distinct estimands.

## C030 - R7 condition-complete final B2/C1 evidence

Status: QUALIFIED PENDING FRESH HOSTILE RE-REVIEW

Claim wording: "At clean Release generating commit `b6285f2eb6b9329f925cde81db5936f5f2a8de98`, the unchanged five-process R7 B2/C1 protocol was rerun with batch-local 20 warmups, 200 measured pairs, 100/100 execution order balance, rotated source offsets, and complete per-batch AC power, Low Power Mode, and thermal-state metadata. B2 p50 was 1.595167 ms and C1 p50 was 1.561417 ms; the difference between marginal p50s was 0.033750 ms, or 2.115766% in C1's favor. The median paired difference and deterministic paired bootstrap interval are in the authoritative artifact. The result remains below the ≥10% target. Quality at the same source commit retained top-1 agreement 1.0, activation maximum absolute error 8.583068e-6, top-5 set agreement 0.984375, two real-image disagreements, zero C RGB bytes, and zero PlaneFuse element-by-element CPU activation-copy bytes."

Evidence files: `proof/r7-final-b2-c1-shared-repaired-conditions.json`, `proof/r7-repaired-batches/b6285f/`, `proof/r7-b2-c1-shared-quality-conditions.json`, `proof/r7-competition-targets-repaired-conditions.json`, `scripts/check_r7_repaired_shared_benchmark.py`

Profiler qualification: `proof/r7-final-shared-path-profile-repaired-conditions.json` and `proof/profiler/r7-b2-c1-shared-repaired-events-full.json` contain nonzero actual event rows, observed command-buffer/encoder labels joined by command-buffer IDs, GPU/submission joins, source-export hashes, and clean completion metadata. The fail-closed checker requires exact 50/100/50/100 cardinalities, complete observed joins, generating-commit equality, and rehashed semantic negative tests. The raw trace remains uncommitted due size. This is not a competition-worthiness claim; fresh hostile re-review is required.
