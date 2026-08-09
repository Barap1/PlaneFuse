# PlaneFuse technical and product specification

## 1. Project identity

Name: PlaneFuse

Technical descriptor: Native-plane vision model compilation for Arm client devices.

Showcase application: PlaneFuse Live.

Target hackathon: Arm Create: AI Optimization Challenge 2026.

Selected track: Mobile AI.

Initial hardware/backend: Apple Silicon macOS using Core Video / Metal and a compatible local vision model.

## 2. Why this project exists

Modern Apple camera/video pipelines commonly deliver compact YUV formats such as NV12/4:2:0. Many pretrained vision models, however, are designed around RGB inputs.

A conventional inference path often performs work conceptually like:

```text
native camera/video frame (NV12)
  -> reconstruct/convert to RGB
  -> resize / normalize
  -> materialize RGB/tensor representation
  -> first learned model operation
  -> rest of model
```

That creates a systems question:

Can a compatible pretrained RGB model be transformed so its first learned representation is produced directly from the native Y and UV planes, avoiding the full RGB intermediate and reducing input-path work without retraining the model?

PlaneFuse investigates and productizes that question.

## 3. Core technical hypothesis

A useful portion of the vision input path is affine or linear before the first nonlinearity.

In simplified form:

```text
RGB = A * YUV + c
normalized = D * (RGB - mean)
features = W * normalized + b
```

For compatible operations, these transformations can be algebraically composed into transformed coefficients operating in the source representation.

The deeper opportunity is 4:2:0 chroma subsampling: the camera source does not contain three independent full-resolution color samples per pixel. A standard RGB path reconstructs/expands compact chroma information before the model immediately projects that representation again.

PlaneFuse should test whether the model stem can instead consume the actual source-plane geometry using fused/phase-aware Metal operations and transformed weights.

Important: the project must not claim that every color conversion, resize, clamp, transfer function, or model stem can be fully folded algebraically. Unsupported/nonlinear semantics may remain as operations inside a fused native-plane kernel. Correctness is more important than an elegant formula.

## 4. Technical contribution we are trying to establish

The desired contribution is called Native-Plane Stem Compilation (NPSC):

1. Inspect a compatible pretrained RGB model's input contract and first fusable learned operation.
2. Model the source camera format and supported color/range semantics.
3. Compile supported input transforms into a native Y/UV model stem.
4. Generate a Metal implementation that reads native planes directly.
5. Produce the same or acceptably equivalent first features/model outputs.
6. Avoid materializing a complete RGB intermediate.
7. Hand the generated activation/tensor into the remaining model path.
8. Verify equivalence and benchmark against both a normal baseline and a properly optimized RGB baseline.

The first backend is Apple Silicon. The broader design should make a future Android YUV or other Arm-client backend conceptually possible, but those are not MVP requirements.

## 5. What we are actually building

PlaneFuse has four deliverables.

### A. Reference/verification library

A deterministic reference implementation for:

- NV12/YUV sampling and color conversion;
- supported resize/normalization semantics;
- reference RGB stem;
- transformed/native-plane stem;
- intermediate activation comparison;
- final model output comparison.

### B. Native Apple-Silicon runtime

A Metal/Core Video path that:

- consumes native pixel-buffer planes;
- avoids a full RGB intermediate for Pipeline C;
- produces the model's first activation/tensor;
- integrates with the remaining model runtime;
- exposes timing/allocation evidence for benchmark tooling.

### C. Developer tool

By the later milestones, a small developer-facing interface should support concepts equivalent to:

```text
planefuse inspect <model>
planefuse compile <model>
planefuse verify <artifact>
planefuse bench <artifact>
```

Exact CLI syntax may evolve, but the reusable developer story matters for the hackathon's impact/DX criteria.

### D. PlaneFuse Live

A polished but focused macOS demo that runs vision inference fully locally and makes the optimization understandable.

Preferred experience:

- live camera or recorded-camera-frame input;
- semantic visual search / zero-shot classification if a suitable licensed model is practical;
- otherwise a meaningful real-time classification/recognition workload;
- switchable optimized-RGB and PlaneFuse paths;
- live or clearly labeled benchmark metrics;
- visible output agreement;
- clear `RGB intermediate: 0` evidence for the PlaneFuse path;
- entirely on-device inference.

A user should understand the value in under 15 seconds: the same useful local camera intelligence runs with less input-path work.

## 6. Why the project is meaningful

This is not an optimization for a synthetic matrix multiplication alone.

Camera intelligence is a real Mobile AI workload: accessibility, visual search, scanning, AR, robotics interfaces, privacy-sensitive recognition, and continuous perception all benefit from lower latency and reduced memory/bandwidth pressure.

A sensor-native input compiler could help especially when:

- the vision backbone is already highly optimized and preprocessing becomes a material fraction of latency;
- camera inference runs continuously and transient memory/bandwidth costs repeat every frame;
- image resolution is high;
- thermal/energy constraints matter;
- the application wants to preserve native capture formats rather than request an expanded BGRA/RGB buffer.

## 7. Hackathon fit

The Mobile AI track explicitly values local inference on Arm-powered client devices and constraints such as responsiveness, memory, battery awareness, offline use, and camera intelligence.

PlaneFuse must demonstrate optimization, not merely local execution.

Our strongest hackathon story is:

```text
Existing workload: pretrained local vision model on Apple Silicon.
Baseline: optimized native camera -> RGB -> model path.
Technical change: compile/fuse the model stem toward NV12 source planes.
Measured result: lower frontend/end-to-end cost with verified output parity.
Reusable output: compiler/runtime + benchmark harness + reproducible evidence.
Meaningful demo: local semantic camera.
```

## 8. MVP technical scope

Initial supported scope should be intentionally narrow and rigorous:

- Apple Silicon macOS;
- 8-bit bi-planar NV12/4:2:0 source;
- one explicitly documented color matrix/range path first, then add another only if time allows;
- one clearly supported resize/sampling mode;
- one compatible first-op family: Conv2D-style stem or ViT/patch-projection equivalent chosen after measurement;
- one real model for the first end-to-end result;
- second compatible model/stem only after the core optimization is proven.

Do not claim universal model compatibility.

## 9. Baseline architecture

### Pipeline A - reference/ordinary

A representative ordinary camera/video-to-model path.

Purpose: demonstrate the real starting workflow and user impact.

### Pipeline B - optimized RGB

A fair optimized implementation that still materializes the RGB/model-input representation.

Conceptually:

```text
NV12 -> efficient Metal conversion/resize/normalization -> RGB/model tensor -> normal stem
```

Purpose: prevent a strawman benchmark.

### Pipeline C - PlaneFuse

Conceptually:

```text
Y plane + UV plane -> native-plane generated/fused stem -> first model activation -> model tail
```

Purpose: prove the proposed technique.

Pipeline C must beat B for the strongest claims.

## 10. Correctness requirements

Performance is rejected if correctness is not established.

The project should validate at multiple levels:

1. source conversion/reference tests;
2. first-layer/first-activation parity;
3. embedding/logit/output similarity;
4. task-level agreement on a validation corpus;
5. live-demo behavior.

Thresholds are specified in `BENCHMARK_CONTRACT.md` and may only be changed for defensible numerical reasons documented in `DECISIONS.md`. Never loosen a threshold solely because a fast implementation failed it.

## 11. Performance metrics

Primary metrics:

- frontend/stem p50 latency;
- frontend/stem p95 latency;
- end-to-end p50/p95 latency;
- sustained FPS for the showcase workload.

Strong supporting metrics where reliably measurable:

- transient allocation/peak memory;
- GPU memory bandwidth/counters;
- bytes moved/allocated based on measured instrumentation;
- energy/frame or sustained power only if a reliable repeatable measurement method is available;
- output quality/agreement.

Do not infer energy savings from latency alone.

## 12. Success ladder

### Minimum technically valid result

- Pipeline C is correct;
- no full RGB intermediate in C;
- reproducible benchmark harness;
- at least one real model runs end to end;
- measurable frontend benefit.

This is not necessarily a winning result.

### Strong submission

- C beats optimized B by a clearly meaningful amount;
- result is repeated and statistically stable;
- one real fast on-device model demonstrates user impact;
- profiler/allocation evidence explains why;
- developer tooling makes the technique reusable;
- excellent README and proof bundle.

### Winning-target result

Aim for at least one headline metric that is instantly understandable, for example:

- >=10% end-to-end latency reduction over optimized B; or
- >=2x frontend/stem speedup plus a material memory/bandwidth reduction that translates into real application value;
- near-equivalent task quality/output agreement;
- real-time PlaneFuse Live demo;
- reproducible on a clean Apple-Silicon environment;
- evidence strong enough that a skeptical systems engineer can audit the claim.

These are internal goals, not promised outcomes.

## 13. Kill/pivot gate

At M4, after a serious optimized baseline and bounded native-plane implementation effort:

If PlaneFuse cannot produce a meaningful advantage over Pipeline B, stop feature work.

Required response:

1. summarize what was measured;
2. identify where time/bandwidth is actually going;
3. list the strongest failed hypotheses;
4. perform a focused Sol Advisor architecture review;
5. propose the nearest evidence-based adjustment that preserves the sensor-native/Arm-client insight;
6. request human approval before a major pivot.

Do not keep polishing a 1-2% noisy improvement.

## 14. Non-goals before M4 passes

Do not spend significant time on:

- elaborate SwiftUI styling;
- iPhone deployment/signing;
- a multi-platform abstraction layer;
- generalized graph compiler infrastructure;
- ANE integration;
- cloud services;
- LLM features;
- a full model zoo;
- speculative power claims;
- branding/marketing polish.

## 15. Preferred model-selection strategy

Do not hard-code a model before measuring stem structure and licensing.

Candidate selection should prioritize:

- permissive/usable licensing;
- genuinely fast on-device inference;
- meaningful camera use case;
- a first stem compatible with the technique;
- clear ability to validate output parity;
- manageable build integration.

MobileCLIP is a strong candidate for the semantic-camera showcase, but it is not sacred. If another model produces a cleaner, more defensible result, use it and document why.

## 16. Final submission artifacts

Expected end-state repository includes:

- source code;
- MIT license;
- reproducible setup;
- benchmark harness;
- benchmark JSON/CSV results;
- system metadata;
- parity/quality report;
- profiler screenshots/captures where practical;
- architecture diagram;
- PlaneFuse Live screenshots/video;
- clear README with measured before/after table;
- Devpost-ready write-up and under-3-minute demo script.

No claim goes into the README or Devpost unless it appears in `CLAIMS.md` with evidence.

<!-- PLANEFUSE_PHASE2_SPEC_POINTER -->
## Active post-M11 continuation

For repository hardening and frontier research after the original M11 snapshot, read `SPEC_V2_ADDENDUM.md`, `RESEARCH_FRONTIER.md`, `MILESTONES_V2.md`, and `BENCHMARK_CONTRACT_V2.md`. These documents extend the project; they do not invalidate previously accepted evidence.
