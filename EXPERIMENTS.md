# PlaneFuse experiment log

Keep this concise and append only experiments that teach something useful.

## E001 - first fair native stem versus optimized RGB stem

Date: 2026-08-09
Base commit: 06f1c8350a8c93fbbb1f5449a2ac9ed02160e020
Evidence/observation: B materializes a 4,915,200-byte RGBA32Float intermediate; C reports zero RGB intermediate bytes and uses the same four-feature output contract.
Hypothesis: Folding decode, normalization, and the first linear stem into direct Y/UV projection will reduce end-to-end frontend-plus-stem work even if the isolated fused kernel is not faster than RGB conversion alone.
Change: Added interleaved preallocated B/C timing with one B sequence and one C sequence per iteration, then exposed quick and 100-iteration confirmation workflows.
Correctness: PASS; max feature absolute difference 1.4305115e-6 in both confirmation batches, threshold 1e-5.
Quick benchmark: Three 30-iteration batches measured C p50 0.2057/0.2220/0.2185 ms versus B 0.4361/0.5163/0.4621 ms; e2e delta 52.7-57.0%.
Confirmation benchmark: Two 100-iteration batches measured e2e delta 51.55% and 50.93%; C isolated frontend was 0.74-1.03% slower.
Outcome: SUPERSEDED
Lesson: The result was not a valid final comparison because Pipeline B's end-to-end measurement used two command-buffer submissions while Pipeline C used one. Preserve the result as historical evidence, but do not use its 50% claim.
Accepted commit: superseded by 3d17ced

## E002 - equalize B and C command-buffer submissions

Date: 2026-08-09
Base commit: b19de08
Evidence/observation: The M4 reviewer identified an apples-to-oranges boundary: B paid two command-buffer waits for conversion plus stem while C paid one wait for the fused stem.
Hypothesis: Making both end-to-end paths use one command buffer and one submission will preserve the native-plane advantage if the benefit comes from eliminating the full RGB intermediate rather than from submission-count asymmetry.
Change: Added caller-owned encoder APIs and measured B conversion plus normal RGB stem in one command buffer, against C native stem in one command buffer. Added explicit methodology to the result artifact.
Correctness: PASS; max feature absolute difference 1.4305115e-6 in both 100-iteration confirmation batches, threshold 1e-5.
Quick benchmark: Not used for acceptance; confirmation tier was rerun directly after the boundary correction.
Confirmation benchmark: Batch 1 measured B/C end-to-end p50 0.232833/0.194792 ms, a 16.34% C reduction; batch 2 measured 0.181917/0.163292 ms, a 10.24% C reduction. Frontend deltas were +1.40% and -0.82% respectively.
Outcome: ACCEPT
Lesson: The defensible M4 result is a smaller but persistent end-to-end win after equalizing submission methodology; the isolated frontend result remains effectively tied.
Accepted commit: 3d17ced

## E003 - real pretrained MobileNetV2 native stem and unchanged tail

Date: 2026-08-09
Base commit: a773382
Evidence/observation: Apple’s official MobileNetV2 model has a 3x3 stride-2, 3-to-48 Conv followed by BatchNorm and ReLU6. The remaining 252-layer classifier graph can accept a derived [48,112,112] Float32 activation input.
Hypothesis: Folding the exact pretrained input stem into direct NV12 projection will preserve the model tail’s output while removing the full normalized RGBA intermediate.
Change: Added model-graph preparation, exact coefficient export, native NV12 3x3 Conv/BN/ReLU6, equal RGB B pipeline, and the same-tail Core ML adapter.
Correctness: PASS; max B/C activation absolute difference 9.059906e-6 <= 1e-5; top-1 agreement 1.0 over 8 validation samples in both post-commit confirmation batches.
Quick benchmark: B/C end-to-end p50 55.9170/54.3686 ms, a 2.77% C reduction; isolated stem-region p50 was 2.0187/0.6765 ms, a 66.48% C reduction.
Confirmation benchmark: Post-commit batches measured B/C end-to-end p50 56.6585/54.6994 ms (3.46% C reduction) and 56.5140/55.3209 ms (2.11% C reduction). Frontend C reductions were 61.90% and 66.47%.
Outcome: REJECTED
Lesson: B/C agreement was insufficient because both paths shared a wrong top/left-heavy SAME-padding convention; the synthetic corpus and missing original-stem parity also prevented acceptance. The CPU-visible MLMultiArray handoff remains explicitly included in timing.
Accepted commit: none; implementation requires correction before M5 acceptance.

## E004 - repair and independently validate pretrained MobileNetV2

Date: 2026-08-09
Base commit: 492a171
Evidence/observation: The audit found top/left-heavy SAME padding, no independent original-stem check, a synthetic/unused corpus, unclear tail lineage, and only 20 measured iterations.
Hypothesis: Correcting the Apple bottom/right-heavy SAME contract and validating the derived graph against a real hashed corpus will preserve the pretrained task while retaining a fair B/C advantage.
Change: Corrected reference and both Metal shaders; added derived StemArray/FullArray artifacts, exact tail input/shape/hash validation, four public CC0 images with deterministic ImageIO→NV12 conversion, and a 100-iteration confirmation tier.
Correctness: PASS; raw B/C max activation error 9.298325e-6 <= 1e-5, B/C and FullArray/split-tail top-1 agreement 1.0, and independent CPU-only Core ML StemArray versus B/C max error 3.904105e-5 <= the documented 1e-4 reference-math tier.
Quick benchmark: At the repaired implementation, real-corpus B/C end-to-end p50 was 53.0177/51.7739 ms, a 2.35% C reduction.
Confirmation benchmark: At commit df5f573, two 100-iteration batches measured end-to-end C reductions of 2.02% and 1.89%; frontend reductions were 61.29% and 51.65%. B allocated 802,816 bytes of RGBA32Float intermediate; C allocated 0.
Outcome: ACCEPT
Lesson: The core result survives a credible pretrained workload, but the absolute end-to-end advantage is workload/runtime dependent; the strongest technical evidence is the native stem reduction and eliminated full-RGB intermediate, not a universal speedup claim.
Accepted commit: 6e685a6, b8b7850, and df5f573

## E005 - explicit phase-aware 2x2 chroma reuse in the MobileNetV2 native stem

Date: 2026-08-09
Base commit: 7cf5151
Evidence/observation: The native 3x3 stride-2 kernel logically reuses four UV texels, although the source code issued up to nine UV reads per output.
Hypothesis: Prefetching the four phase-aware chroma pairs will reduce source-plane bandwidth and improve C frontend/e2e latency.
Change: Prefetched the four UV pairs for each output patch while preserving Y reads, accumulation order, bottom/right guards, and coefficients.
Correctness: PASS; quick real-corpus validation retained 100% task agreement and max raw B/C activation error 9.298325e-6.
Quick benchmark: Baseline C frontend p50 0.3009 ms and e2e p50 52.2850 ms; experiment C frontend p50 0.2518 ms but e2e p50 52.4548 ms, with higher mean e2e time.
Outcome: REJECTED
Lesson: The isolated kernel p50 improvement did not survive the user-level e2e boundary; explicit reuse likely traded UV reads for register/selection overhead. Reverted without a commit.

## E006 - native-stem threadgroup geometry

Date: 2026-08-09
Base commit: 7cf5151
Evidence/observation: The accepted native kernel uses 8x8 (64-thread) groups; source-plane accesses are spatially local and the output grid is 112x112.
Hypothesis: A 16x4 (also 64-thread) group may improve X locality and UV/Y coalescing without changing shader math.
Change: Changed only the native-stem dispatch geometry from 8x8 to 16x4.
Correctness: PASS; raw B/C max activation error remained 9.298325e-6 and task agreement remained 1.0.
Quick benchmark: C frontend p50 improved to 0.2605 ms from the 0.3009 ms baseline, but C e2e p50 moved to 52.5810 ms from 52.2850 ms.
Confirmation benchmark: The 100-iteration confirmation measured C e2e p50 52.7563 ms versus B 53.7635 ms, a 1.87% reduction, below both accepted M5 batches and not an improvement over the 8x8 accepted path.
Outcome: REJECTED
Lesson: Threadgroup geometry changes can improve the isolated kernel while losing at the model boundary; retain 8x8 and stop this hypothesis family.

## E007 - M6 bounded optimization plateau

Date: 2026-08-09
Base commit: 7cf5151
Evidence/observation: Two distinct source-grid hypotheses preserved the accepted 9.298325e-6 raw B/C parity and 100% task agreement, but neither improved the measured model boundary. Phase-aware UV prefetch improved isolated C frontend p50 by 16.3% and worsened e2e p50 by 0.32 ms; 16x4 threadgroups improved isolated frontend p50 but worsened quick e2e and lost to both accepted 8x8 confirmation batches.
Hypothesis: The accepted simple 8x8 native stem is already near the practical optimum for this workload/runtime boundary; further local shader tuning is unlikely to improve user-visible inference without changing the handoff or workload.
Change: No retained code change. Both experiment patches were reverted after parity-preserving quick/confirmation measurements.
Correctness: PASS for both experiments; the existing M5 numerical and task contracts were unchanged.
Quick benchmark: Neither candidate improved C end-to-end p50 over the 8x8 baseline.
Confirmation benchmark: E006 confirmed C e2e p50 52.7563 ms versus accepted M5 C p50 values 52.3829/52.6675 ms; E005 was rejected at the quick boundary before confirmation.
Outcome: ACCEPT
Lesson: Close this M6 hypothesis family with a precise plateau conclusion. The strongest remaining contribution is the native-plane model-stem boundary and eliminated intermediate; future gains require a separately evidenced tensor handoff or a different workload, not random shader tuning.
Accepted commit: recorded with the M6 state transition.

## E008 - R3 Float16 tail feasibility

Date: 2026-08-09
Base commit: 665a46d
Evidence/observation: Core ML rejects a Float16 multi-array feature declaration under the source model's specification version 1, but accepts the same unchanged derived tail graph after the minimum specification-version-7 declaration. The temporary model compiled with `coremlc` on the stable Xcode 26.6 toolchain.
Hypothesis: A Float16 declaration for the unchanged `[48,112,112]` tail input can support an IOSurface-backed bridge without unacceptable task-output drift.
Change: Added a reproducible project-local Float16 tail preparation script and compared the temporary compiled Float16-input tail with the accepted Float32 CPU-only tail over the 32-sample corpus.
Correctness: Top-1 agreement was 1.0. Maximum probability-vector absolute error was 0.01288722 and failed its predeclared 0.005 threshold; mean probability L1 distance was 0.01548487 and passed its 0.05 threshold.
Quick benchmark: Not run; the precision contract failed before IOSurface/Metal timing.
Confirmation benchmark: Not applicable; the candidate failed the declared R3 quality gate.
Outcome: REJECT
Lesson: The stable toolchain can compile a Float16-input copy, but the current tail's output sensitivity exceeds the predeclared Float16 quality contract. Do not accept an IOSurface Float16 path or silently relax the threshold; proceed to R4 feasibility with the accepted Float32 shared bridge as control.
Accepted commit (if any): none; the verifier and preparation script are retained as a reproducible negative result.

## E009 - R4 Metal 4 GPU-timeline tail feasibility

Date: 2026-08-09
Base commit: 41831b1
Evidence/observation: Stable Xcode 26.6 provides `metal-package-builder`, `MTLTensor`, and `MTL4MachineLearningCommandEncoder`, but the unchanged derived tail compiles as an Espresso/neural-network model rather than an ML Program package.
Hypothesis: The unchanged tail can be promoted or converted into a provenance-preserving ML Program and packaged for the Metal 4 ML encoder.
Change: Attempted `coremlc upgrade`, forced ML Program compilation, normal compilation inspection, and coremltools 9.0 ML Program conversion in temporary paths.
Correctness: No candidate execution was produced; no quality claim was made.
Quick benchmark: Not applicable; the package prerequisite failed.
Confirmation benchmark: Not applicable.
Outcome: REJECT
Lesson: The stable toolchain cannot convert this already-authored specification-version-1 neural-network tail without an unavailable source representation or a provenance-changing re-authoring. Retain R2 and continue to R5; do not install beta tooling or claim a GPU-timeline tail.
Accepted commit (if any): none; infeasibility report committed in the Phase 2 state transition.

## E010 - R5 exact nearest-sited polyphase compiler

Date: 2026-08-09
Base commit: b1a399c
Evidence/observation: The native 3x3/stride-2 stem issues nine luma and nine UV texture reads per output feature even though nearest-sited 4:2:0 maps the nine taps to four physical chroma coordinates.
Hypothesis: Compile repeated UV contributions into four phase-specific chroma coefficients while preserving per-tap offsets and bottom/right padding, reducing source-domain work without retraining.
Change: Added a Double-reference polyphase compiler, generated Metal coefficients/kernel, procedural phase/edge parity cases, generated operator metadata, and the strongest shared Float32 bridge/tail benchmark.
Correctness: PASS; independent Double reference and compiled polyphase output agree across three procedural cases at 1e-9, and all 32 real/procedural benchmark inputs retain task agreement 1.0 with maximum confirmation activation error 6.198883e-6.
Quick benchmark: Corrected frontend-inclusive e2e p50 was 2.0317 ms native versus 2.0418 ms polyphase (-0.49%).
Confirmation benchmark: Three corrected 200-pair batches measured polyphase e2e deltas of +0.23%, -0.64%, and +0.39%; GPU p50 was consistently about 0.233 ms polyphase versus 0.240 ms native, but the application boundary was mixed.
Outcome: ACCEPT as a rigorous documented negative result; do not claim a runtime speedup.
Lesson: Reducing generated UV instructions and weighted multiplications can improve GPU duration without producing a stable user-level latency gain when the fixed Core ML tail and scheduling noise dominate this small stem.
Accepted commit: 9c201de (implementation/evidence correction); milestone proof committed separately.

Template:

## Exxx - short title

Date:
Base commit:
Evidence/observation:
Hypothesis:
Change:
Correctness:
Quick benchmark:
Confirmation benchmark:
Outcome: ACCEPT / REJECT / INCONCLUSIVE
Lesson:
Accepted commit (if any):

## E011 - R6.1 Release replay and live camera benchmark

Date: 2026-08-10
Base commit: 93a7016
Evidence/observation: The Release benchmark path captured a 300-frame real NV12 replay, persisted binary payload plus manifest, reused preallocated replay textures, alternated B2/C1 order over five 200-pair batches, and ran separate 300-frame physical-camera sessions for true frame-delivery-to-result timing.
Hypothesis: A strongest-credible B2 planar Float32 baseline and C1 native-plane stem will show a stable camera-level advantage under matched shared-tail conditions.
Change: Added `./pf bench camera`, explicit `.all` tail configuration, deterministic replay, candidate-local paired post-resize timing, isolated live sessions, raw pair records, fixed-seed hierarchical bootstrap, thermal/drop/callback metadata, and a structural artifact verifier.
Correctness: PASS; Release artifact recorded top-1 agreement 1.0, activation max absolute error 8.583068e-6, identical replay hash for B2/C1, zero C full-RGB intermediate bytes, and zero element-by-element CPU activation population bytes. Artifact verifier passed.
Quick benchmark: Direct paired B2-C1 post-resize-input-to-result p50 difference 0.0460 ms, aggregate 3.8033%; p95 difference 0.6093 ms; mean/MAD and raw samples are persisted.
Confirmation benchmark: Five independent 200-pair batches produced median bootstrap 95% CI [-0.0244, 0.1094] ms, which crosses zero. Separate physical-camera B2/C1 sessions each processed 300 frames with zero dropped/late/overwritten/skipped counts in this run; their delivery timings are descriptive, not a paired comparative claim.
Outcome: INCONCLUSIVE
Lesson: The strongest B2 planar baseline narrows the prior camera advantage below the competition target; the direct paired confidence interval does not establish a stable camera speedup. Continue to Pipeline A and the bounded profiler-driven fusion go/no-go, without claiming this as a win.
Accepted commit (if any): 93a7016

## E012 - Direct B2-shared versus C1-shared Release confirmation

Date: 2026-08-10
Base commit: 57bcf42
Evidence/observation: The direct benchmark used the existing 32-sample corpus, persistent CHW Float32 B2 and native C1 activation buffers, one shared `.all` tail, exactly five 200-pair batches, alternating order, and a fixed hierarchical bootstrap.
Hypothesis: Removing boxed MLMultiArray population from both optimized paths would expose a stable strongest-B versus strongest-C comparison.
Change: Added `MobileNetV2DirectSharedBenchmark` and `./pf bench mobilenetv2 shared`, with raw pair records and exact R6.1 statistics.
Correctness: PASS; top-1 agreement 1.0, activation max error 9.298325e-6, zero C RGB bytes, zero element-by-element CPU activation-copy bytes.
Quick benchmark: B2 p50 1.7264 ms; C1 p50 1.6209 ms; aggregate 6.1111% lower for C1.
Confirmation benchmark: Five batches, 1,000 pairs; median bootstrap 95% CI [0.0542, 0.0729] ms, positive. The result is stable but below the ≥10% competition target.
Outcome: QUALIFIED
Lesson: The strongest conventional B2 narrows the native-plane advantage to a reproducible but sub-target 6.11%; the direct matched result should remain visible and not be replaced by the weaker B1 baseline.
Accepted commit (if any): 4c4b8fe, 57bcf42

## E013 - Pipeline A original image-input challenge

Date: 2026-08-10
Base commit: 9f196b5
Evidence/observation: The original Apple MobileNetV2 image-input model was loaded with explicit `.all` compute units. Pre-rendered 224x224 CGImages were prepared before timing; each measured call included BGRA pixel-buffer materialization, original Core ML prediction, and result extraction.
Hypothesis: The framework-optimized unsplit image-input model may be faster than the split B2/C1 paths and must be shown contextually.
Change: Added `./pf bench mobilenetv2 pipeline-a` and persisted 1,000 raw timing samples over five batches.
Correctness: The run completed with the original model and its declared image-input boundary; this contextual benchmark does not replace the matched B2/C1 quality contract.
Quick benchmark: p50 1.0891 ms, p95 1.1507 ms, mean 1.0957 ms.
Confirmation benchmark: Five 200-sample batches, 1,000 processed calls; no claim is made that this boundary is directly interchangeable with B2/C1.
Outcome: ACCEPT as contextual evidence
Lesson: The standard unsplit Apple path is faster under its own framework-optimized image-input boundary. The final evaluation must disclose this and explain the boundary difference rather than present PlaneFuse as universally faster.
Accepted commit (if any): 9f196b5

## E014 - R6.5 camera-space fusion profiler go/no-go

Date: 2026-08-10
Base commit: 5ff39fa
Evidence/observation: Release camera profiling separated native-plane resize GPU execution from synchronized wall time. GPU p50 was 0.0217 ms, while wall p50 was 0.5096 ms and p95 0.6843 ms; the direct B2/C1 p50 difference was 0.0743 ms.
Hypothesis: Eliminating the resized NV12 intermediate and its synchronization could materially improve true frame-delivery boundaries even if the native resize kernel itself is fast.
Change: Added resize GPU/wall timing to the Release camera artifact and performed the profiler-driven decision; no camera-space fusion kernel was implemented.
Correctness: PASS for the measured candidate path: top-1 agreement 0.9960, activation max error 9.059906e-6, both within declared thresholds. This is a go/no-go artifact, not fusion evidence.
Quick benchmark: Resize wall overhead was material relative to the direct B2/C1 difference; the direct paired result remained below the competition target.
Confirmation benchmark: Not applicable; no fusion variant was run.
Outcome: GO JUSTIFIED / HUMAN REVIEW REQUIRED
Lesson: The remaining camera opportunity is synchronization/mapping around resize, not raw GPU resize duration. A bounded camera-space experiment is technically motivated, but the current strongest B2/C1 and Pipeline A gates do not support autonomous claim reframing or beta/toolchain expansion.
Accepted commit (if any): 5ff39fa

## E015 - R6.5 direct camera-space fusion

Date: 2026-08-10
Base/implementation commit: a665fb4 (final full-source provenance Release rerun)
Evidence: `proof/r6.5-camera-space.json`, `proof/r6.5-camera-source-replay.manifest.json`, `proof/r6.5-camera-source-replay.bin`, `scripts/check_r6_5_camera_space_artifact.py`

Observed bottleneck: profiler evidence showed synchronized resize wall p50 0.5096 ms, materially larger than the direct B2/C1 gap.
Hypothesis: Compiling the accepted even-aligned crop and nearest source-grid mapping directly into the native C stem would remove the resized NV12 allocation and synchronization without changing the model.
Fair design: direct source-space B materialized planar Float32 RGB through the same source mapping and one ordered B conversion+stem submission; direct C used one ordered native-stem submission; both used the same 32-frame 1920x1080 NV12 source replay, explicit `.all` tail, Release build, persistent resources, five alternating 200-pair batches, and separate B-only/C-only live sessions.
Correctness: accepted C activation max error 0; accepted B activation max error 0; direct B/C activation max error 8.58306884765625e-06; top-1 agreement 1.0; zero task disagreements; zero C RGB and CPU element-copy bytes.
Result: direct B p50 post-input-to-result 1.5613 ms; direct C p50 2.3859 ms; paired B-minus-C p50 -1.4195 ms, mean -1.5128 ms, p95 -0.3025 ms, MAD 0.5635 ms; median bootstrap 95% CI [-1.4586, -1.3918] ms. The interval is decisively negative for C.
Outcome: REJECT as a performance candidate; accepted as a qualified negative experiment after SOL-07 SHIP. Retain C1 for R7 and do not random-tune or pursue a corrective shader variant.
Lesson: Removing a synchronization boundary did not compensate for the direct transformed native stem's higher work relative to a fair source-space materialized-RGB baseline. This bounded architecture family is closed.
Review: R6.5-CANDIDATE-B01B3E1-20260810-SOL-03, R6.5-ACCEPTANCE-9FCC2EB-20260810-SOL-04, R6.5-ACCEPTANCE-351E3D4-20260810-SOL-05, R6.5-ACCEPTANCE-ED61ADF-20260811-SOL-06, and R6.5-ACCEPTANCE-ED61ADF-20260811-SOL-07. Final status: accepted qualified negative; C1 retained for R7.

## E016 - R7 output-blind corpus, quality contract, and final matched matrix

Date: 2026-08-11
Base/integrated commit: 8f9e98d
Evidence/observation: The preregistered acquisition workflow promoted 32 provenance-bearing real images across eight buckets (four each) and retained 32 deterministic procedural stress inputs. The fail-closed verifier passed hashes, image integrity, strict provenance, uniqueness, classification, and bucket distribution. Selection did not inspect B/C outputs.
Quality: Release B2/C1 quality evidence over all 64 samples passed top-1 1.0 and the established activation gate with max error 8.583068e-6. Top-5 set agreement was 0.984375 and ranking agreement 0.96875. Probability max absolute error was 0.001953125 and mean vector L1 was 0.001053418. Two real-image top-5 disagreements were retained with complete per-sample labels/rankings; no sample was removed.
Performance: The final direct shared benchmark used explicit `.all`, five independent 200-pair batches, alternating order, 1,000 raw pairs, and the existing hierarchical block bootstrap. B2 p50 was 1.6641 ms; C1 p50 was 1.6225 ms; marginal-p50 difference was 0.0416 ms; median paired difference was 0.0481 ms with CI [0.0415, 0.0543] ms; C1 was 2.5013% lower. B2 RGB logical/allocated bytes were 602,112/606,208; C1 recorded zero RGB bytes; both recorded zero PlaneFuse element-by-element activation-copy bytes.
Pipeline A: The contextual original Apple image-input path measured p50 1.1483 ms over 1,000 calls with explicit `.all`, under its distinct pre-rendered-image boundary. It remains visible and is not used as a strawman replacement for B2/C1.
Camera: The prior successful Release 300-frame replay/live artifact remains the camera evidence source. A fresh Release invocation received zero camera callbacks before timeout; the failure is persisted without inventing drop or latency values.
Competition targets: The durable target evaluation marks all four preregistered targets false or pending hostile review: T1 below 10%; T2 cadence-limited and no lower C1 frame-delivery p50; T3 below both >=2x frontend and >=5% e2e; T4 requires Sol acceptance.
Outcome: R7 measurement complete; no competition-worthiness target is currently established. Request hostile Sol technical review. Do not activate the authorized R7.5 fallback until R7 review is complete and all four targets fail.
Lesson: The full corpus confirms the matched path preserves top-1 and activation behavior while exposing small rank-order differences near ties; benchmark claims must retain those disagreements and the standard unsplit context.

## E017 - R7 F-002/F-003 repaired final shared benchmark

Date: 2026-08-11
Base/generating commit: 3b62467f6bb4e8b0a95209f23471ecf2de722d3f
Evidence: `proof/r7-final-b2-c1-shared-repaired.json`, `proof/r7-repaired-batches/3b62467607ba29b58c0d7205dfec06f8f7b909c4/`, `scripts/check_r7_repaired_shared_benchmark.py`

Repair: Replaced the invalid one-warmup continuous run with five separate Release processes. Each process independently initialized state, warmed 20 times, measured 200 pairs, balanced 100/100 execution order, and used a rotated source offset. Aggregate raw records cover all 64 corpus inputs in both orders.
Correctness/protocol: PASS; 5 distinct execution identities, 1,000 raw pairs, 100/100 order balance per batch, deterministic hierarchical bootstrap metadata, explicit `.all`, persistent shared B2/C1 paths, and fail-closed raw-statistics reconstruction.
Production source repair: B2 `executeCHW` and C1 `execute` now encode/commit/wait directly. Profiler-only timing and GPU timestamps remain in separate methods sharing only the encoding helpers; `scripts/check_r7_production_instrumentation.py` passes.
Result: B2 p50 2.483208 ms; C1 p50 2.413458 ms; difference of marginal p50s 0.069750 ms; C1 lower 2.808866%; median paired difference 0.077167 ms; paired-median bootstrap CI [0.068625, 0.091542] ms.
Outcome: QUALIFIED PENDING FRESH HOSTILE REVIEW; below the ≥10% target. The old 2.5013% artifact remains historical/superseded for final CI.
Lesson: Independent batch initialization and independent source/order rotation change the final measured result, so the repaired raw protocol is authoritative for the review decision.

## E018 - R7 F-004/F-007 profiler and environment repair

Date: 2026-08-11
Source repair commit: `b6285f2eb6b9329f925cde81db5936f5f2a8de98`
Evidence: `proof/r7-final-b2-c1-shared-repaired-conditions.json`, `proof/r7-b2-c1-shared-quality-conditions.json`, `proof/r7-final-shared-path-profile-repaired-conditions.json`, `proof/profiler/r7-b2-c1-shared-repaired-events-full.json`

F-007 repair: Reran the unchanged five-process Release protocol and recorded AC Power, Low Power Mode, and thermal state at batch start/end. The fail-closed aggregator/checker requires all five batches to contain valid condition fields.
Result: B2 p50 1.595167 ms; C1 p50 1.561417 ms; marginal-p50 C1 improvement 2.115766%; below the ≥10% target. The prior 2.808866% conditionless result remains historical/superseded.
F-004 repair: Replaced inferred/generic profiler attribution with observed Metal command-buffer labels, observed combined B2 ordered encoder labels, observed C1 native-stem labels, command-buffer-ID joins, 100 nonzero GPU rows joined through 100 observed submission mappings, source-export hashes, and clean completion. The checker now requires exact 50/100/50/100 cardinalities, complete per-command joins, observed alternating order, generating-commit/hash binding, and rehashed negative blank-row, truncation, wrong-path, wrong-cardinality, broken-join, wrong-commit, wrong-encoder, and schema-only tests.
Outcome: EVIDENCE REPAIRED PENDING FRESH HOSTILE RE-REVIEW.
Lesson: Small matched performance differences require explicit power/thermal provenance, and profiler summaries must preserve enough event structure for an independent reviewer to reconstruct attribution.

## E019 - Final R7 hostile closure and R7.5 gate

Date: 2026-08-11
Evidence: `proof/reviews/R7-F004-REPAIRED-5-COMPACT-HOSTILE-20260811.md`, `proof/reviews/R7-REVIEW-PACKET-REPAIRED-5.md`, `proof/r7-competition-targets-repaired-conditions.json`

Final compact hostile review verified F-004 profiler closure and found no regression in benchmark fairness, conditions, quality, Pipeline A qualification, source lineage, historical camera provenance, privacy, or the A/B/C matrix. It returned RETHINK only for F-001: all four preregistered targets remain false/pending and the 2.115766% result is below the 10% target.
Outcome: R7 evidence repair complete; R7 remains formally unaccepted. Under the explicit human authorization, exactly one same-workload R7.5 source-reuse investigation may now be prepared. Before coding, confirm repeated camera/source sampling remains a credible profiler cost, derive the execution schedule with the high-complexity worker, obtain compact architecture review if available, and preregister comparison against strongest B2 and accepted C1. If it does not materially beat C1, freeze performance research and productize the strongest honest result.
