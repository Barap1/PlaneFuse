# Integration guide

PlaneFuse is a focused research prototype today. The bundled implementation
supports the inspected Apple MobileNetV2 configuration end to end. Its CLI and
compatibility rules describe the intended extension path without pretending
that arbitrary Core ML graphs are already supported.

## 1. Inspect a model

```bash
./pf inspect mobilenetv2
```

Inspection records the model input contract, first learned operator, activation
boundary, and source lineage. For a future model adapter, the same inspection
step must identify the camera representation and every preprocessing operation
before the first fusable learned operator.

## 2. Check compatibility

PlaneFuse needs a declared compatibility manifest. At minimum it describes:

- source format, such as NV12;
- YCbCr matrix, range, and transfer semantics;
- resize and crop rules;
- normalization constants;
- first-layer type, shape, stride, and padding;
- the activation tensor handed to the unchanged tail.

The current verified contract is represented by the MobileNetV2 derived
manifest in `models/derived/manifest.json` after setup. The stable public
compatibility rules are in [`MODEL_COMPATIBILITY.md`](MODEL_COMPATIBILITY.md).

## 3. Compile the transformed stem

```bash
./pf compile mobilenetv2
```

The compiler composes affine color conversion and normalization into the
pretrained first convolution. C1-SR then schedules the resulting source-plane
operator with small Y and UV tiles staged once and reused across output
channels.

## 4. Verify parity

```bash
./pf verify
./pf verify lineage
```

Verification checks transformed activations, predictions, top-5 behavior, and
source-model lineage. It does not apply the dashboard's presentation smoothing.

## 5. Benchmark matched paths

```bash
./pf bench quick
./pf reproduce final
```

The benchmark harness compares the strongest materialized-RGB B2 path with the
native-plane candidate at the same persistent activation and Core ML tail
boundary. Do not use a weaker baseline or a different timing boundary when
adding a model adapter.

## 6. Understand the camera boundary

The supported application path has one explicit conversion boundary:

```text
AVCaptureVideoDataOutput
        ↓
CVPixelBuffer (420v NV12)
        ↓  inspect YCbCr matrix/range metadata
CVMetalTextureCache
        ↓
Y + UV source textures
        ↓  reusable center-crop/nearest resize
224×224 r8Uint + rg8Uint NV12 textures
        ↓
PlaneFuse C1-SR stem
        ↓
persistent MTLBuffer activation → buffer-backed MLMultiArray
        ↓
unchanged Core ML MobileNetV2 tail → local result
```

NV12 uses an 8-bit luma plane and an interleaved, half-resolution chroma
plane. `CVMetalTextureCache` maps the camera planes without a CPU copy; the
application's resize bridge writes the exact integer textures expected by the
verified stem. The bridge must retain its `CVMetalTexture` wrappers until the
Metal command buffer completes.

## 7. Embed the runtime

The live application follows this conceptual shape:

```swift
let runtime = try PlaneFuseMobileNetV2Runtime(
    device: device,
    coefficientsURL: root.appendingPathComponent("models/derived/MobileNetV2StemCoefficients.json"),
    tailModelURL: root.appendingPathComponent("models/derived/tail-compiled/MobileNetV2Tail.mlmodelc"),
    semantics: .bt601VideoRange
)
let result = try runtime.predict(nv12Textures: resizedNV12)
print(result.topLabel ?? "no label")
```

Create `runtime` once. It compiles the native stem, loads the unchanged tail,
allocates the activation buffer, and creates the buffer-backed `MLMultiArray`
once. Call `predict` for each resized frame; it runs C1-SR and reuses those
resources. The compile-checked source is
[`Examples/PlaneFuseIntegration/README.swift`](../Examples/PlaneFuseIntegration/README.swift).

The current AppKit application adds the camera capture and resize bridge in
`Sources/PlaneFuseLive/CameraNV12MetalBridge.swift`. Run
`./scripts/check_integration_example.sh` to build PlaneFuseCore and type-check
the public example against the real API.

## Current boundary

Generic model inspection and compilation are an explicit extension surface, not
a promise that every model is accepted today. A contributor adding a model
should add a manifest, a parity fixture, a quality record, and a matched B2
comparison before calling it supported.
