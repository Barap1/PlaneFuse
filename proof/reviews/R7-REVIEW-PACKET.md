# PlaneFuse R7 Independent Review Packet

## Scope and immutable scope

- Requested review: hostile technical acceptance of R7, including the preregistered T1–T4 decision.
- Evidence/source head assembled before this packet: `72457c7686be1a348be2f66a38b3c3c88f513775` (`bench(evidence): verify historical camera provenance`).
- The packet commit is a documentation-only descendant of that head. Review the packet plus the actual current tree; no benchmark or implementation file changes occur in the packet commit.
- R7 is not accepted, T4 is not accepted, and R7.5 is not active.
- This packet indexes raw evidence; it does not replace it or restate unmeasured results.

## Contract and competition targets

R7 requires an output-blind 64-input corpus, matched strongest-B/C measurements, persistent shared activation evidence, quality gates, camera-path provenance, and final profiler evidence. The four preregistered targets are:

1. T1: C1 end-to-end p50 improvement >=10% over B2 with a positive paired CI.
2. T2: >=20% sustained camera throughput improvement or materially lower matched frame-delivery-to-result latency.
3. T3: >=2x frontend improvement, zero full RGB, zero element-by-element CPU activation copy, and >=5% end-to-end improvement with positive paired CI.
4. T4: another comparably strong measured result explicitly accepted by hostile technical review.

The measured record currently says all four are false/pending. A 2.5% result is not treated as a 10% result.

## Corpus and exact B/C definitions

- Corpus: 64 inputs: 32 provenance-bearing real images (8 fixed categories, 4 each) and 32 procedural stress inputs. R7 corpus checker confirms the 4/4 bucket structure and output-blind selection.
- B2: native NV12 input -> Metal video-range conversion to normalized Float32 CHW RGB -> MobileNetV2 RGB stem -> persistent Float32 shared activation -> the same Core ML tail.
- C1: native NV12 input -> Metal video-range native Y/UV stem -> the same persistent Float32 shared activation -> the same Core ML tail.
- Both use `MLComputeUnits.all`, the same model/tail, Float32 activation shape `[48,112,112]`, strides `[12544,112,1]`, and `BufferBackedMultiArray(dataPointer:)`; B2 and C1 differ only in the frontend representation path.
- Production symbols: `MetalMobileNetV2RGBPipeline.executeCHW`, `MetalMobileNetV2NativeStem.execute`, and `CoreMLMobileNetV2TailAdapter.predict(sharedActivation:)`.

## Matched performance and quality

Authoritative performance: `proof/r7-final-b2-c1-shared-current.json`.

- Five independent 200-pair batches, 20 warmups per batch, 1,000 measured pairs; post-resize-input-to-result boundary.
- B2 p50: `1.6641250004 ms`; C1 p50: `1.6224999999 ms`.
- Difference of marginal p50s: `0.0416250004 ms`, C1 lower by `2.5013145310%`.
- Median paired B2-C1 difference: `+0.0480833332 ms`; paired-median bootstrap CI: `[+0.0415000031, +0.0542916678] ms`.
- These are different estimands: the percentage is computed from the two marginal medians; the CI is for the median of paired per-sample differences. They must not be conflated.
- B2 p95: `2.1574166676 ms`; C1 p95: `1.8917499983 ms`.
- Top-1 agreement: `1.0`; activation maximum absolute error: `0.00000858306885`, under the existing `0.00000999999975` threshold.
- Quality summary: top-5 set agreement `0.984375`, top-5 ranking agreement `0.96875`, minimum activation cosine `0.999999999997659`, probability maximum absolute error `0.001953125`, mean probability L1 `0.001053418032825`.
- The two retained real-image top-5 disagreements are `wikimedia-52052040` (set and ranking disagreement) and `wikimedia-107696548` (ranking disagreement; set agrees). Both retain top-1 agreement.
- No quality threshold was weakened and procedural cases remain included.

Pipeline A remains visible as context, not as the matched B/C claim: its pre-rendered 224x224 image-input boundary has p50 `1.1482916671 ms` at commit `8f9e98dd...`; it is faster under a distinct framework-optimized input boundary.

## Source lineage qualification

`proof/r7-source-lineage-release.json` compares the original source-image adapter using `.all` with the FullArray `.cpuOnly` derived-array path. It reports top-1 agreement `1.0`, real top-5 set agreement `1.0`, procedural top-5 set agreement `0.84375`, probability maximum absolute difference `0.0148681998`, and mean probability L1 `0.01344179`.

The controlled 28 shared stress-input comparison shows R0 CPU-only source-vs-FullArray top-5 `28/28`, while R7 source `.all` vs FullArray is `23/28`; R7 full procedural is `27/32` and real is `32/32`. The source adapter changed from explicit `.cpuOnly` to `.all` at commit `578a96c` (after the R0 artifact). This is strong evidence that backend/precision policy explains the procedural divergence, but does not prove that every preprocessing/backend interaction is absent. It is qualified separately and is not a B2/C1 quality failure.

## Camera provenance

- Successful Release evidence is explicitly historical: `proof/r6.1-camera-benchmark-release.json`, 300 replay frames plus five 200-pair batches, generated by the camera harness at `93a701632df6a83df4c01d06511c5432a688cd9e` and recorded at `46fbe3d5cf3df1d1d25f82d181d130ad8305959e`.
- Current accepted live semantics remain equivalent: `CameraInferenceRunner.inferB2` uses `executeCHW` plus shared-tail prediction; `inferC1` uses native `execute` plus the same shared-tail prediction. The later R6.5 source-space additions are separate and not used by this accepted path. The NV12 bridge refactor preserves video-range validation, geometry, shaders, output, and synchronization.
- Fresh R7 physical-camera attempt: `proof/r7-camera-session-attempt-20260811.json`, `unavailable_before_first_callback`, zero callbacks/processed frames. No current camera latency or drop result is inferred.
- Historical Release quality recorded top-1 `1.0`, C1 RGB resource `0`, and CPU element population `0`; its paired camera CI crosses zero and is not a new positive performance claim.

## Final shared-path profiler

The old `proof/r7-final-component-profile.json` is intentionally still `EXPERIMENTAL`: it is an R1 boxed `MLMultiArray` population profile at commit `8bea11d3...`, not the accepted B2-shared/C1-shared path.

The replacement `proof/r7-final-shared-path-profile.json` profiles the exact accepted implementations in a separate profile command (5 warmups, 20 measured iterations):

- B2 frontend GPU p50 `0.3055833331 ms`; C1 frontend GPU p50 `0.2396249984 ms`.
- B2 input-to-result p50 `2.1870833334 ms`; C1 `1.9924166663 ms`.
- B2 RGB logical/Metal allocated bytes: `602112` / `606208`.
- C1 RGB logical/Metal allocated bytes: `0` / `0`.
- CPU element-by-element activation copy bytes: `0`.
- Persistent shared activation handoff: Float32 `[48,112,112]`, strides `[12544,112,1]`, 2,408,448-byte B2/C1 buffers retained through `BufferBackedMultiArray(dataPointer:)`.
- Durable profiler export: `proof/profiler/r7-b2-c1-shared-toc.xml` and command-buffer schema export. The raw 261 MB Metal System Trace bundle remains local at `proof/profiler/r7-b2-c1-shared.trace/` and is intentionally not committed. Reproduction command:
  `xcrun xctrace record --template 'Metal System Trace' --time-limit 45s --output proof/profiler/r7-b2-c1-shared.trace --launch -- .build/arm64-apple-macosx/release/planefuse profile mobilenetv2 shared`
- Profile commit/environment: `f615847fe6e1aa6e56fbfc442b17f25fda5d5d83`, arm64 Release, Apple M5 Pro, macOS `26.6.1 (25G76)`, Swift `6.3.3`, Xcode `26.6`. The profile is not a benchmark run and did not alter B2/C1 performance implementation.

## Checks and authoritative paths

Passing checks:

- `python3 -B scripts/check_benchmark_index.py`
- `python3 -B scripts/check_r7_corpus.py`
- `python3 -B scripts/check_r6_5_camera_space_artifact.py proof/r6.5-camera-space.json`
- `python3 -B scripts/check_r7_camera_provenance.py`
- `python3 -B scripts/check_r7_shared_profiler.py --expected-commit f615847fe6e1aa6e56fbfc442b17f25fda5d5d83`
- `python3 -B scripts/check_r7_source_lineage_diagnostic.py`
- `./pf build`, `./pf test quick`, and `git diff --check`

Authoritative artifact SHA-256:

```
proof/r7-final-b2-c1-shared-current.json       21e7196cddfdca1141209113930c03c2227217dd9f0ae19d1f818733fda00a6f
proof/r7-b2-c1-shared-quality-clean.json       5afdb43a5948894ee331f017ade87fe58bdd861d346b1a440283964a51a5a057
proof/r7-competition-targets.json              264b888baa39cd69f0117e54e783f1b5b206742ceb6c4fe885749a098c57f970
proof/r7-source-lineage-release.json           4cffcbf522e1c0f201e22446e93608c13cb82beaf4830e2ef76de03f34144079
proof/r7-camera-evidence.json                  fb82442c0646a2a492b41b23029b1900e08f496f9ddeda8efcf52f6d86858ded
proof/r6.1-camera-benchmark-release.json      a4836f618c268c50d6bda116525458b8df096b3b93c2468114a3a3aa2fd77323
proof/r6.1-camera-replay.bin                   1bf39d0b944aa6f780361134667eed6b01cf3af4a81bfe064ba8a6e6e88c4a3f
proof/r6.1-camera-replay.manifest.json         a439175593d6a93cfe0ab6af60499cc83483faa412e1c6924ca00d7f28c76e3a
proof/r7-camera-session-attempt-20260811.json 5f56fc1b75a0e019f1d720b6f8dd765386c110021b1661617f6d4051f80192a9
proof/r7-final-pipeline-a-current.json         a070b0b38fd3279b4854c53079acad4d0ca62068f2b050777fd084a088ae69a8
proof/r7-final-shared-path-profile.json        4111b28706e6fb14a452cd62540f1bf9fbaf53fd442a516b0c1a9d139ab7ec7c
proof/profiler/r7-b2-c1-shared-toc.xml         3dba4569c2cfebc8f88059f321176cd09af25ebddab445249a9c2dea217b9a1f
proof/profiler/r7-b2-c1-shared-command-buffers.xml 4cb55cf68660dbce31036b0b10491e41513424fa391e894b4a18e30eb44c11a3
proof/r6.5-camera-space.json                  0942413b205f442c21ef6a7b4273b00a924d488439a22de29e39b680287c54b4
proof/r6.5-camera-source-replay.bin           c9bda8d59ebe90fb321504f2c696022bf036ff0e38b5f88a5790dd60f51b2966
```

## Negative results and limitations

- R3 Float16 failed its quality gate; do not revive it.
- R4 Metal 4 was infeasible on the stable toolchain; do not revive it.
- R5 polyphase work did not produce a stable end-to-end win; do not retune it.
- R6.5 direct camera-space C was slower than accepted C1 (and its paired interval was negative); do not treat it as a candidate.
- Fresh R7 camera acquisition had zero callbacks; do not infer missing values.
- No power, peak-memory, or unobservable Core ML internal-copy claim is made.
- The raw profiler bundle is local rather than committed because of size; the compact exported trace evidence and exact capture command are committed.
- Pipeline A has a distinct pre-rendered image-input boundary.

Inspect these symbols/files first: `Sources/PlaneFuseCore/MobileNetV2DirectSharedBenchmark.swift`, `Sources/PlaneFuseCore/MobileNetV2SharedQualityEvidence.swift`, `Sources/PlaneFuseCore/MetalMobileNetV2RGBPipeline.swift`, `Sources/PlaneFuseCore/MetalMobileNetV2NativeStem.swift`, `Sources/PlaneFuseCore/MobileNetV2Integration.swift`, `Sources/PlaneFuseCore/Shaders/NV12MobileNetV2RGB.metal`, `Sources/PlaneFuseCore/Shaders/NV12MobileNetV2Stem.metal`, `Sources/PlaneFuseLive/main.swift`, `Sources/PlaneFuseLive/CameraNV12MetalBridge.swift`, and `Sources/PlaneFuseLive/CameraBenchmarkSupport.swift`.
