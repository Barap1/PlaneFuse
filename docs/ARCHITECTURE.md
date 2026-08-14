# PlaneFuse architecture

![PlaneFuse system architecture](diagrams/planefuse-architecture.svg)

PlaneFuse compiles the compatible RGB input stem of a pretrained MobileNetV2
into the camera's native NV12 representation. The rest of the model remains an
ordinary Core ML tail. No retraining is involved.

## Conventional B2

B2 is the strongest credible conventional baseline in the final matched
matrix. Its RGB intermediate is 602,112 logical payload bytes and 606,208
Metal-allocated bytes for the 224×224 stem input.

## PlaneFuse C1-SR

C1-SR produces the same first activation from Y and UV without a full RGB
intermediate. The source-reuse schedule stages each input tile once and reuses
the source taps across output channels. The full RGB intermediate is therefore
0 B in the PlaneFuse path, while the persistent activation handoff and the
unchanged tail stay matched to B2.

## Analytical composition

The supported preprocessing and normalization are affine:

```text
r = A·s + c
x = D·(r − μ)
h = W·x + b

h = (W·D·A)·s + [b + W·D·(c − μ)]
```

For the spatial 3×3 stem, the compiler applies this composition per tap,
preserves the declared BT.601 video-range NV12 mapping, and handles padding
only for in-bounds source coordinates. The generated operator is a source-domain
version of the original pretrained stem, not a new trained model.

## Why source reuse matters

An earlier direct camera-space fusion attempt removed a resized NV12
intermediate but was slower than a fair source-space materialized-RGB baseline.
That result showed that eliminating an intermediate can also eliminate valuable
spatial and channel reuse. C1-SR solves the measured problem differently: it retains the
native-plane representation while restoring reuse in the execution schedule.

The final principle is selective representation elimination: remove a boundary
when the measured schedule benefits, and retain a representation when it creates
more useful reuse than its materialization costs. R5's polyphase compiler is
retained as a mathematically correct negative result rather than an unsupported
runtime speed claim.

## Runtime boundary

Both B2 and C1-SR write a persistent 48×112×112 Float32 activation and call the
same `.all` Core ML MobileNetV2 tail. PlaneFuse does not claim that Core ML makes
no hidden internal copy. The structural claim is narrower and measured: C1-SR
does not materialize full RGB, and PlaneFuse performs 0 B of element-by-element
CPU activation population on the compared path.

## Evidence map

The final numbers and protocol are generated in
[`RESULTS_AND_EVIDENCE.md`](RESULTS_AND_EVIDENCE.md). The implementation is in
`Sources/PlaneFuseCore/Shaders/NV12MobileNetV2Stem.metal` and
`Sources/PlaneFuseCore/R75SourceReuseBenchmark.swift`.
