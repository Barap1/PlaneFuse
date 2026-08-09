# PlaneFuse research-paper outline

Working title:

**PlaneFuse: Sensor-Native Graph Re-authoring for Pretrained Vision Models on Unified-Memory Arm Clients**

Alternative title:

**From Camera Planes to Logits: No-Retrain Native-Grid Compilation on Apple Silicon**

This is an internal research structure, not a claim that a paper has been peer reviewed.

## Abstract skeleton

Camera and video pipelines commonly produce YUV 4:2:0 data, while pretrained vision models consume dense RGB tensors. Conventional deployment reconstructs a full RGB representation, normalizes it, and applies the first learned operator. PlaneFuse compiles affine color processing, normalization, BatchNorm, and the first learned convolution into a native-plane operator without retraining. It then investigates shared-memory and accelerator-resident handoffs that keep the first activation on the device through the unchanged model tail. On Apple Silicon, evaluate latency, memory representation, quality agreement, and live camera throughput against ordinary and aggressively optimized RGB baselines.

Do not fill the result sentence until R7.

## Research questions

### RQ1 — Exactness

Can a declared class of pretrained RGB stems be transformed into native YUV 4:2:0 operators without retraining while preserving model outputs?

### RQ2 — Representation cost

How much latency, allocation, and memory traffic comes from materializing RGB before the first learned operator?

### RQ3 — Boundary cost

How much of end-to-end inference is attributable to transferring the first activation from a custom Metal kernel into the model runtime?

### RQ4 — Source-grid compilation

Can a polyphase compiler exploit the true 4:2:0 grid to reduce redundant chroma reads/arithmetic beyond ordinary kernel fusion?

### RQ5 — Systems integration

Can a camera frame remain in native-plane/shared accelerator storage through the transformed stem and unchanged tail?

## Proposed contributions

Use only contributions that are implemented and validated.

1. **No-retrain source-domain stem compiler.** Algebraically composes source-to-RGB conversion, normalization, learned convolution, BatchNorm, and activation for an explicitly supported stem family.
2. **Polyphase 4:2:0 operator compilation.** Aggregates chroma contributions on the physical UV lattice rather than reconstructing per-pixel RGB values.
3. **PlaneFuse Continuum execution path.** Removes CPU element-copy/boxing and, if feasible, executes the stem and tail through shared tensors or one GPU timeline.
4. **Fair Apple-Silicon evaluation harness.** Includes ordinary, strong conventional, and native-plane baselines; source-model lineage checks; paired statistics; resource evidence; and a live camera workload.
5. **Reusable compatibility contract and tooling.** Rejects unsupported graph/color semantics explicitly rather than silently changing model meaning.

## Theorem-style statement for the affine prefix

Given an affine source conversion `r = A s + c`, channel normalization `x = D(r - mu)`, and a linear operator `h = W x + b`, the composed source-domain operator is:

```text
W_s = W D A
b_s = b + W D(c - mu)
```

For convolution, this is applied per spatial tap. A following pointwise nonlinearity is unchanged.

The exactness claim is conditioned on:

- declared source range/matrix;
- declared chroma sampling/reconstruction;
- declared resize and padding;
- no unmodeled nonlinear preprocessing before the learned operator;
- comparable numerical precision.

## Polyphase derivation outline

1. Define full-resolution luma lattice `Y[i,j]` and half-resolution chroma lattice `C[p,q]`.
2. Define mapping `phi(i,j)` from each reconstructed RGB sample position to one or more physical chroma samples.
3. Expand the RGB-domain convolution into Y, Cb, and Cr coefficients.
4. Group all chroma terms by unique physical coordinate and output phase.
5. Emit phase-specific native-grid kernels.
6. Prove equivalence to the declared reconstruction operator.
7. Count unique source reads and multiply-adds.
8. Verify numerically on exhaustive small-grid and randomized tests.

## Evaluation matrix

### Models

- Apple MobileNetV2 ImageNet — primary controlled real model.
- Optional second compatible real model only after the complete systems path works.
- Parameterized reference fixtures for exhaustive semantics testing.

### Pipelines

- A standard Core ML image input.
- B1 RGBA32Float materialized baseline.
- B2 strongest compact conventional RGB baseline.
- C0 current native stem + boxed bridge.
- C1 buffer-backed multiarray.
- C2 IOSurface Float16.
- C3 Metal 4 GPU-timeline.
- C4 polyphase strongest path.

### Metrics

- frontend, bridge, tail, and end-to-end p50/p95/mean/MAD;
- paired confidence interval;
- capture-to-result and sustained FPS;
- logical and allocated bytes;
- CPU bytes copied;
- GPU durations and trace evidence;
- activation max/mean error and cosine similarity;
- top-1/top-5 and probability-vector agreement.

## Required ablations

- with/without RGB materialization;
- boxed versus shared multiarray bridge;
- Float32 versus accepted Float16 shared path;
- ordinary versus polyphase chroma evaluation;
- CPU-mediated Core ML versus Metal 4 GPU timeline, if feasible;
- CPU camera plane copy versus CVMetalTextureCache input;
- first-run versus warmed steady state.

## Threats to validity

- one Apple device/chip;
- one primary pretrained model;
- small or non-labeled equivalence corpus;
- Core ML scheduling/compute-unit opacity;
- different arithmetic ordering and precision;
- camera chroma-siting assumptions;
- beta API availability for optional work;
- benchmark noise at sub-millisecond frontend times.

## Prior-art framing

Discuss adjacent categories honestly:

- sensor-domain and learned camera processing;
- direct YUV/4:2:0 learned codecs;
- compressed-domain inference;
- sparse temporal video inference;
- operator/kernel fusion;
- ML accelerator/runtime integration.

The novelty statement should be narrow:

> PlaneFuse combines no-retrain source-domain compilation of a pretrained RGB stem, explicit 4:2:0 native-grid operator generation, and Apple-Silicon shared/timeline execution in one reproducible camera-to-model system.

Do not use “first” unless a much broader literature search and legal review support it.
