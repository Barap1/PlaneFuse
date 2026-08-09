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
Outcome: ACCEPT
Lesson: The real pretrained model preserves the native-stem equivalence and a smaller but repeated end-to-end win after the unchanged Core ML tail. The current CPU-visible MLMultiArray handoff is included in e2e timing; no zero-copy Core ML claim is made.
Accepted commit: 492a171

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
