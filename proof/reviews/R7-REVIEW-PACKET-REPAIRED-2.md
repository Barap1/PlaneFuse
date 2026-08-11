# PlaneFuse R7 Condition-Complete Repaired Review Packet

## Scope

- Requested review: fresh behaviorally read-only hostile technical re-review of R7 after Sol findings F-004 and F-007.
- Evidence/source head before this packet: `b6285f2eb6b9329f925cde81db5936f5f2a8de98`; this packet is a documentation-only descendant.
- R7 remains unaccepted; F-001 remains open; R7.5 is not active. This packet indexes raw evidence and does not replace it.
- Parent responses: `proof/reviews/R7-FINAL-20260811-01-RESPONSE.md` and `proof/reviews/R7-FINAL-REPAIRED-20260811-02-RESPONSE.md`. Preserved verdict: `proof/reviews/R7-FINAL-REPAIRED-20260811-02.md`.

## Contract, targets, and selection

The unchanged four targets are T1 ≥10% matched B2/C1 end-to-end p50 with positive paired CI; T2 ≥20% sustained camera throughput or materially lower true frame-delivery latency; T3 ≥2x frontend plus zero full RGB/CPU element-copy and ≥5% e2e; T4 another comparably strong result explicitly accepted by hostile review. `proof/r7-competition-targets-repaired-conditions.json` records all four false/pending. The 2.115766% result is not treated as 10%.

`proof/r7-final-selection-matrix.json` and `.md` cover A, B1, B2, C0, C1, C2, C3, C4. Strongest matched B is B2; strongest stable C is C1. Pipeline A is contextual only. B1/C0 are superseded; C2 is quality-rejected; C3 is stable-toolchain-infeasible; C4 has no stable e2e win. R6.5 direct camera-space fusion remains a separate qualified negative.

## Corpus and exact B/C paths

- 64 output-blind inputs: 32 provenance-bearing real images, eight fixed buckets/four each, plus 32 deterministic procedural stress inputs. Corpus artifact: `proof/m5-validation-corpus.json`; verifier: `scripts/check_r7_corpus.py`.
- B2: native NV12 → normalized Float32 CHW RGB materialization → RGB stem → persistent Float32 shared activation → unchanged Core ML MobileNetV2 tail.
- C1: native NV12 → native Y/UV stem → the same persistent activation and Core ML tail.
- Both explicitly request `MLComputeUnits.all`, Float32 `[48,112,112]`, strides `[12544,112,1]`, and `BufferBackedMultiArray(dataPointer:)`. B2 RGB logical/allocated bytes `602112/606208`; C1 `0/0`; CPU element-copy bytes `0`.
- Inspect `MetalMobileNetV2RGBPipeline.executeCHW`, `MetalMobileNetV2NativeStem.execute`, `CoreMLMobileNetV2TailAdapter.predict(sharedActivation:)`, and the matching profiler methods/helpers.

## Authoritative condition-complete performance

Artifact: `proof/r7-final-b2-c1-shared-repaired-conditions.json`, generated at `b6285f2eb6b9329f925cde81db5936f5f2a8de98`.

- Five separate Release processes; execution identities and raw records: `proof/r7-repaired-batches/b6285f/`.
- Every batch: 20 warmups, exactly 200 measured pairs, 100 B2-first/100 C1-first, fixed 64-input corpus. Offsets `[0,12,24,36,48]`, order phases `[0,1,0,1,0]`; every repeated sample appears in both orders.
- B2 p50 `1.5951666646 ms`; C1 p50 `1.5614166696 ms`; difference of marginal p50s `0.0337499951 ms`; C1 lower `2.1157660703%`.
- Median paired B2−C1 difference `0.0432500019 ms`; paired-median bootstrap 95% CI `[0.0296249927,0.0649166686] ms`. Mean-difference CI is also retained. The marginal-p50 difference and paired-median CI are distinct estimands.
- Deterministic bootstrap: five blocks, 200 pairs/block, block size 10, 10,000 replicates, seed `1346783826`.
- Each batch records AC Power, Low Power Mode `0`, and nominal thermal state at start/end. The checker fails closed if any field is absent.

Quality artifact: `proof/r7-b2-c1-shared-quality-conditions.json`, same source commit; top-1 `1.0`, activation max error `8.583068e-6`, top-5 set `0.984375`, top-5 ranking `0.96875`, probability max error `0.001953125`, mean L1 `0.001053418`, two retained real-image disagreements, zero C RGB and CPU element-copy bytes.

## Source-lineage and camera qualification

`proof/r7-source-lineage-release.json` reports top-1 `1.0`, real top-5 set `1.0`, procedural top-5 set `0.84375`; controlled shared stress cases are R0 CPU-only `28/28` versus R7 source `.all` `23/28`. This is a qualified backend/precision explanation, not a B2/C1 quality failure; preprocessing interaction is not proven absent.

Pipeline A remains visible at contextual p50 `1.1482916671 ms` under its distinct pre-rendered image-input boundary. Successful camera evidence is historical in `proof/r7-camera-evidence.json`; accepted live B2/C1 source semantics are unchanged. Fresh R7 acquisition got zero callbacks; no current camera values are inferred.

## Profiler and F-004 closure evidence

- Old `proof/r7-final-component-profile.json` remains experimental boxed historical evidence and is not promoted.
- Current profile: `proof/r7-final-shared-path-profile-repaired-conditions.json`, Release, arm64, `.all`, same B2/C1 shared paths, persistent activation, profiler-only timing/labels/signposts, separate from benchmark.
- Sanitized event export: `proof/profiler/r7-b2-c1-shared-repaired-events-full.json`. It preserves all resolved event rows: 50 command-buffer, 164 GPU execution, 50 encoder. It includes source-export SHA-256 values and a complete temporal attribution table binding every command/encoder row to 25 B2 and 25 C1 calls in the exact B2-then-C1 profile schedule. The source-level expected encoders are B2 `planefuse.b2.rgb` then `planefuse.b2.stem`; C1 `planefuse.c1.native_stem`. xctrace normalized object labels, so both row-level join and source structure are explicitly retained.
- Clean completion status and bounded capture command are recorded; raw `.trace` is intentionally not committed due size. The checker derives cardinality/order/bindings and negative-tests schema-only, truncated, and wrong-path exports.

## Checks

```text
python3 -B scripts/check_r7_corpus.py
python3 -B scripts/check_r7_repaired_shared_benchmark.py proof/r7-final-b2-c1-shared-repaired-conditions.json --expected-commit b6285f2eb6b9329f925cde81db5936f5f2a8de98
python3 -B scripts/check_r7_shared_profiler.py proof/r7-final-shared-path-profile-repaired-conditions.json --events proof/profiler/r7-b2-c1-shared-repaired-events-full.json --expected-commit b6285f2eb6b9329f925cde81db5936f5f2a8de98
python3 -B scripts/check_r7_profiler_privacy.py
python3 -B scripts/check_r7_final_selection_matrix.py
python3 -B scripts/check_r7_repaired_targets.py proof/r7-competition-targets-repaired-conditions.json
python3 -B scripts/check_r7_production_instrumentation.py
python3 -B scripts/check_r7_source_lineage_diagnostic.py
python3 -B scripts/check_r7_camera_provenance.py
python3 -B scripts/check_benchmark_index.py
./pf test quick
./pf build
git diff --check
```

All listed checks passed before this packet. No benchmark threshold was weakened; no new workload/model was used; no R3/R4/R5/R6.5 path was revived.

## Hashes

```text
proof/r7-final-b2-c1-shared-repaired-conditions.json 922e86c8d19fd9cf44e23f83252428e9227223368626b3440135b2b0307447b5
proof/r7-b2-c1-shared-quality-conditions.json         df8bfda955f8b6c8b20211a6554fc396af27f1dccb5a7eda770e02ca85ac8ff9
proof/r7-competition-targets-repaired-conditions.json 35abf8000d3d28d89467e3329f45336db5aa22a447e1429cc13f181a84de64a9
proof/r7-final-shared-path-profile-repaired-conditions.json ea514594f124d30a0eb03a6c5a99032fc0826105a880c6ae4eaba3bdf29be34d
proof/profiler/r7-b2-c1-shared-repaired-events-full.json 282090e2175167d9e7bd37db49d2e1ad4d25559941647e3d29bd2996307f06e9
proof/r7-final-selection-matrix.json                  9f96934e3012479575c8c2807437356d851a133c96544c285b3f0d0023031ff6
proof/r7-camera-evidence.json                          fb82442c0646a2a492b41b23029b1900e08f496f9ddeda8efcf52f6d86858ded
proof/r7-source-lineage-release.json                   4cffcbf522e1c0f201e22446e93608c13cb82beaf4830e2ef76de03f34144079
```

## Limitations and negative results

F-001 remains a strategic hard stop because all targets fail; do not claim a win. Preserve R3 Float16 rejection, R4 Metal 4 infeasibility, R5 no stable end-to-end win, R6.5 slower direct camera-space C, historical camera provenance, procedural lineage qualification, Pipeline A boundary distinction, and the profiler publication history blocker. Inspect the exact symbols/checkers above; do not read raw giant arrays unless a targeted discrepancy requires it.
