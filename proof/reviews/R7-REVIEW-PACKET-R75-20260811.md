# R7/R7.5 independent hostile review packet

Review base: `953e41a` (`phase2/continuum`). The packet is an index, not a replacement for raw evidence. Review is behaviorally read-only: inspect files and recompute/check claims with `git show`, `git diff`, `rg`, `jq`, and `python3 -B`; do not build, benchmark, run wrappers that write logs/caches, or read giant raw arrays unless a targeted check requires it.

Requested output: persist an unchanged artifact under `proof/reviews/` with exactly `VERDICT: SHIP | FIX-FIRST | RETHINK`, actionable findings for non-SHIP, and explicit evaluation of F-002–F-006 closure, R7.5 validity, fairness, reproducibility, quality, strongest B/C selection, Pipeline A context, and all four preregistered competition targets. Do not reinterpret thresholds.

## R7 contract and targets

R7 compares the strongest fair matched B2-shared path with accepted C1-shared on the fixed 64-input output-blind corpus, Release arm64, explicit `MLComputeUnits.all`, persistent shared Float32 activation/tail boundary, five independent processes, 20 warmups per process, 200 pairs per process, and 100/100 order balance. Estimands are nearest-rank p50/p95 and paired B-minus-C differences with the deterministic hierarchical block bootstrap. Difference of marginal p50s and median paired difference are distinct and must not be conflated.

Targets: T1 >=10% C1 p50 improvement versus strongest matched B; T2 application/frame-delivery latency target; T3 >=2x frontend and >=5% e2e; T4 genuinely comparably strong measured result explicitly accepted by Sol. A 2.5% or 2.1% R7 improvement is not a pass.

## Authoritative R7 evidence

- Performance: `proof/r7-final-b2-c1-shared-repaired-conditions.json`, SHA256 `922e86c8d19fd9cf44e23f83252428e9227223368626b3440135b2b0307447b5`; generating benchmark commit `b6285f2eb6b9329f925cde81db5936f5f2a8de98`; B2 p50 `1.595167 ms`, C1 p50 `1.561417 ms`, marginal C1 improvement `2.115766%`, positive paired median CI in artifact.
- Quality: `proof/r7-b2-c1-shared-quality-conditions.json`, SHA256 `df8bfda955f8b6c8b20211a6554fc396af27f1dccb5a7eda770e02ca85ac8ff9`; top-1 `1.0`, activation max `8.583068e-6`, top-5 set `.984375`, top-5 ranking `.96875`, probability max `.001953125`, mean L1 `.001053418`; two retained real-image top-5 disagreements.
- Targets: `proof/r7-competition-targets-repaired-conditions.json`, SHA256 `35abf8000d3d28d89467e3329f45336db5aa22a447e1429cc13f181a84de64a9`; all condition-complete R7 targets false/pending.
- Matrix: `proof/r7-final-selection-matrix.json`, SHA256 `9f96934e3012479575c8c2807437356d851a133c96544c285b3f0d0023031ff6`; rows A/B1/B2/C0/C1/C2/C3/C4. B2 is strongest credible matched B; C1 is strongest accepted stable C; A is contextual; B1/C0 superseded; C2 quality rejection; C3 stable-toolchain infeasible; C4 no stable e2e win; R6.5 is separately documented negative.
- Source lineage: `proof/r7-source-lineage-release.json`, SHA256 `4cffcbf522e1c0f201e22446e93608c13cb82beaf4830e2ef76de03f34144079`; source-vs-FullArray top-1 1.0, real top-5 set 1.0, procedural top-5 set .84375. This qualifies original image-input preprocessing/backend divergence and is not B2/C1 quality failure.
- Camera: `proof/r7-camera-evidence.json`, SHA256 `fb82442c0646a2a492b41b23029b1900e08f496f9ddeda8efcf52f6d86858ded`; successful Release camera result is historical from its generating Release evidence; fresh R7 acquisition got zero callbacks and no current camera measurements were inferred.
- Pipeline A: contextual original Apple image-input boundary, faster under its distinct pre-rendered image-input/framework-optimized boundary; must remain visible and separate from matched B/C.

## F-002–F-006 closure index

- F-002: five batch artifacts under the R7 repaired batch directory and `scripts/check_r7_repaired_shared_benchmark.py`; checker reconstructs batch IDs, warmups, 200 records, order balance, source distribution, both orders for repeated samples, raw statistics, deterministic bootstrap, and provenance.
- F-003: `Sources/PlaneFuseCore/MetalMobileNetV2RGBPipeline.swift` production `executeCHW` and `Sources/PlaneFuseCore/MetalMobileNetV2NativeStem.swift` production `execute` contain no profiler timing/GPU timestamp collection; `executeCHWTimed`/`executeTimed` share only encoding helpers. Check with `scripts/check_r7_production_instrumentation.py`.
- F-004: final profile `proof/r7-final-shared-path-profile-repaired-conditions.json`, SHA256 `2c5fd6c142e0849c60dee6b481b1b6befb399936b00ee8d4e1c7382abab08fb7`; event export `proof/profiler/r7-b2-c1-shared-repaired-events-full.json`, SHA256 `96c7e43c9866beebafb2512cfa60ee65f9263e8b049fe34b2af3642a38136826`. The export has 50 command rows, 100 GPU rows, 50 encoder rows, 100 submission-map rows, observed labels/IDs, clean exit, B2 RGB logical/allocated 602112/606208, C1 RGB 0/0, persistent shared activation, and zero CPU element-copy bytes. `scripts/check_r7_shared_profiler.py` rejects schema-only, zero-event, wrong-path, broken-join, wrong-cardinality, wrong-commit, wrong-workload, and other mutated fixtures.
- F-005: `scripts/check_r7_profiler_privacy.py` (or repository privacy checker invoked by the release checks) verifies current-tree profiler exports are sanitized. Device nicknames, UUIDs, usernames, paths, PIDs, and unrelated inventories are not publication-safe in Git history. Publication remains blocked until the human chooses history sanitization/rewrite or a clean sanitized public repository/history; no rewrite/force-push was performed.
- F-006: the A/B/C matrix above is machine-readable and human-readable; obsolete/rejected rows use existing evidence and are not rerun.

## R7.5 source-reuse candidate

R7.5 is the one authorized same-workload fallback, not a workload/model pivot. Architecture review `proof/reviews/R7.5-SOURCE-REUSE-ARCH-20260811.md` returned `SHIP` before implementation. The fixed candidate uses exact NV12 source mapping, 4x4 spatial tiles, cooperative Y/UV tile loads, unchanged coefficients/SAME/ReLU6/tail, and persistent activation handoff. Source files: `Sources/PlaneFuseCore/R75SourceReuseBenchmark.swift`, `Sources/PlaneFuseCore/Shaders/NV12MobileNetV2Stem.metal`, `Sources/PlaneFuseCore/MetalMobileNetV2NativeStem.swift`.

Authoritative confirmation: `proof/r7.5-source-reuse-final-52db138-20260811T1605Z-confirm.json`, SHA256 `268131c9e9f5d19e49b4ebf4c3c8edebb25fe1cae910c2556cbb89191ef758f3`, generating commit `52db138feef3d6fc52bcb5839a419423fd992019`; raw batches under `proof/r7.5-source-reuse-batches/52db138-20260811T1605Z-confirm/`; checker `scripts/check_r75_source_reuse.py`.

R7.5 protocol: five independent Release processes; 20 warmup triples; 240 measured triples; six B2/C1/C1-SR permutations exactly 40 times per batch; fixed 64-input corpus; `.all`; raw records; deterministic 10,000-replicate block bootstrap. Confirmation B2 p50 `1.737875 ms`, C1 `1.633458 ms`, C1-SR `1.532583 ms`; C1-SR is `6.1755%` below C1 and `11.8128%` below B2; C1-minus-C1-SR paired median CI `[0.091125, 0.101750] ms`. Full quality: activation max `5.960464e-6`, top-1/top-5-set/top-5-ranking `1.0`, probability max `.001953125`, mean L1 `.001176831`, 64 samples, no disagreements.

The first primary artifact `proof/r7.5-source-reuse-final-c5733db-20260811T1550Z.json` is retained as historical because it predates complete top-5/probability field retention; it is not the authoritative confirmation.

## Known negatives and limitations

Do not resurrect R3/R4/R5/R6.5, Float16, Metal 4, polyphase retuning, or the old boxed MLMultiArray profile. R6.5 direct camera-space fusion is a qualified negative because eliminating an intermediate lost reuse value. R7 source lineage procedural divergence is qualified, not B2/C1 failure. R7 camera performance is unavailable for the fresh attempt. R7.5 is not a license to start another performance round. No publication, public-repo change, video upload, or Devpost submission is authorized.
