# PlaneFuse research frontier

Last researched: 2026-08-09

Purpose: identify the highest-leverage next experiments without confusing ambition with evidence.

## Executive conclusion

The strongest next move is **not another local Metal micro-optimization**.

The current code already makes the native stem fast. Its main end-to-end bottleneck is the boundary after that stem: the activation is read into a Swift array, copied element by element through `NSNumber`, placed into a new `MLMultiArray`, and then passed to the Core ML tail.

Phase 2 should therefore pursue a ladder of progressively deeper boundary elimination:

```text
current boxed bridge
    -> persistent buffer-backed MLMultiArray
    -> IOSurface-backed Float16 multiarray
    -> Metal 4 MTLTensor + ML command encoder
    -> optional Core AI integrated custom-op model
```

In parallel, the source-domain compiler should become more novel through **polyphase 4:2:0 operator compilation**, not just UV prefetching.

## Ranked opportunity 1 — persistent buffer-backed MLMultiArray

### Why it matters

The current tail adapter allocates a new Float32 multiarray and assigns approximately 602,112 activation values through boxed `NSNumber` values for every prediction.

Core ML provides an initializer that constructs an `MLMultiArray` from an existing data pointer, explicit shape, type, and strides. A shared-storage `MTLBuffer` exposes CPU-visible memory through `contents()` when using shared storage.

The experiment should create the multiarray once over a retained activation buffer and reuse it after GPU completion. This removes:

- the temporary `[Float]` allocation;
- activation-buffer readback into a new Swift array;
- the per-element `NSNumber` loop;
- repeated multiarray allocation.

### Why this is first

- works on the current stable OS/toolchain;
- small implementation surface;
- directly attacks a visibly expensive path;
- easy to benchmark and revert;
- keeps the same Core ML tail.

### Risks

- Core ML may still perform an internal copy;
- synchronization and lifetime must be correct;
- strides must exactly match `[48, 112, 112]` CHW storage;
- B and C need separate persistent wrappers over their own buffers.

### Primary source

- Apple `MLMultiArray.init(dataPointer:shape:dataType:strides:deallocator:)`: https://developer.apple.com/documentation/coreml/mlmultiarray/init%28datapointer%3Ashape%3Adatatype%3Astrides%3Adeallocator%3A%29

## Ranked opportunity 2 — IOSurface-backed Float16 activation bridge

### Why it matters

Apple documents an `MLMultiArray(pixelBuffer:shape:)` initializer for an IOSurface-backed one-component Float16 pixel buffer and explicitly states that it can reduce inference latency by avoiding buffer copies to and from some compute units.

A research implementation can flatten the `48 x 112 x 112` activation into a `112 x 5376` one-component half-float surface while preserving the logical shape supplied to Core ML.

Both B and C would write to identical Float16 activation surfaces, and both would use a tail whose input contract is explicitly Float16.

### Potential advantages

- shared IOSurface between Metal and Core ML;
- half the activation payload;
- fewer CPU-visible transfers;
- potentially better accelerator compatibility.

### Risks

- changes precision and therefore needs a predeclared quality contract;
- Core ML tail input must be derived and independently validated at Float16;
- the physical layout must match the multiarray's shape and strides;
- the resulting speedup is not guaranteed.

### Primary source

- Apple `MLMultiArray.init(pixelBuffer:shape:)`: https://developer.apple.com/documentation/coreml/mlmultiarray/init%28pixelbuffer%3Ashape%3A%29

## Ranked opportunity 3 — Metal 4 GPU-timeline tail

### Why it matters

Metal 4 introduced:

- `MTLTensor`, including tensors that wrap existing `MTLBuffer` storage;
- `MTL4MachineLearningCommandEncoder` for running complete models on the GPU timeline;
- `metal-package-builder`, which converts a supported Core ML package into an `MTLPackage`;
- synchronization between compute and ML passes in Metal command buffers.

This enables the target architecture:

```text
Y/UV compute encoder
    -> MTLTensor activation
    -> ML command encoder for tail
    -> output tensor
```

without returning the first activation to the CPU.

### Why it is high value

This is the most direct way to make PlaneFuse a complete accelerator-resident system rather than a fast custom frontend attached to a CPU-mediated model call.

### Feasibility questions that must be answered before implementation

1. Is `metal-package-builder` present in Xcode 26.6?
2. Can the current derived tail be represented as a supported ML Program?
3. Can the source model be recreated as an equivalent ML Program without weakening provenance?
4. What tensor layout does the generated package require?
5. Can the native stem's activation buffer be wrapped directly as the required `MTLTensor`?
6. Can B2 and C use the exact same MTLPackage tail?

### Important constraint

Apple's WWDC25 material says the Metal package workflow supports ML Program packages. The existing Apple MobileNetV2 asset is an older neural-network Core ML model. Conversion feasibility must be demonstrated, not assumed.

### Primary sources

- WWDC25, “Combine machine learning and Metal 4 graphics”: https://developer.apple.com/videos/play/wwdc2025/262/
- Apple `MTLTensor`: https://developer.apple.com/documentation/metal/mtltensor
- Apple `MTL4MachineLearningPipelineState`: https://developer.apple.com/documentation/metal/mtl4machinelearningpipelinestate

## Ranked opportunity 4 — polyphase 4:2:0 source-grid compiler

### Current behavior

The MobileNetV2 native kernel evaluates a 3x3 RGB-domain convolution directly from source planes. Under the current nearest-sited NV12 contract, multiple luma taps address the same physical UV sample. The kernel still performs chroma arithmetic per RGB-domain tap.

### Proposed contribution

Generate a phase-specific source-grid operator:

```text
RGB-domain 3x3 convolution
  + YUV conversion
  + normalization
  + chroma sample mapping
  + BatchNorm
        ↓ compile
native Y-grid coefficients
  + unique UV-grid coefficients
  + exact offsets
```

For each output phase, chroma coefficients that reference the same UV location are summed at compile time. Runtime evaluates the unique UV values rather than emulating nine reconstructed RGB samples.

For a future bilinear mode, the compiler precomposes the linear chroma reconstruction matrix with the learned convolution, yielding phase-specific native-grid kernels.

### Why this is more novel than UV prefetch

Prefetching changes only memory access. Polyphase compilation changes the mathematical operator and reduces redundant source-domain arithmetic while preserving the pretrained model.

### Prior-art position

Related research exists in sensor-domain networks, YUV-aware learned codecs, and direct camera processing. Search did not identify a primary source demonstrating this exact combination:

- no-retraining conversion of an existing RGB pretrained stem;
- explicit 4:2:0 polyphase coefficient compilation;
- native Apple camera planes;
- accelerator-resident continuation into the unchanged model tail.

Do not claim world-first. Claim the exact implemented combination and provide the prior-art review.

### Related primary research

- “Learning Sensor Multiplexing Design through Back-propagation”: https://arxiv.org/abs/1605.07078
- “Deep Camera: A Fully Convolutional Neural Network for Image Signal Processing”: https://openaccess.thecvf.com/content_ICCVW_2019/html/LCI/Ratnasingam_Deep_Camera_A_Fully_Convolutional_Neural_Network_for_Image_Signal_ICCVW_2019_paper.html
- YUV 4:2:0 learned video-coding work: https://arxiv.org/abs/2212.14187

### R5 result and claim boundary

The R5 implementation now instantiates the nearest-sited mode described above:
the compiler preserves nine full-resolution luma taps and per-tap padding offsets,
while aggregating the repeated chroma contributions into four UV phases. The
independent Double reference and the generated Metal path agree across procedural
chroma-phase and edge cases. Three 200-pair confirmation batches on the accepted
Float32 shared bridge did not establish a latency improvement: end-to-end p50
differences were +0.23%, -0.64%, and +0.39% for polyphase relative to the native
stem. The reduction from nine to four UV read instructions and from 27 to 17
weighted multiplications is therefore recorded as compiler evidence, not as a
runtime speed claim. R5 is a rigorous documented negative for the current
MobileNetV2 boundary; future work must measure a different workload or execution
boundary before presenting this transformation as a performance win.

## Ranked opportunity 5 — direct camera textures and GPU resize

The current camera demo locks the `CVPixelBuffer`, copies both planes into Swift arrays, and performs a CPU nearest-neighbor resize.

Core Video's Metal texture cache can map each camera plane to a live Metal texture backed by the existing image buffer. Apple documents mappings for 420v luma to `R8Unorm` and chroma to `RG8Unorm`.

The improved camera path should:

1. retain the camera `CVPixelBuffer` until GPU completion;
2. use `CVMetalTextureCacheCreateTextureFromImage` for Y and UV;
3. crop/resize on GPU in native planes;
4. feed those output planes directly to B2 and C;
5. use a frame ring rather than per-frame allocation;
6. measure capture-to-result and sustained throughput.

Primary source:

- Apple `CVMetalTextureCacheCreateTextureFromImage`: https://developer.apple.com/documentation/corevideo/cvmetaltexturecachecreatetexturefromimage

## Ranked opportunity 6 — Core AI integrated model asset (optional moonshot)

Core AI, introduced at WWDC26, supports:

- `.aimodel` assets;
- `NDArray` views over existing Metal buffers and IOSurfaces;
- inference functions and compute streams;
- custom Metal kernels bundled into the model;
- model re-authoring around target-specific layouts and interfaces.

The ultimate PlaneFuse artifact could expose native Y and UV inputs and embed the source-domain stem as a custom Metal operation inside the model asset.

That would turn PlaneFuse from “custom preprocessing plus model tail” into **one sensor-native model artifact**.

However:

- Core AI is beta;
- Core AI Debugger requires macOS 27;
- Xcode 27/macOS 27 installation is a human-controlled system change;
- the stable submission must not depend on it.

Primary sources:

- Core AI overview: https://developer.apple.com/documentation/coreai
- WWDC26 model authoring/custom Metal kernels: https://developer.apple.com/videos/play/wwdc2026/325/
- `NDArray.RawView` over Metal buffers and IOSurfaces: https://developer.apple.com/documentation/coreai/ndarray/rawview
- Core AI Debugger requirements: https://developer.apple.com/core-ai-debugger/

## Ranked opportunity 7 — M5 neural-accelerator TensorOps

Apple's WWDC26 Metal Tensor material describes TensorOps that can use neural accelerators in M5/A19-family GPUs for matrix multiplication, convolution, quantized formats, and custom Core AI operations.

This is technologically exciting but currently lower priority because the accepted native stem is only a fraction of a millisecond. Optimizing it further cannot create a large end-to-end gain while the bridge/tail dominates.

Investigate only after the execution boundary is fixed and profiling shows the stem is again material.

Primary source:

- WWDC26, “Optimize custom machine learning operations with Metal tensors”: https://developer.apple.com/videos/play/wwdc2026/330/

## Deferred directions

### Temporal sparse inference

DeltaCNN and MotionDeltaCNN show large video-inference speedups by propagating sparse frame differences, including up to 7x in the original DeltaCNN work. This is powerful prior art but would broaden PlaneFuse into a separate video-inference framework.

It should be cited as future work, not added under the current deadline.

- DeltaCNN: https://openaccess.thecvf.com/content/CVPR2022/html/Parger_DeltaCNN_End-to-End_CNN_Inference_of_Sparse_Frame_Differences_in_Videos_CVPR_2022_paper.html
- MotionDeltaCNN: https://openaccess.thecvf.com/content/ICCV2023/html/Parger_MotionDeltaCNN_Sparse_CNN_Inference_of_Frame_Differences_in_Moving_Camera_Videos_with_Spherical_Buffers_ICCV_2023_paper.html

### Model switching before systems work

Moving to MobileCLIP or a larger model before fixing the current bridge would add model complexity without solving the central systems bottleneck. Keep MobileNetV2 as the controlled research vehicle until the continuum path is measured.

## Research claim discipline

The final contribution should be described as:

> A no-retraining sensor-native graph transformation and execution system for a declared family of pretrained vision stems, evaluated on Apple Silicon with native NV12 camera planes.

Do not describe it as:

- a universal compiler;
- a world-first system;
- a zero-copy system unless every relevant boundary is actually shared;
- an energy optimization without measurements;
- a generic MobileNet speedup independent of the tested pipeline.
