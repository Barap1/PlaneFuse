# PlaneFuse R7 hostile review packet — repaired iteration 3

This is an immutable navigation index, not a replacement for raw evidence. Current head: `e5a3cc195cee660045bd7d0616af6f801dd3e2b3` (`phase2/continuum`). Requested review: behaviorally read-only independent hostile technical review under `proof/reviews/REVIEW_CONTRACT.md`; return exactly `VERDICT: SHIP | FIX-FIRST | RETHINK` with actionable findings.

## Contract and decision targets

R7 compares the fixed output-blind 64-input corpus under matched post-resize-to-result boundaries. The four unchanged preregistered targets are:

- T1: strongest matched C end-to-end p50 improvement ≥10% with positive paired CI.
- T2: sustained camera throughput ≥20% higher, or materially lower true frame-delivery-to-result, with matched quality.
- T3: ≥2x frontend improvement, zero full RGB, zero element-by-element CPU activation copy, and ≥5% end-to-end improvement with positive paired CI.
- T4: another comparably strong measured result explicitly accepted by hostile technical review.

No threshold has changed. Current target artifact marks T1/T2/T3 false and T4 pending; the 2.115766% result is not a winning claim.

## Corpus, strongest paths, and estimands

The authoritative corpus is 64 fixed samples: 32 real images plus 32 procedural stress inputs, selected and recorded in the raw corpus manifest/evidence. Repeated samples are measured in both execution orders across five independent Release processes.

- Strongest matched B: B2-shared, `MetalMobileNetV2RGBPipeline.executeCHW`, Float32 normalized CHW RGB materialized in a persistent `MTLBuffer`, then shared activation/tail.
- Strongest accepted stable C: C1-shared, `MetalMobileNetV2NativeStem.execute`, Float32 native NV12/YUV-to-stem, then the same persistent activation/tail.
- Both use explicit `MLComputeUnits.all`, the same tail/model configuration, and the same post-resize input-to-result boundary.

Authoritative performance: `proof/r7-final-b2-c1-shared-repaired-conditions.json`, generating commit `b6285f2eb6b9329f925cde81db5936f5f2a8de98`. Five distinct batches each contain 20+ warmups, 200 measured pairs, and 100 B2-first/100 C1-first pairs. B2 p50 = `1.595166665 ms`; C1 p50 = `1.561416670 ms`; difference of marginal p50s = `0.033749995 ms`, C1 lower `2.115766%`. The median paired B2−C1 difference is `0.043250002 ms`, with deterministic paired-median bootstrap CI `[0.029624993, 0.064916669] ms`. These are distinct estimands; the marginal-p50 percentage is not the paired-median CI.

Raw batches: `proof/r7-repaired-batches/b6285f/`; checker reconstructs all statistics from raw records. Performance SHA-256: `922e86c8d19fd9cf44e23f83252428e9227223368626b3440135b2b0307447b5`.

## Quality and disagreements

`proof/r7-b2-c1-shared-quality-conditions.json` records 64/64 top-1 agreement; activation maximum absolute error `8.583068e-6`; top-5 set agreement `0.984375`; top-5 ranking agreement `0.96875`; probability maximum absolute error `0.001953125`; probability L1 distance `0.001053418`. The two retained real-image top-5 disagreements are:

- `wikimedia-52052040`: top-1 agrees; B2 includes `cliff, drop, drop-off`, C1 includes `alp`.
- `wikimedia-107696548`: top-1 and top-5 set agree; `umbrella` and `pot, flowerpot` exchange rank.

These are quality qualifications near ties, not B2/C1 top-1 failures. No disagreement is removed.

## Pipeline A context and source lineage

Pipeline A remains visible as contextual only: original Core ML image-input path, framework-optimized pre-rendered image boundary, p50 `1.1483 ms`; it is not a matched B/C competitor.

Source-lineage evidence `proof/r7-source-lineage-release.json` reports source-vs-FullArray top-1 agreement `1.0`, all-real top-5 set agreement `1.0`, procedural top-5 set agreement `0.84375`, and probability differences larger than direct B2/C1 differences. The controlled interpretation is that the procedural divergence is original image-input preprocessing/backend execution versus derived-array execution; it is retained as a qualification and not converted into a B2/C1 quality failure.

## Camera provenance

`proof/r7-camera-evidence.json` is explicitly historical: successful Release 300-frame camera/replay evidence comes from `proof/r6.1-camera-benchmark-release.json`. A fresh R7 physical-camera attempt received zero callbacks and produced no inferred measurements. Current live-path source semantics remain equivalent for the accepted B2/C1 execution path; the provenance artifact and current-source comparison are retained. Camera performance is unavailable as a fresh current measurement.

## Profiler evidence and resources

The old `proof/r7-final-component-profile.json` remains `EXPERIMENTAL` and profiles the historical boxed MLMultiArray path; it is not final evidence. Final profiler artifact: `proof/r7-final-shared-path-profile-repaired-conditions.json`, source commit `b6285f2eb6b9329f925cde81db5936f5f2a8de98`, Release, arm64, `.all`, same B2/C1 shared paths and tail. Capture is separate from benchmark runs:

`xcrun xctrace record --template 'Metal System Trace' --time-limit 10s --no-prompt --output proof/profiler/r7-b2-c1-shared-repaired-labeled.trace --launch -- .build/arm64-apple-macosx/release/planefuse profile mobilenetv2 shared`

The raw trace is intentionally not committed due size. Durable event export: `proof/profiler/r7-b2-c1-shared-repaired-events-full.json`; file SHA-256 `96c7e43c9866beebafb2512cfa60ee65f9263e8b049fe34b2af3642a38136826`; canonical payload hash `eb50f16e86309463f10bfa9c41306a048169697e930acef6f2132d0c3a633300`. The export contains 50 command rows, 50 encoder rows, 100 nonzero GPU rows, and 100 submission-to-command-buffer rows. Observed Metal labels—not array parity—show 25 B2 `planefuse.b2.shared` rows with combined ordered `planefuse.b2.rgb & planefuse.b2.stem`, and 25 C1 `planefuse.c1.shared` rows with `planefuse.c1.native_stem`; command-buffer IDs join encoder and GPU/submission rows. The TOC records clean target exit 0.

Resource evidence: B2 materialized RGB logical/allocated bytes `602112/606208`; C1 RGB `0/0`; persistent shared activation shape `[48,112,112]`, strides `[12544,112,1]`, `BufferBackedMultiArray(dataPointer:)`; CPU element-by-element activation copy `0` bytes. Production paths contain no profiler-only timing/GPU timestamp collection; profiler paths share only encoding helpers.

## Matrix and dispositions

Authoritative matrix: `proof/r7-final-selection-matrix.json` and `proof/r7-final-selection-matrix.md` (SHA-256 JSON `9f96934e3012479575c8c2807437356d851a133c96544c285b3f0d0023031ff6`). Rows A, B1, B2, C0, C1, C2, C3, C4 are all present. B2/C1 are eligible for matched comparison; A is contextual; B1/C0 are superseded; C2 is quality-rejected; C3 is stable-toolchain-infeasible; C4 has no stable end-to-end win. R6.5 direct camera-space fusion remains a separately documented accepted negative extension, not a matrix row.

Known negatives that must not be resurrected: R3 Float16 quality failure; R4 Metal 4 stable-toolchain infeasibility; R5 no stable end-to-end win; R6.5 direct camera-space C slower than accepted C1; fresh R7 camera zero-callback failure; prior hostile Sol no-verdict attempts. F-001 remains open. No R7.5 implementation is active.

## Checks and raw-artifact index

The following targeted checks pass at the current tree: `python3 -B scripts/check_r7_corpus.py`; repaired benchmark checker with expected commit `b6285f2...`; `python3 -B scripts/check_r7_shared_profiler.py proof/r7-final-shared-path-profile-repaired-conditions.json --events proof/profiler/r7-b2-c1-shared-repaired-events-full.json --expected-commit b6285f2...`; `python3 -B scripts/check_r7_profiler_privacy.py`; `python3 -B scripts/check_r7_production_instrumentation.py`; `python3 -B scripts/check_r7_source_lineage_diagnostic.py`; `python3 -B scripts/check_r7_camera_provenance.py`; `python3 -B scripts/check_r7_final_selection_matrix.py`; `python3 -B scripts/check_r7_repaired_targets.py proof/r7-competition-targets-repaired-conditions.json`; `python3 -B scripts/check_benchmark_index.py`; `./pf test quick`; `./pf build`; `git diff --check`.

Other authoritative hashes: quality `df8bfda955f8b6c8b20211a6554fc396af27f1dccb5a7eda770e02ca85ac8ff9`; targets `35abf8000d3d28d89467e3329f45336db5aa22a447e1429cc13f181a84de64a9`; profiler artifact `2c5fd6c142e0849c60dee6b481b1b6befb399936b00ee8d4e1c7382abab08fb7`; source lineage `4cffcbf522e1c0f201e22446e93608c13cb82beaf4830e2ef76de03f34144079`; camera provenance `fb82442c0646a2a492b41b23029b1900e08f496f9ddeda8efcf52f6d86858ded`.

## Inspect these symbols first

`Sources/PlaneFuseCore/MetalMobileNetV2RGBPipeline.swift`: `executeCHW`, `executeCHWTimed`, `encodeCHWConversion`, `encodeCHWStem`; `Sources/PlaneFuseCore/MetalMobileNetV2NativeStem.swift`: `execute`, `executeTimed`, `encode`; `Sources/PlaneFuseCore/MobileNetV2SharedPathProfile.swift`: profiler-only path and persistent-tail handoff; `Sources/PlaneFuseCore/CoreMLMobileNetV2TailAdapter.swift`: `predict(sharedActivation:)`; `scripts/sanitize_r7_profiler_events.py`; `scripts/check_r7_shared_profiler.py`; `scripts/check_r7_repaired_shared_benchmark.py`; `scripts/check_r7_profiler_privacy.py`.

Current known limitations: R7 is not accepted; all four targets are not passed; camera current performance is unavailable; raw traces are not committed; old private Git history still requires a human choice of history sanitization or clean sanitized publication history before any public release. Do not publish, rewrite history, activate R7.5, or submit from this packet.
