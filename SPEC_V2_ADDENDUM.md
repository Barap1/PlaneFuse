# PlaneFuse Phase 2 specification addendum

Status: active continuation after the original M11 release-candidate snapshot

Working research name: **PlaneFuse Continuum**

Tagline: **Compile the camera representation into the model, then keep the result on the accelerator all the way to the answer.**

This addendum preserves the original PlaneFuse objective and extends it. It does not invalidate the accepted M1-M5 evidence.

## 1. Why Phase 2 exists

PlaneFuse has already demonstrated the first half of the idea:

```text
native NV12 Y + UV
    -> transformed pretrained MobileNetV2 stem
    -> first activation
```

without materializing a full RGB intermediate.

The present implementation then breaks the accelerator-resident path:

```text
Metal activation buffer
    -> CPU-visible Float array
    -> hundreds of thousands of NSNumber assignments
    -> new MLMultiArray
    -> Core ML tail
```

The current real-model frontend improves substantially, but the bridge and tail dominate the roughly 51 ms end-to-end path. Phase 2 treats this representation and execution boundary as the next systems problem.

## 2. Expanded objective

PlaneFuse Continuum should optimize three boundaries, in order:

1. **Representation boundary** — avoid expanding native camera planes into full RGB.
2. **Memory boundary** — avoid copying the first activation through CPU-owned arrays and boxed values.
3. **Execution boundary** — when supported, encode the native stem and model tail on one accelerator timeline without a CPU round trip.

The ideal final path is:

```text
camera CVPixelBuffer / IOSurface
    -> live Y and UV Metal textures
    -> source-domain pretrained stem
    -> shared activation tensor
    -> accelerator-resident model tail
    -> output
```

No retraining is required for the exact compilation path.

## 3. Formal transformation

Let the camera source vector be `s`, the affine source-to-RGB transform be:

```text
r = A s + c
```

Let model normalization be:

```text
x = D(r - mu)
```

and the first learned linear operator be:

```text
h = W x + b
```

Before the first nonlinearity, these compose exactly:

```text
h = W D A s + [b + W D(c - mu)]
```

PlaneFuse compiles those terms into source-domain weights and offsets.

For a spatial convolution, this composition is applied per kernel tap. Padding offsets are applied only to in-bounds source samples so the result preserves the original RGB model semantics.

## 4. Polyphase 4:2:0 extension

NV12 stores luma at full resolution and interleaved chroma at half resolution in each spatial dimension. Several luma taps in a convolution therefore reference the same physical UV sample.

The Phase 2 compiler should derive **polyphase source-grid kernels**. For each output phase and convolution tap mapping:

1. map each RGB-domain sample to its luma coordinate and physical chroma coordinate;
2. aggregate all chroma coefficients that address the same UV sample;
3. generate phase-specific source-domain weights;
4. evaluate only the unique source samples required by that phase.

For the current nearest-sited 3x3/stride-2 contract, the result should be algebraically equivalent to the existing kernel while reducing redundant UV reads and chroma multiply-adds. A later bilinear/chroma-sited mode may precompose the interpolation operator into phase-specific coefficients.

This is not merely caching UV values. The compiler changes the operator representation from reconstructed-pixel convolution to native-grid convolution.

## 5. Mandatory supported path on the current machine

The mandatory path must work with the user's existing stable environment:

```text
macOS 26.6
Xcode 26.6
Apple M5 Pro
```

Mandatory experiments, in order:

1. reuse a persistent `MLMultiArray` backed by the existing shared `MTLBuffer` memory using the documented data-pointer initializer;
2. test an IOSurface-backed Float16 `MLMultiArray` and Metal texture when the tail input can be derived fairly at Float16;
3. test Metal 4 `MTLTensor` plus `MTL4MachineLearningCommandEncoder` if the tail can be exported to a supported ML Program / MTLPackage without changing the model semantics.

Each B/C pair must use the same tail implementation and bridge class.

## 6. Optional Core AI research branch

Core AI offers the cleanest conceptual end state: `NDArray` views can wrap Metal buffers or IOSurfaces, inference can be encoded on a compute stream, and custom Metal kernels can be bundled inside an `.aimodel`.

However, Core AI is beta technology associated with the macOS 27/Xcode 27 toolchain. It is not a mandatory dependency.

Codex must stop and ask before:

- installing Xcode 27 beta;
- installing macOS 27 beta;
- changing the active Xcode globally;
- making the release depend on beta-only runtime APIs.

A Core AI branch may be created only after the stable-toolchain path is secure and the human explicitly approves it.

## 7. Baseline taxonomy

The final evaluation should distinguish:

- **A** — representative ordinary Apple/Core ML image-input workflow.
- **B1** — current optimized materialized `RGBA32Float` path.
- **B2** — strongest reasonable compact conventional RGB path, such as a fair Float16/IOSurface or equivalent implementation.
- **C0** — current PlaneFuse native stem plus boxed CPU/MLMultiArray bridge.
- **C1** — native stem plus buffer-backed persistent `MLMultiArray` bridge.
- **C2** — native stem plus IOSurface/Float16 shared bridge, if accepted.
- **C3** — native stem plus Metal 4 GPU-timeline tail, if feasible.
- **C4** — accepted polyphase source-grid version of the strongest C path.

A public speed claim must compare the strongest accepted C path against the strongest credible B path at the same precision and tail boundary.

## 8. Competition-worthiness targets

These are research targets, not facts.

The final entry should meet at least one of the following with quality preserved and a positive paired confidence interval:

1. at least 10% lower end-to-end p50 than B2;
2. at least 20% higher sustained camera throughput or materially lower capture-to-result latency;
3. at least 2x frontend improvement, zero full-RGB intermediate, zero element-by-element CPU tensor copy, and at least 5% end-to-end improvement;
4. an equally strong measured result approved by an independent hostile review.

If none is achieved after the bounded research program, Codex must stop for a human decision before claiming a winning result.

## 9. Correctness requirements

Do not weaken existing thresholds.

Minimum final evidence:

- deployed B/C activation error at or below the established GPU threshold, unless a separately approved precision path has its own predeclared contract;
- source-derived reference parity under its declared backend-specific threshold;
- top-1 and top-5 agreement on a substantially expanded corpus;
- probability-vector difference metrics;
- direct original Apple image-input model versus derived FullArray task agreement;
- explicit color range, matrix, chroma siting, resize, padding, precision, and layout contracts.

## 10. Product requirement

The final demo must be a continuous local camera experience, not only a benchmark CLI.

It should show:

- live camera preview;
- B2 versus strongest C selection or side-by-side comparison;
- actual top predictions and confidence;
- measured capture-to-result and model latency;
- RGB intermediate bytes;
- CPU tensor-copy bytes or a clear zero-copy/shared-memory indicator;
- parity/quality status;
- a simple visual dataflow.

Any stored benchmark displayed in the UI must be labeled as stored evidence. Live values must be measured live.

## 11. Non-goals

Phase 2 must not become:

- an unrelated model-quantization project;
- a MobileCLIP migration before the MobileNetV2 systems path is complete;
- a claim that all vision models are supported;
- a beta-OS dependency hidden from the user;
- random shader tuning without profiler evidence;
- a world-first claim without a defensible prior-art review.
