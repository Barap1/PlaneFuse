# Model compatibility

PlaneFuse compiles a narrow class of input pipelines. The current end-to-end
verified model is Apple MobileNetV2 ImageNet.

## Verified today

| Model | Input contract | First fusable operator | Status |
| --- | --- | --- | --- |
| Apple MobileNetV2 ImageNet | 224x224 normalized RGB, derived from NV12 BT.601 video range | 3x3 Conv2D, stride 2, 48 output channels, bottom/right SAME padding | Verified end to end |

The unchanged tail consumes a persistent `48 x 112 x 112` Float32 activation.
The reviewed R7.5 quality record covers 64 fixed inputs and reports top-1,
top-5 set, and top-5 rank agreement of 1.0 for C1-SR.

## Required compatibility properties

A future model can be considered for compilation when:

1. the source representation and its color/range semantics are known;
2. resize, crop, and normalization are deterministic and either affine or
   explicitly representable in the generated kernel;
3. the first learned operation is compatible with source-domain composition;
4. padding, stride, channel layout, and activation shape are explicit;
5. the remaining tail can accept the transformed activation without retraining;
6. an independent reference path and a strong materialized-RGB baseline exist.

## Unsupported or unverified today

The current prototype does not claim support for:

- nonlinear or unknown preprocessing before the first learned operation;
- dynamic resize or crop semantics that are not compiled into the plan;
- unknown camera matrix, range, or transfer-function behavior;
- arbitrary graph surgery or unsupported first operators;
- models without a stable activation handoff to an unchanged tail;
- iOS, Android, or non-Apple-Silicon performance results.

The source-reuse scaling graph is a stem microbenchmark, not evidence that
these unsupported models or platforms will benefit.

## Porting checklist

Use this checklist before adding another adapter:

```text
[ ] Camera/input representation is known
[ ] YCbCr matrix, range, and transfer semantics are known
[ ] Resize and crop behavior is deterministic
[ ] Normalization is known
[ ] First learned operation is supported and linear before activation
[ ] Padding, stride, and channel layout are explicit
[ ] Output activation shape is known
[ ] The unchanged tail accepts the compiled activation
[ ] A reference path exists for numerical parity
[ ] A strong matched RGB baseline exists
[ ] Quality and performance are measured on a fixed corpus
```

## Extension path

Add a compatibility manifest, implement the transform in the reference math,
generate the native stem, and add parity tests against the original model. Then
run the quality contract on a fixed corpus, establish the strongest matched B2
baseline, and record both accepted and rejected outcomes. A model is not
supported merely because its graph can be edited.
