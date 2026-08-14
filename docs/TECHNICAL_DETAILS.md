# Technical details

PlaneFuse targets the first learned operator of a compatible RGB vision model.
The model tail stays in Core ML and the benchmark boundary includes the same
persistent Float32 activation handoff for the compared paths.

## Affine composition

For one source sample `s`, the declared camera conversion and normalization can
be written as:

```text
r = A s + c
x = D(r - μ)
h = W x + b
```

The first learned operation is linear before its activation, so the affine
parts can be composed into the stem:

```text
W_native = W D A
b_native = b + W D(c - μ)
```

The compiler applies this composition per spatial tap. NV12 chroma has one
sample for each 2x2 luma block, so the spatial mapping is explicit rather than
treated as a third full-resolution channel. Padding coordinates are handled at
the source boundary and the shader preserves the declared BT.601 video-range
contract used by the benchmark corpus.

### Chroma-siting contract

B2, C1, and C1-SR use the same NV12 chroma-siting rule: each full-resolution
source coordinate reads the corresponding half-resolution UV sample at
`(x / 2, y / 2)`. B2 performs the lookup directly; C1 and C1-SR use the same
mapping through their native-plane and staged-tile paths. PlaneFuse changes
where the arithmetic and reuse occur, not which source chroma samples are used.

## C1 and C1-SR

C1 reads the native Y and UV planes and writes the first 48-channel activation
without allocating a normalized RGB texture. C1-SR uses the same mathematical
operator with a different execution schedule. It stages the exact source tile
needed by a 4x4 output tile, including the 9x9 luma and 5x5 chroma footprints,
then reuses those source values across output-channel groups in threadgroup
memory.

This distinction matters because an earlier direct camera-space fusion attempt
showed that removing an intermediate can also remove useful reuse. C1-SR
restores reuse at the source-plane boundary.
The focused schedule is shown in [`source-reuse.svg`](diagrams/source-reuse.svg).

## Runtime bridge

Both B2 and C1-SR retain a 48x112x112 Float32 activation buffer and pass it to
the same Core ML MobileNetV2 tail through a buffer-backed `MLMultiArray` view.
PlaneFuse measures no element-by-element CPU population of that activation. It
does not infer that Core ML performs no internal copy beyond the measured
adapter boundary.

The camera path uses `CVMetalTextureCache` to expose the two CVPixelBuffer
planes as Metal textures. A center crop is resized on Metal before live B2 and
C1-SR inference. The application reports the observed YCbCr matrix, color
primaries, and transfer-function attachments when a physical frame is
available. The benchmark's BT.601 video-range contract is not changed by live
metadata. When the camera reports BT.709, the live B2 and C1-SR frontends use
the matching BT.709 coefficients.

The dashboard applies a short exponential presentation filter to the displayed
top-three probabilities. It changes only the labels shown to a person, not
model inference, parity, timings, or stored benchmark data.

## Timing boundary

The reviewed R7.5 comparison uses five independent Release processes, 20 warmup
triples, 240 measured triples per process, and all six path-order permutations.
Each path uses the same 64-input corpus, Float32 activation format, Core ML
`.all` policy, persistent activation bridge, and input-to-result wall boundary.
The paired bootstrap uses 10,000 deterministic replicates in blocks of ten.

## Numerical parity

Parity compares the transformed activation and model outputs on 32 real and 32
procedural inputs. The accepted C1-SR artifact reports top-1, top-5 set, and
top-5 rank agreement of 1.0 with a maximum activation absolute error of
`5.960464e-6`. The raw JSON and the checker are the source of truth.

Implementation entry points:

- `Sources/PlaneFuseCore/NativePlaneCompiler.swift`
- `Sources/PlaneFuseCore/Shaders/NV12MobileNetV2Stem.metal`
- `Sources/PlaneFuseCore/R75SourceReuseBenchmark.swift`
- `Sources/PlaneFuseLive/CameraNV12MetalBridge.swift`
