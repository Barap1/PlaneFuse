# PlaneFuse architectural decisions

Record only durable decisions that future Codex sessions should not repeatedly reconsider.

## D001 - Start on native macOS Apple Silicon

Status: accepted

Decision: Early mathematical, Metal, and benchmark work runs directly on the Apple-Silicon Mac. Do not begin with an iOS Simulator target.

Why: Real performance measurement should use the actual Arm hardware without simulator timing ambiguity, signing friction, or mobile UI work before the optimization is proven.

Revisit when: M8/M9 if an iOS version would materially strengthen the final demonstration and time permits.

## D002 - Fair benchmark requires optimized RGB baseline

Status: accepted

Decision: The core performance claim must compare PlaneFuse Pipeline C against optimized RGB Pipeline B, not only against a naive/ordinary Pipeline A.

Why: This avoids a strawman result and is central to technical credibility.

## D003 - No custom PlaneFuse Codex skill at bootstrap

Status: accepted

Decision: Use root AGENTS.md + repository documents + XcodeBuildMCP + Sol Advisor initially. Do not create a custom PlaneFuse skill during M0.

Why: The recurring optimization workflow is not yet proven. Encoding speculative behavior in another always-discoverable instruction surface would add context and maintenance overhead.

Revisit when: after M3/M4 if a stable reusable experiment/evidence workflow has emerged.

## D004 - Local commits are autonomous; remote publishing is not

Status: accepted

Decision: Codex may make local Conventional Commits without asking. It must ask before pushing or publishing.

Why: Frequent local commits improve rollback and experiment traceability while keeping external actions under human control.

## D005 - SwiftPM macOS package is the M0 foundation

Status: accepted

Decision: Start with a native macOS Swift Package Manager library plus executable CLI, keeping the early reference math and benchmark harness independent of an app target.

Why: It gives deterministic build/test/CLI behavior on real Apple Silicon and avoids simulator, signing, and UI complexity before the optimization is proven. A macOS app target can be added at M9 without changing the core library boundary.

Evidence: M0 gate passed with `./pf build`, `./pf test quick`, `./pf doctor`, `./pf verify`, and `./pf bench quick`.

Revisit when: M9 if the live camera shell requires an Xcode app target.

## D006 - M1 affine proof scope and tolerance

Status: accepted

Decision: M1 supports 8-bit bi-planar NV12 with BT.601 video-range decoding, one decoded Y/Cb/Cr sample per output pixel, per-channel normalization, and a 1x1 linear stem. The reference parity target is max absolute error <= 1e-12 in Double precision.

Why: This proves the coefficient composition and bias handling without implying support for resize interpolation, nonlinear transfer functions, clipping policy, chroma siting, spatial convolution, or arbitrary model stems. Those semantics must be locked before GPU/native performance claims.

Evidence: `proof/m1-reference-parity.json` records 512 deterministic samples with max absolute error 2.220446049250313e-15; the configured read-only Sol Advisor returned `proceed` and identified real NV12 plane semantics and GPU precision as M2/M3 risks.

Revisit when: M2 locks source-plane sampling and M3 establishes GPU parity thresholds.

## D007 - M2 locks the first real NV12 plane contract

Status: accepted

Decision: The M2 baseline consumes an 8-bit `R8Uint` Y plane at full resolution and an `RG8Uint` UV plane at half width and half height. Each output pixel uses the nearest stored UV pair at `(x / 2, y / 2)`, applies BT.601 video-range decoding and normalization, and writes a same-size `RGBA32Float` model-input texture. No resize, interpolation, or RGB clamp is part of this contract.

Why: Pipeline B and the first native-plane C kernel need identical source-grid semantics before timing or parity comparisons are meaningful. The contract exposes the exact 4:2:0 geometry rather than treating NV12 as an opaque RGB source.

Evidence: `Sources/PlaneFuseCore/Shaders/NV12RGB.metal`, `MetalRGBBaselineTests`, and `benchmarks/results/m2-pipeline-b-quick.json`.

Revisit when: adding a resize/chroma-siting mode after the first A/B/C gate.

## D008 - Initial GPU parity acceptance threshold

Status: accepted

Decision: For the first Metal native stem, accept the supported BT.601 NV12 path only when the deterministic GPU feature output has max absolute error <= 1e-5 against the Double-precision reference over the tested pixels and channels. This is a correctness gate, not a performance tradeoff.

Why: Fused GPU arithmetic and Float output can differ from the reference's operation ordering, but the threshold remains tight enough to expose coefficient, plane-indexing, or systematic chroma errors. The threshold is recorded before Pipeline C benchmarking and must not be loosened to make a faster kernel pass.

Evidence: `MetalNativeStemTests.swift` enforces the threshold; the first fixture passed before the Sol review required a second UV-row case.

Revisit when: a new precision/backend path is introduced with a separately justified numerical contract.

## D009 - Proposed M5 model boundary

Status: accepted

Decision: Use the official Apple MobileNetV2 ImageNet workload for M5. Extend the native path to the model's 3x3 stride-2 convolution plus BatchNorm/ReLU6 stem, then hand off to the unchanged split model tail. Compare it with an optimized RGB path using the same tail and require activation/logit comparison plus at least 99.5% top-k/task agreement before making a real-model claim.

Why: MobileNetV2 is small enough for a fully local camera workload and has a concrete spatial learned stem that tests PlaneFuse's actual compiler/runtime premise. MobileCLIP is attractive for zero-shot UX, but its model-weight terms and export/splitting scope add deadline and licensing risk; it should be deferred unless explicitly approved.

Evidence: M5 Sol architecture review `019fe5b6-df0b-70e3-a55f-b7723d2beb7b`; Apple MobileNetV2 model gallery; Apple MobileCLIP repository and model-weight license review.

Revisit when: a later model/generalization milestone adds a different compatible stem or the MobileNetV2 export/tail boundary changes.

## D010 - Make the Core ML handoff boundary explicit

Status: accepted

Decision: M5's current Core ML tail handoff uses a CPU-visible Float32 `MLMultiArray` built from the native activation buffer. Include that adapter in end-to-end timing and do not describe the path as zero-copy into Core ML.

Why: The boundary is reproducible with the available macOS Core ML API and keeps B and C on the same unchanged tail. Hiding the bridge would overstate the current systems result; a later tensor/Metal handoff can be measured as a separate optimization.

Evidence: `Sources/PlaneFuseCore/MobileNetV2Integration.swift`, `Sources/PlaneFuseCore/MobileNetV2Benchmark.swift`, `proof/m5-mobilenetv2.md`.

Revisit when: a supported Core ML tensor or MPSGraph handoff can consume the native activation without changing the model tail.

## D011 - Separate CPU reference parity from deployed Metal parity

Status: accepted

Decision: Keep the deployed Pipeline B/C Float32 Metal activation threshold at `<=1e-5` (D008). Validate the source-derived StemArray against B/C using Core ML CPU-only execution with the existing reference-math threshold `<=1e-4`; require task agreement `>=0.995`. Record the backend and all three thresholds in every M5 artifact.

Why: Core ML accelerator execution selects lower-precision arithmetic for this asset, while CPU-only execution is the reproducible Float32 source-derived reference. The remaining CPU-vs-fused-Metal difference is accumulation/order behavior, not a changed model or color contract. This is a separate boundary contract and does not supersede or loosen D008.

Evidence: `benchmarks/results/m5-mobilenetv2-confirm1.json`, `benchmarks/results/m5-mobilenetv2-confirm2.json`, `BENCHMARK_CONTRACT.md`, and the independent advisor review recorded in the M5 audit handoff.

Revisit when: a direct tensor handoff or a controlled Float32 Core ML compilation path removes the backend-ordering difference.

## D012 - Close the bounded M6 shader-tuning family at the model boundary

Status: accepted

Decision: Retain the accepted 8x8 MobileNetV2 native stem. Do not claim an M6 optimization win from phase-aware UV prefetch or 16x4 threadgroups: both improved an isolated frontend sample but regressed the measured end-to-end boundary, and both were reverted.

Why: PlaneFuse's useful claim is about the complete model boundary, including the unchanged tail and explicit CPU-visible handoff. Isolated kernel movement is not sufficient evidence of application value. The next optimization opportunity must be a different, measured architectural boundary such as tensor handoff or a distinct workload.

Evidence: `EXPERIMENTS.md` E005-E007, `benchmarks/results/m6-exp0-baseline.json`, `benchmarks/results/m6-exp1-phase-aware.json`, and `benchmarks/results/m6-exp2-threadgroup-confirm.json`.

Revisit when: a supported no-copy tail handoff or a second real compatible workload is available for a new hypothesis family.

---

New decision template:

## Dxxx - Title

Status: proposed / accepted / superseded

Decision:

Why:

Evidence:

Revisit when:
