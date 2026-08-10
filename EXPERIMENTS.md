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
