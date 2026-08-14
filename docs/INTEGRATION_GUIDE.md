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

## 6. Embed the runtime

The live application follows this conceptual shape:

```swift
let capture = try LiveCameraCapture()
let runner = try CameraInferenceRunner(semantics: capture.colorSemantics)
let result = try runner.inferC1SourceReuse(input: frame, ...)
```

The reusable pieces are the source-plane bridge, native stem, buffer-backed
activation handoff, and Core ML tail adapter. The current application wires
those pieces to an AppKit camera dashboard and reports live values separately
from stored benchmark evidence.

## Current boundary

Generic model inspection and compilation are an explicit extension surface, not
a promise that every model is accepted today. A contributor adding a model
should add a manifest, a parity fixture, a quality record, and a matched B2
comparison before calling it supported.
