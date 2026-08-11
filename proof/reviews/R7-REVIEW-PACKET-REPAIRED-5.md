# PlaneFuse R7 hostile review packet — final F-004 repair

Immutable navigation index; raw evidence remains authoritative. Reviewed source/evidence head before this packet-only commit: `ee3381c9fae0a21ac48b40e18e50b576acb7042c` on `phase2/continuum`. Requested review: fresh behaviorally read-only independent hostile technical review under `proof/reviews/REVIEW_CONTRACT.md`; return exactly `VERDICT: SHIP | FIX-FIRST | RETHINK`.

## Fixed contract, corpus, paths, and targets

R7 uses the fixed output-blind corpus: 64 inputs, 32 real plus 32 procedural stress, strict provenance and eight real-image buckets. Matched boundary is post-resize-to-result with explicit `MLComputeUnits.all`. Strongest B is B2-shared (`MetalMobileNetV2RGBPipeline.executeCHW`): Float32 normalized CHW RGB materialized in a persistent buffer, then persistent activation/common tail. Strongest stable C is C1-shared (`MetalMobileNetV2NativeStem.execute`): Float32 native NV12 stem, then the same activation/tail.

Targets are unchanged: T1 ≥10% end-to-end p50 with positive paired CI; T2 ≥20% camera throughput or materially lower true frame-delivery-to-result; T3 ≥2x frontend, zero full RGB, zero element-copy, and ≥5% end-to-end with positive paired CI; T4 independently accepted comparably strong measured result. Target artifact records T1/T2/T3 false and T4 pending; no winning claim is made.

Authoritative performance: `proof/r7-final-b2-c1-shared-repaired-conditions.json`, generated at `b6285f2eb6b9329f925cde81db5936f5f2a8de98`; five separate Release processes, 20 warmups, 200 pairs, 100/100 order per batch, rotated offsets/phases, all repeated samples both orders. B2 p50 `1.595166665 ms`; C1 p50 `1.561416670 ms`; marginal p50 difference `0.033749995 ms`; C1 lower `2.115766%`; median paired B2−C1 `0.043250002 ms`, bootstrap CI `[0.029624993, 0.064916669] ms`. Distinguish marginal-p50 percentage from paired-median CI. JSON SHA `922e86c8d19fd9cf44e23f83252428e9227223368626b3440135b2b0307447b5`; raw batches `proof/r7-repaired-batches/b6285f/`.

Quality: `proof/r7-b2-c1-shared-quality-conditions.json` reports top-1 `1.0`, activation max error `8.583068e-6`, top-5 set `0.984375`, top-5 ranking `0.96875`, probability max `0.001953125`, L1 `0.001053418`. Retained real disagreements: `wikimedia-52052040` fifth-set member differs (`cliff`/`alp`); `wikimedia-107696548` swaps `umbrella`/`pot, flowerpot` ranking; top-1 remains equal. Pipeline A is contextual only (pre-rendered image boundary, p50 `1.1483 ms`). Source lineage reports top-1 `1.0`, real top-5 set `1.0`, procedural top-5 set `0.84375`, qualified as backend/preprocessing divergence. Camera evidence is historical; fresh R7 acquisition had zero callbacks and no inferred current values.

## Final profiler evidence

Old boxed `proof/r7-final-component-profile.json` is EXPERIMENTAL, not final. Final profile: `proof/r7-final-shared-path-profile-repaired-conditions.json`, Release arm64 `.all`, source commit `b6285f2...`, separate bounded capture:

`xcrun xctrace record --template 'Metal System Trace' --time-limit 10s --no-prompt --output proof/profiler/r7-b2-c1-shared-repaired-labeled.trace --launch -- .build/arm64-apple-macosx/release/planefuse profile mobilenetv2 shared`

Raw trace is omitted due size. Durable `proof/profiler/r7-b2-c1-shared-repaired-events-full.json`: file SHA `96c7e43c9866beebafb2512cfa60ee65f9263e8b049fe34b2af3642a38136826`, canonical payload SHA `eb50f16e86309463f10bfa9c41306a048169697e930acef6f2132d0c3a633300`; exact 50 command/100 GPU/50 encoder/100 submission-map rows; clean exit; observed alternating 25 B2 `planefuse.b2.shared` with `planefuse.b2.rgb & planefuse.b2.stem` and 25 C1 `planefuse.c1.shared` with `planefuse.c1.native_stem`. B2 RGB logical/allocated `602112/606208`; C1 RGB `0/0`; activation `[48,112,112]` strides `[12544,112,1]` via `BufferBackedMultiArray(dataPointer:)`; CPU element-copy `0`.

The final checker requires exact event cardinalities, workload `warmup_iterations=5` and `measured_iterations=20`, every command encoder count `1`, observed alternating schedule, two mappings per command, 100 unique mapped submissions, one mapped GPU submission per command with two execution points, exact invocation-to-mapping submission IDs, fixed source-export hashes, and profile/expected generating-commit equality. It rehashes and semantically rejects schema-only, truncation, wrong path/order, wrong cardinality, broken cardinality-preserving joins, fake hash, wrong commit, wrong/null encoder, wrong workload, and blank/generic mutations for named reasons.

## Matrix, checks, and limitations

`proof/r7-final-selection-matrix.json/.md` contains checked rows A/B1/B2/C0/C1/C2/C3/C4: A contextual; B2 strongest matched B; C1 strongest stable C; B1/C0 superseded; C2 quality rejected; C3 infeasible on stable toolchain; C4 no stable e2e win. R6.5 direct camera-space fusion remains a separate accepted negative. Preserve all R3/R4/R5/R6.5 negatives, camera zero-callback failure, and prior no-verdict failures.

Passing checks: corpus; repaired benchmark with expected `b6285f2...`; profiler checker with expected commit; profiler privacy; production instrumentation; source-lineage; camera provenance; matrix; targets; benchmark index; docs; `./pf test quick` 55/55; `./pf build`; `git diff --check`. Inspect first: B2/C1 production and profiler methods, `MobileNetV2SharedPathProfile`, `CoreMLMobileNetV2TailAdapter.predict(sharedActivation:)`, sanitizer/checker, benchmark/privacy/lineage/camera/matrix checkers. R7 remains unaccepted; all targets are not passed; F-001 remains open; publication/history sanitization, R7.5, and submission are human gates.
