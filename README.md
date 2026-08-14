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

## What PlaneFuse does

Your laptop camera does not hand a vision model a neat RGB tensor. On Apple
devices, video commonly arrives as NV12, with luma and chroma in separate
planes. A conventional pipeline converts that frame to RGB, normalizes it, and
then sends it through the model.

PlaneFuse started with a simple question: does that RGB image need to exist at
all?

For a compatible pretrained model, PlaneFuse composes camera conversion,
normalization, and the first learned operation into a native-plane stem. The
rest of the pretrained MobileNetV2 tail stays the same. The project includes a
Metal/Core ML implementation, a reproducible benchmark harness, and PlaneFuse
Live, a local AppKit camera application.

## The result

The final reviewed workload is Apple MobileNetV2 ImageNet classification on an
Apple Silicon Mac. C1-SR is the source-reuse PlaneFuse path. It measured
11.8128% lower matched p50 latency than B2, the strongest matched
materialized-RGB baseline, and 6.1755% lower than the earlier C1 native-plane
schedule.

| Path | Matched Release p50 |
| --- | ---: |
| B2, materialized RGB | 1.737875 ms |
| C1, native-plane stem | 1.633458 ms |
| C1-SR, source reuse | 1.532583 ms |

The paired B2 minus C1-SR median 95% confidence interval is
`[0.180250, 0.198792] ms`. The percentages above compare marginal p50 values;
the interval is a paired-median bootstrap estimand.

![Matched Release p50 latency comparison](docs/assets/latency-comparison.svg)

Quality on the fixed 64-input corpus was top-1, top-5 set, and top-5 rank
agreement of 1.0, with activation maximum error `5.960464e-6`. These results
are specific to the reviewed model, input contract, toolchain, and measured
Apple Silicon environment. They are not a claim that every model is faster.

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

## Try it

On an Apple Silicon Mac with Xcode command line tools and camera permission:

```bash
./pf setup mobilenetv2
./pf live --app
```

PlaneFuse Live shows the real camera image, a center classification region,
top-three MobileNetV2 predictions, live B2 and C1-SR parity, runtime state,
the representation boundary, and a separate reviewed benchmark card. It is an
ImageNet classifier, not an object detector. Place one object inside the region
and use an object with a recognizable ImageNet label, such as a mug, bottle,
banana, keyboard, mouse, book, or microphone.

The dashboard uses camera color metadata for live conversion when it is
available. Its short probability smoother changes only presentation. Raw
inference, parity, timing, and stored evidence remain unsmoothed.

## How it works

The conventional path creates a normalized RGB tensor and runs the learned
stem. C1-SR reads the native Y and UV planes, stages the source tile once, and
reuses those values across output channels before handing the activation to the
unchanged tail.

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
full RGB tensor does not have to be materialized. The full derivation and
padding details are in [`docs/TECHNICAL_DETAILS.md`](docs/TECHNICAL_DETAILS.md).

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
independent review:
[`docs/RESULTS_AND_EVIDENCE.md`](docs/RESULTS_AND_EVIDENCE.md).

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

## Mobile AI in practice

PlaneFuse runs the camera path and inference locally on an Arm-powered Apple
Silicon client device. Once model assets are available, it does not need a
cloud service. That gives the live application offline behavior and keeps the
camera data on the device. The measured contribution is a lower-latency input
representation path, not a claim about battery or energy use.

The same design is relevant to compatible local camera workloads such as
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

## Model compatibility and integration

The current end-to-end implementation supports the bundled Apple MobileNetV2
configuration. A compatible model must expose known source semantics,
deterministic preprocessing, a fusable first learned operation, explicit
padding and stride, and an unchanged tail boundary.

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
headline comparison. T2 and T3 were not met or established. No power,
bandwidth, universal-model, or Apple-wide speed claim is made.

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
