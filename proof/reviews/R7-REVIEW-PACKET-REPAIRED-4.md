# PlaneFuse R7 hostile review packet — repaired iteration 4

Immutable navigation index only; raw evidence remains authoritative. Reviewed source/evidence head before this packet commit: `3a2709602bf4eff680c30157855176a7018f0190` on `phase2/continuum`. Requested review: fresh behaviorally read-only independent hostile technical review under `proof/reviews/REVIEW_CONTRACT.md`; return exactly `VERDICT: SHIP | FIX-FIRST | RETHINK` with actionable findings.

## Fixed contract and targets

R7 uses the fixed output-blind corpus and matched post-resize-to-result boundary. T1 requires ≥10% strongest-C end-to-end p50 improvement with positive paired CI; T2 requires ≥20% sustained camera throughput or materially lower true frame-delivery-to-result; T3 requires ≥2x frontend, zero full RGB, zero element-by-element CPU copy, and ≥5% end-to-end with positive paired CI; T4 requires an independently accepted comparably strong measured result. No thresholds changed. `proof/r7-competition-targets-repaired-conditions.json` records T1/T2/T3 false and T4 pending; no winning claim is made.

## Corpus, strongest B/C, and statistics

Fixed corpus: 64 inputs, 32 real plus 32 procedural stress, with strict provenance and all eight real-image buckets. Strongest matched B is B2-shared: `MetalMobileNetV2RGBPipeline.executeCHW`, Float32 normalized CHW RGB in a persistent `MTLBuffer`, then persistent shared activation and the common `.all` tail. Strongest stable C is C1-shared: `MetalMobileNetV2NativeStem.execute`, Float32 native NV12 stem, then the same activation/tail. Both use explicit `MLComputeUnits.all` and the same input-to-result boundary.

Authoritative performance is `proof/r7-final-b2-c1-shared-repaired-conditions.json`, generated at `b6285f2eb6b9329f925cde81db5936f5f2a8de98`: five separate Release processes; 20 warmups; exactly 200 pairs; 100 B2-first/100 C1-first per batch; rotated offsets/order phases; 1,000 raw pairs; every repeated sample in both orders. B2 p50 `1.595166665 ms`; C1 p50 `1.561416670 ms`; difference of marginal p50s `0.033749995 ms`; C1 lower `2.115766%`. Median paired B2−C1 difference `0.043250002 ms`; deterministic paired bootstrap CI `[0.029624993, 0.064916669] ms`. Difference of marginal p50s and median paired difference are distinct estimands. JSON SHA-256: `922e86c8d19fd9cf44e23f83252428e9227223368626b3440135b2b0307447b5`. Raw batches: `proof/r7-repaired-batches/b6285f/`.

## Quality, context, lineage, and camera

Quality artifact `proof/r7-b2-c1-shared-quality-conditions.json`: top-1 `1.0`; activation max error `8.583068e-6`; top-5 set `0.984375`; top-5 ranking `0.96875`; probability max error `0.001953125`; L1 `0.001053418`. Retained real-image disagreements: `wikimedia-52052040` changes the fifth-set member (`cliff` versus `alp`), while `wikimedia-107696548` swaps `umbrella` and `pot, flowerpot` ranking; top-1 remains equal.

Pipeline A is contextual only: original Core ML image-input path, distinct framework-optimized pre-rendered boundary, p50 `1.1483 ms`. It is not a matched B/C competitor. `proof/r7-source-lineage-release.json` reports source-vs-FullArray top-1 `1.0`, real top-5 set `1.0`, procedural top-5 set `0.84375`, with larger probability differences; qualify this as source image-input preprocessing/backend versus derived-array behavior, not B2/C1 failure.

`proof/r7-camera-evidence.json` is historical Release evidence from `proof/r6.1-camera-benchmark-release.json`. The fresh R7 physical-camera attempt received zero callbacks; no current camera latency/drop values were inferred. Current accepted B2/C1 execution semantics remain unchanged against the historical generating path.

## Profiler and resource evidence

The old boxed-path `proof/r7-final-component-profile.json` remains EXPERIMENTAL and is not final. Final profile artifact: `proof/r7-final-shared-path-profile-repaired-conditions.json`, Release arm64, `.all`, generating commit `b6285f2...`, same B2/C1 paths and tail. Separate bounded capture command:

`xcrun xctrace record --template 'Metal System Trace' --time-limit 10s --no-prompt --output proof/profiler/r7-b2-c1-shared-repaired-labeled.trace --launch -- .build/arm64-apple-macosx/release/planefuse profile mobilenetv2 shared`

Raw trace is intentionally not committed. Durable export `proof/profiler/r7-b2-c1-shared-repaired-events-full.json` has file SHA-256 `96c7e43c9866beebafb2512cfa60ee65f9263e8b049fe34b2af3642a38136826` and canonical payload hash `eb50f16e86309463f10bfa9c41306a048169697e930acef6f2132d0c3a633300`. It contains exactly 50 command, 100 GPU, 50 encoder, and 100 submission-map rows; observed labels show 25 alternating B2 `planefuse.b2.shared` with combined `planefuse.b2.rgb & planefuse.b2.stem`, and 25 C1 `planefuse.c1.shared` with `planefuse.c1.native_stem`; clean target exit is recorded. B2 RGB logical/allocated bytes `602112/606208`; C1 RGB `0/0`; activation `[48,112,112]` strides `[12544,112,1]` through `BufferBackedMultiArray(dataPointer:)`; CPU element-copy `0`.

The profiler checker now requires exact `50/100/50/100` cardinalities, exact workload counts, observed B2/C1 alternating order, exactly two submission mappings per command, one mapped GPU submission per command with two execution points, valid fixed source hashes, profile/expected generating-commit equality, canonical encoder counts, and semantic negative tests whose payload hashes are recomputed. It rejects schema-only, blank/generic, truncated, wrong-path/order, wrong-cardinality, broken-join, fake-hash, wrong-commit, and wrong-encoder mutations.

## Matrix, checks, negatives, and inspection map

`proof/r7-final-selection-matrix.json/.md` is the authoritative checked A/B1/B2/C0/C1/C2/C3/C4 matrix: A contextual; B2 strongest credible matched B; C1 strongest accepted stable C; B1/C0 superseded; C2 quality rejection; C3 stable-toolchain infeasible; C4 no stable end-to-end win. R6.5 direct camera-space fusion remains a separate accepted negative extension. Preserve R3 Float16, R4 Metal 4, R5 no-win, R6.5 slower-C1, camera zero-callback, and prior no-verdict review failures; do not resurrect them.

Passing checks at the reviewed head: `scripts/check_r7_corpus.py`; repaired benchmark checker with expected `b6285f2...`; `scripts/check_r7_shared_profiler.py ... --expected-commit b6285f2...`; profiler privacy; production instrumentation; source-lineage diagnostic; camera provenance; final matrix; repaired targets; benchmark index; project docs; `./pf test quick` (55/55); `./pf build`; `git diff --check`.

Authoritative hashes: quality `df8bfda955f8b6c8b20211a6554fc396af27f1dccb5a7eda770e02ca85ac8ff9`; targets `35abf8000d3d28d89467e3329f45336db5aa22a447e1429cc13f181a84de64a9`; matrix `9f96934e3012479575c8c2807437356d851a133c96544c285b3f0d0023031ff6`; profile `2c5fd6c142e0849c60dee6b481b1b6befb399936b00ee8d4e1c7382abab08fb7`; lineage `4cffcbf522e1c0f201e22446e93608c13cb82beaf4830e2ef76de03f34144079`; camera `fb82442c0646a2a492b41b23029b1900e08f496f9ddeda8efcf52f6d86858ded`.

Inspect first: `MetalMobileNetV2RGBPipeline.executeCHW/executeCHWTimed/encodeCHWConversion/encodeCHWStem`; `MetalMobileNetV2NativeStem.execute/executeTimed/encode`; `MobileNetV2SharedPathProfile`; `CoreMLMobileNetV2TailAdapter.predict(sharedActivation:)`; `scripts/sanitize_r7_profiler_events.py`; `scripts/check_r7_shared_profiler.py`; benchmark, privacy, lineage, camera, and matrix checkers. Known limitations: R7 unaccepted; targets not passed; current camera performance unavailable; raw trace omitted for size; old Git history requires human privacy decision before publication. Do not publish, rewrite history, activate R7.5, or submit.
