<h1 align="center">PlaneFuse</h1>

<p align="center">
  Run a compatible pretrained vision stem directly from native camera planes instead of building a full RGB tensor first.
</p>

<p align="center">
  <strong>11.8% lower matched p50 latency</strong> on the reviewed MobileNetV2/NV12 benchmark.
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

## In plain English

Mac cameras give applications video in NV12, with separate luma and chroma
planes. Most pretrained vision models expect RGB, so a conventional pipeline
creates a full RGB representation before inference.

PlaneFuse changes a compatible model's first learned step so it can consume the
camera planes directly. The rest of the pretrained MobileNetV2 tail stays the
same. The result is a local AppKit demonstration and a reproducible Metal/Core
ML implementation.

## Reviewed result

On the final reviewed MobileNetV2/NV12 test, C1-SR measured 11.8128% lower
matched p50 than the strongest matched B2 materialized-RGB baseline. It also
measured 6.1755% lower than the accepted C1 native-plane path.

| Path | Matched Release p50 |
| --- | ---: |
| B2, materialized RGB | 1.737875 ms |
| C1, native-plane stem | 1.633458 ms |
| C1-SR, source reuse | 1.532583 ms |

The paired B2 minus C1-SR median 95% confidence interval is
`[0.180250, 0.198792] ms`. The percentages compare marginal p50 values; the
interval is a paired-median bootstrap estimand.

![Matched Release p50 latency comparison](docs/assets/latency-comparison.svg)

Quality on the fixed 64-input corpus was top-1, top-5 set, and top-5 rank
agreement of 1.0, with activation maximum error `5.960464e-6`. The result is
specific to the reviewed MobileNetV2/NV12 workload and measured Apple Silicon
environment. It is not a claim that PlaneFuse makes all AI faster.

## Try it

PlaneFuse is a macOS Swift Package. On an Apple Silicon Mac with Xcode command
line tools and camera permission:

```bash
./pf setup mobilenetv2
./pf live --app
```

PlaneFuse Live shows the real camera preview, live classification, B2 and C1-SR
parity, current runtime measurements, the representation boundary, and a
separate stored benchmark card. Live predictions are MobileNetV2 classification,
not object detection. Place one object inside the classification region.

If a camera or model asset is unavailable, the app reports that state and does
not fill in live values from stored evidence.

The app reports the camera's YCbCr matrix and uses the matching live conversion
when the camera advertises BT.709. The displayed top-three labels use a short
presentation smoother so they are easier to read; inference, parity, timings,
and stored benchmark values remain unsmoothed.

## How it works

The conventional B2 path materializes a normalized RGB tensor, runs the learned
stem, and passes the activation to the shared tail. PlaneFuse composes the
camera conversion, normalization, and linear first stem into one source-domain
operator. C1-SR stages the source Y/UV taps once per output tile and reuses them
across output channels.

![Full RGB intermediate allocation](docs/assets/rgb-intermediate.svg)

The full technical explanation is in
[`docs/TECHNICAL_DETAILS.md`](docs/TECHNICAL_DETAILS.md). The implementation
overview is in [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## The idea in equations

The camera conversion and normalization are affine, and the first learned layer
is linear before its activation:

```text
r = A s + c
x = D(r - μ)
h = W x + b

W_native = W D A
b_native = b + W D(c - μ)
```

PlaneFuse precomputes this transformed first-layer representation so the shader
can consume native camera values without explicitly materializing RGB first.
C1-SR adds source-tile staging and reuse to the same transformed operator.

## Experimental findings

The work kept negative results. Float16 failed the quality gate. Metal 4 was not
a stable path for this model format. The polyphase compiler was correct but had
no stable end-to-end win. Direct camera-space fusion was slower because it
removed useful source reuse. [`docs/WHAT_WE_TRIED.md`](docs/WHAT_WE_TRIED.md)
records the progression and what each result changed.

## Reproduce

```bash
./pf doctor
./pf setup mobilenetv2
./pf build
./pf test quick
./pf verify
./pf verify lineage
./pf bench quick
./pf evidence --check
./pf live --sample
```

The setup command uses a project-local environment, verifies the model source
hash, prepares the derived assets, and is safe to repeat. Verbose command logs
are written under `artifacts/logs/`.

For the curated result and its raw artifacts, read
[`docs/RESULTS_AND_EVIDENCE.md`](docs/RESULTS_AND_EVIDENCE.md). To regenerate
the graphs and diagrams:

```bash
python3 scripts/generate_readme_assets.py
```

## Limitations

The current claimed workload is Apple MobileNetV2 ImageNet classification on one
Apple Silicon environment. Pipeline A is faster under a distinct pre-rendered
image-input boundary and is contextual, not the matched headline. T2 and T3
were not met or established. No power, bandwidth, universal-model, or
Apple-wide speed claim is made. The live camera path has a separate runtime
boundary from the reviewed benchmark.

## Project context

PlaneFuse was built for the Arm Create: AI Optimization Challenge 2026 Mobile
AI track, and the work is intended to remain useful as an independent systems
research prototype. Performance research is frozen at the reviewed C1-SR result.

## Sources and references

- [Apple Core ML documentation](https://developer.apple.com/documentation/coreml)
- [Apple Metal documentation](https://developer.apple.com/documentation/metal)
- [Apple CVMetalTextureCache documentation](https://developer.apple.com/documentation/corevideo/cvmetaltexturecache)
- [MobileNetV2: Inverted Residuals and Linear Bottlenecks](https://arxiv.org/abs/1801.04381)
- [Arm Create: AI Optimization Challenge](https://arm-ai-optimization-challenge.devpost.com/)

## License

PlaneFuse source is released under the [MIT License](LICENSE). Model, corpus,
and third-party terms are summarized in
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).
