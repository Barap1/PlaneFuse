<h1 align="center">PlaneFuse</h1>

<p align="center">
  Compile compatible pretrained vision stems directly onto native camera planes.
</p>

<p align="center">
  <strong>11.8% lower matched p50 latency</strong> on the reviewed MobileNetV2/NV12 experiment.
</p>

<p align="center">
  <a href="https://swift.org"><img alt="Swift" src="https://img.shields.io/badge/Swift-5.9%2B-F05138?logo=swift&logoColor=white"></a>
  <a href="https://developer.apple.com/metal/"><img alt="Metal" src="https://img.shields.io/badge/Metal-Apple%20Silicon-111111?logo=apple&logoColor=white"></a>
  <a href="https://developer.apple.com/documentation/coreml"><img alt="Core ML" src="https://img.shields.io/badge/Core%20ML-local-0A84FF"></a>
  <a href="https://developer.apple.com/documentation/coreml"><img alt="arm64" src="https://img.shields.io/badge/arm64-macOS-6E56CF"></a>
  <a href="https://arxiv.org/abs/1801.04381"><img alt="MobileNetV2" src="https://img.shields.io/badge/model-MobileNetV2-64E6C4"></a>
  <a href="LICENSE"><img alt="MIT License" src="https://img.shields.io/badge/license-MIT-2EA44F"></a>
</p>

<p align="center">
  <img src="docs/diagrams/planefuse-architecture.svg" alt="System architecture comparing the materialized RGB B2 path with the PlaneFuse C1-SR native-plane path before the shared MobileNetV2 tail" width="900">
</p>

## Quick start

Clone the repository first. The setup command downloads the pinned Apple
MobileNetV2 asset, derives the stem and tail, and verifies their hashes. Setup
needs network access once; inference runs locally after the assets are present.

```bash
git clone https://github.com/Barap1/PlaneFuse.git
cd PlaneFuse

./pf doctor
./pf setup mobilenetv2
./pf live --app
```

To check the local toolchain and run a short measured path:

```bash
./pf reproduce quick
./pf evidence --check
```

For the complete five-process experiment, see
[`docs/REPRODUCIBILITY.md`](docs/REPRODUCIBILITY.md).

## What PlaneFuse does

Your camera does not hand a vision model a neat RGB tensor. Video commonly
arrives as NV12, a two-plane YUV format: the Y plane stores luma (brightness)
and the interleaved UV plane stores subsampled chroma (color difference). A
conventional camera-AI pipeline converts those planes to RGB, normalizes the
pixels, and materializes a full RGB tensor before the model runs.

PlaneFuse started with a simple question: does that RGB image need to exist at
all?

For a compatible pretrained model, PlaneFuse composes camera conversion,
normalization, and the first learned operation into a native-plane stem. The
rest of the pretrained MobileNetV2 tail stays the same. PlaneFuse Live makes
that boundary visible in a local AppKit camera application, while the CLI keeps
the parity and reproduction checks repeatable.

Three ideas organize the project:

1. **RGB does not have to exist.** The camera already provides useful Y/UV
   source data.
2. **Compatible preprocessing can move into the first learned operation.**
   Fixed color conversion and normalization can be composed with a linear
   first convolution.
3. **Reuse matters.** C1-SR stages a small source tile once and reuses it while
   computing multiple learned output channels.

## The result

The final reviewed workload is Apple MobileNetV2 ImageNet classification on an
Apple Silicon Mac. C1-SR is the source-reuse PlaneFuse path. It measured
11.8% lower matched p50 latency than B2, the strongest matched
materialized-RGB baseline, and 6.2% lower than C1.

The public benchmark labels are:

- **B2**: conventional matched path that converts NV12 into a full normalized
  RGB representation before the learned stem.
- **C1**: native-plane stem that removes the full RGB representation.
- **C1-SR**: C1 plus explicit source-tile reuse across output channels.

| Path | Matched Release p50 |
| --- | ---: |
| B2, materialized RGB | 1.737875 ms |
| C1, native-plane stem | 1.633458 ms |
| C1-SR, source reuse | 1.532583 ms |

The paired B2 minus C1-SR median 95% confidence interval for the absolute
latency difference is `[0.180250, 0.198792] ms`. The percentages above compare
marginal p50 values; this interval is a different paired-median bootstrap
estimand, not a confidence interval for the percentage reduction.

![Matched Release p50 latency comparison](docs/assets/latency-comparison.svg)

Against the earlier C1 native-plane schedule, C1-SR matched top-1, top-5 set,
and top-5 ranking on all 64 inputs, with activation maximum error
`5.960464e-6`. The separate matched B2/C1 quality record retains two real-image
top-5 disagreements (top-5 set agreement `0.984375`, top-5 rank agreement
`0.96875`). The model was not retrained. These results are specific to the
reviewed model, input contract, toolchain, and measured Apple Silicon
environment; they are not a claim that every model is faster.

B2, C1, and C1-SR use the same NV12 chroma-siting rule: each full-resolution
source coordinate reads the corresponding half-resolution UV sample at
`(x / 2, y / 2)`. PlaneFuse changes where the arithmetic and reuse occur, not
which source chroma samples are used.

## Before and after

| | Conventional B2 | PlaneFuse C1-SR |
| --- | --- | --- |
| Source | NV12 Y + UV | NV12 Y + UV |
| Frontend | materialized Float32 RGB | transformed native-plane stem |
| Full RGB intermediate | 606,208 Metal-allocated bytes | 0 bytes |
| Model tail | pretrained MobileNetV2 tail | the same tail |
| Retraining | none | none |
| Reviewed matched p50 | 1.737875 ms | 1.532583 ms |

The resource number is a measured full RGB boundary, not a total application
memory claim. Both paths use the same persistent activation handoff and the
same Core ML tail.

## PlaneFuse Live

On an Apple Silicon Mac with Xcode command line tools and camera permission,
the Quick Start launches the app after setup.

PlaneFuse Live shows the real camera image, a center classification region,
top-three MobileNetV2 predictions, live B2 and C1-SR parity, runtime state,
the representation boundary, and a separate reviewed benchmark card. It is an
ImageNet classifier, not an object detector. Place one object inside the region
and use an object with a recognizable ImageNet label, such as a mug, bottle,
banana, keyboard, mouse, book, or microphone.

![PlaneFuse Live app window showing the local camera path, live predictions, measured metrics, representation comparison, and reviewed benchmark panel](docs/assets/planefuse-live.png)

The dashboard uses camera color metadata for live conversion when it is
available. Its short probability smoother changes only presentation. Raw
inference, parity, timing, and stored evidence remain unsmoothed.

## How it works

The conventional path creates a normalized RGB tensor and immediately turns it
into the first learned activation. That RGB tensor is temporary.

PlaneFuse moves compatible preprocessing across that boundary. C1-SR reads the
native Y and UV planes directly, stages a small source tile once, and reuses
those values across output channels before handing the activation to the
unchanged tail.

## Removing RGB was not the whole answer

C1 showed that the full RGB representation could be removed successfully and
already improved the matched path. A later, more aggressive direct camera-space
fusion attempt was slower because the removed intermediate had been enabling
useful source reuse. C1-SR keeps the native-plane advantage while staging each
source tile once and reusing it across output channels. That reuse-aware
schedule produced the accepted final result.

![Full RGB intermediate allocation](docs/assets/rgb-intermediate.svg)

Read the deeper implementation notes in
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) and
[`docs/TECHNICAL_DETAILS.md`](docs/TECHNICAL_DETAILS.md).

## The idea in equations

In plain English, the camera conversion and normalization are affine, and the
first learned operation is linear before its activation:

```text
r = A s + c
x = D(r - μ)
h = W x + b

W_native = W D A
b_native = b + W D(c - μ)
```

Here `s` is the camera-space source value, `A` and `c` describe YUV-to-RGB,
`D` and `μ` describe normalization, and `W` and `b` are the pretrained first
layer. PlaneFuse precomputes the compatible native-plane coefficients so the
full RGB tensor does not have to be materialized before the first learned
operation. The full derivation and padding details are in
[`docs/TECHNICAL_DETAILS.md`](docs/TECHNICAL_DETAILS.md).

## How we measured it

The headline compares B2 and C1-SR at the same input-to-result boundary. Both
paths use Release builds, arm64 Apple Silicon, the same 64-input corpus, the
same pretrained MobileNetV2 tail, persistent Float32 activation storage, and
Core ML compute units set to `.all`.

The reviewed protocol used five independent processes. Each process ran 20
warmup triples and 240 measured triples, balanced across all six three-way path
orders. Raw samples were retained, and the paired interval came from a
deterministic 10,000-replicate block bootstrap. Quality checks covered
activations, top-1 output, top-5 set, and top-5 ranking.

The evidence landing page links the raw JSON, profiler summary, corpus, and
read-only, model-based GPT-5.6 Sol adversarial review (not an external human audit),
plus the retained fresh-clone aggregate and raw batches:
[`docs/RESULTS_AND_EVIDENCE.md`](docs/RESULTS_AND_EVIDENCE.md).

## How source reuse scales

This controlled microbenchmark isolates the reuse mechanism inside the verified
MobileNetV2 stem. It varies active output-channel width only at the kernel's
real eight-channel grouping boundaries, keeps the same NV12 source geometry and
transformed weights, omits the unchanged Core ML tail, and checks C1/C1-SR
activation parity at every width.

| Active output channels | C1 stem p50 | C1-SR stem p50 | C1-SR vs C1 |
| ---: | ---: | ---: | ---: |
| 8 | 0.1750 ms | 0.2025 ms | -15.74% |
| 16 | 0.1693 ms | 0.1754 ms | -3.62% |
| 24 | 0.1744 ms | 0.1756 ms | -0.69% |
| 32 | 0.1793 ms | 0.1772 ms | +1.16% |
| 40 | 0.1883 ms | 0.1854 ms | +1.55% |
| 48 | 0.1987 ms | 0.1889 ms | +4.97% |

At narrow widths, staging overhead dominates. The paths move toward parity as
more channel work shares the tile, and the clearest C1-SR advantage appears at
the full 48-channel MobileNetV2 stem. This is a stem-only experiment on one
verified model; the partial widths are controlled microbenchmarks, not evidence
that larger models universally benefit.

![Stem-only source-reuse scaling](docs/assets/source-reuse-scaling.svg)

Run it with `./pf bench source-reuse-scale`. Raw batches and the aggregate live
in [`proof/final/source-reuse-scaling.json`](proof/final/source-reuse-scaling.json).

## Reproduce the result

For a short verification:

```bash
./pf doctor
./pf setup mobilenetv2
./pf reproduce quick
./pf evidence --check
```

For the complete five-batch protocol:

```bash
./pf reproduce final
```

Fresh output is written to `artifacts/reproduction/<timestamp>/`. The reviewed
files under `proof/` are never overwritten. See
[`docs/REPRODUCIBILITY.md`](docs/REPRODUCIBILITY.md) for requirements,
expected outputs, hashes, and hardware variability notes.

### Clean-clone reproduction

A clean clone of the public repository with no local project state passed the
documented workflow. B2, C1, and C1-SR preserved the same ordering, and the
fresh C1-SR result was approximately 9.7% lower p50 than B2. Quality and parity
checks passed. The frozen reviewed result remains 11.8128% lower by marginal
p50; exact latency varies between sessions, so the fresh run does not replace
the reviewed headline.

## Use PlaneFuse in a camera pipeline

Apple Silicon is an Arm-powered client platform. PlaneFuse keeps camera
capture, preprocessing, and MobileNetV2 inference on-device; after one-time
asset setup, inference needs no network. PlaneFuse targets the same class of
client-side camera stack used by Apple platforms: NV12 CVPixelBuffers exposed to
Metal, followed by local model inference. This project measures and verifies
that path on Apple Silicon macOS, not on a phone or iOS device.

The same design may fit compatible local camera workloads such as
accessibility features, visual search, robotics perception, smart-home
cameras, AR, industrial inspection, document understanding, and continuous
visual interfaces. These are applicability areas, not additional measured
models or platforms.

PlaneFuse addresses optimization goals in a narrow, evidenced way:

| Optimization goal | PlaneFuse evidence |
| --- | --- |
| Inference speed | Reviewed B2 versus C1-SR matched p50 |
| Quality preservation | 64-input parity and activation checks |
| Representation efficiency | Full RGB intermediate removed in C1-SR |
| Local execution | Core ML and Metal on Apple Silicon |
| Developer experience | Inspect, compile, verify, bench, and reproduce workflow |

It does not claim model-size reduction, measured energy reduction, phone
performance, iOS performance, Android performance, or universal acceleration.

The real integration sequence is:

```text
AVCaptureVideoDataOutput → CVPixelBuffer NV12 → CVMetalTextureCache
→ Y + UV textures → crop/resize → C1-SR → persistent activation
→ unchanged Core ML tail → local result
```

The compile-checked Swift facade owns the stem, persistent activation, and
tail. The application still owns camera capture, metadata inspection, and the
center-crop/resize bridge:

```swift
let runtime = try PlaneFuseMobileNetV2Runtime(
    device: device,
    coefficientsURL: root.appendingPathComponent("models/derived/MobileNetV2StemCoefficients.json"),
    tailModelURL: root.appendingPathComponent("models/derived/tail-compiled/MobileNetV2Tail.mlmodelc"),
    semantics: .bt601VideoRange
)
let prediction = try runtime.predict(nv12Textures: resizedNV12)
```

`MobileNetV2CameraAdapter` is a convenience wrapper around
`PlaneFuseMobileNetV2Runtime` that resolves the project assets and camera-facing
setup. Use `PlaneFuseMobileNetV2Runtime` directly when the host application
manages its own model and coefficient paths. The verified texture contract is
`Y: .r8Uint`, `UV: .rg8Uint`, with 224×224 luma and half-resolution 112×112 UV.

See [`Examples/PlaneFuseIntegration/README.md`](Examples/PlaneFuseIntegration/README.md)
and [`docs/INTEGRATION_GUIDE.md`](docs/INTEGRATION_GUIDE.md) for the camera
bridge and resource-lifetime details.

## Model compatibility

PlaneFuse has one fully verified end-to-end model today: the bundled Apple
MobileNetV2 configuration. The compiler idea applies to a broader class of
compatible affine-preprocessed vision stems, but each additional model still
needs its own parity and matched-performance evidence.

A candidate must expose known source semantics, deterministic preprocessing, a
fusable first learned operation, explicit padding and stride, and an unchanged
tail boundary. See [`docs/MODEL_COMPATIBILITY.md`](docs/MODEL_COMPATIBILITY.md)
for the verified, required, and unsupported cases.

The intended workflow is:

```text
inspect → compatibility check → compile → verify → benchmark → integrate
```

The limits and extension path are documented in
[`docs/MODEL_COMPATIBILITY.md`](docs/MODEL_COMPATIBILITY.md) and
[`docs/INTEGRATION_GUIDE.md`](docs/INTEGRATION_GUIDE.md).

## What we tried

The final design came from measured failures as well as the accepted result.

| Experiment | Result | Lesson |
| --- | --- | --- |
| Native-plane stem | Correct | RGB preprocessing can be compiled into a compatible stem |
| Float16 bridge | Rejected | Lower precision failed the quality gate |
| Metal 4 tail | Not usable on the stable toolchain | Model format and toolchain constraints matter |
| Polyphase 4:2:0 compiler | Correct, no stable end-to-end win | Fewer operations do not guarantee lower latency |
| Direct camera-space fusion | Slower | Removing a representation can destroy useful reuse |
| C1-SR source reuse | Accepted R7.5 path | Stage source tiles once and reuse them across channels |

## Limitations

The claimed result covers one pretrained MobileNetV2 configuration, one fixed
NV12 benchmark contract, and one Apple Silicon environment. Pipeline A is a
contextual ordinary image-input path under a different boundary, not the
headline comparison. A Float16 activation bridge failed the declared quality
gate, and a broader multi-model result was not established in this project. No
power, bandwidth, universal-model, or Apple-wide speed claim is made.

## Sources and references

- [Apple Core ML documentation](https://developer.apple.com/documentation/coreml)
- [Apple Metal documentation](https://developer.apple.com/documentation/metal)
- [Apple CVMetalTextureCache documentation](https://developer.apple.com/documentation/corevideo/cvmetaltexturecache)
- [Apple AVCaptureVideoPreviewLayer documentation](https://developer.apple.com/documentation/avfoundation/avcapturevideopreviewlayer)
- [MobileNetV2: Inverted Residuals and Linear Bottlenecks](https://arxiv.org/abs/1801.04381)
- [Arm Create: AI Optimization Challenge](https://arm-ai-optimization-challenge.devpost.com/)

## License

PlaneFuse source is released under the [MIT License](LICENSE). Model, corpus,
and third-party terms are summarized in
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).
