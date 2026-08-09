# M5 — Apple MobileNetV2 proof

PlaneFuse M5 uses Apple’s pretrained MobileNetV2 ImageNet Core ML model. The
source asset is downloaded from Apple’s model gallery and is not committed;
the SHA-256 recorded here identifies the exact asset used for the evidence.

Source: <https://ml-assets.apple.com/coreml/models/Image/ImageClassification/MobileNetV2/MobileNetV2.mlmodel>

SHA-256: `cb5a35f593582232140556bbfa4618e66b37b8ff2fc33ba17db909e1050fd144`

## Compiled boundary

The preparation tool inspects and validates the source graph, then derives two
local Core ML artifacts:

```text
MobileNetV2 source image input
  -> Conv 3x3, stride 2, same padding, 3 -> 48
  -> BatchNorm
  -> ReLU6
  -> planefuse_mobilenetv2_stem_features [48, 112, 112]
  -> unchanged source layers 6...tail and classifier
```

Pipeline B runs NV12 → normalized RGBA32Float → ordinary RGB Conv/BN/ReLU6.
Pipeline C folds the same pretrained weights and reads Y/UV directly into the
CHW activation. Both paths pass the same activation to the same compiled Core
ML tail. The current tail handoff uses an explicit CPU-visible `MLMultiArray`
adapter; it is included in end-to-end timing and is not claimed to be zero-copy.

## Reproduce

```bash
python3 -m venv .venv
.venv/bin/pip install coremltools
curl -L --fail -o models/MobileNetV2.mlmodel \
  https://ml-assets.apple.com/coreml/models/Image/ImageClassification/MobileNetV2/MobileNetV2.mlmodel
VIRTUAL_ENV=.venv .venv/bin/python scripts/prepare_mobilenetv2.py \
  models/MobileNetV2.mlmodel models/derived
xcrun coremlc compile models/derived/MobileNetV2Tail.mlmodel \
  models/MobileNetV2Tail.mlmodelc --platform macOS --deployment-target 13.0
PF_MOBILENET_COEFFICIENTS=models/derived/MobileNetV2StemCoefficients.json \
PF_MOBILENET_TAIL=models/MobileNetV2Tail.mlmodelc \
./pf bench mobilenetv2 confirm
```

## Confirmed result

Hardware: Apple M5 Pro, macOS 26.6, Xcode 26.6, Release, 20 measured
iterations per batch, 5 warmups, 8 validation samples.

| Metric | Batch 1 | Batch 2 |
| --- | ---: | ---: |
| B end-to-end p50 | 56.6585 ms | 56.5140 ms |
| C end-to-end p50 | 54.6994 ms | 55.3209 ms |
| C reduction vs B | 3.46% | 2.11% |
| B frontend p50 | 0.5510 ms | 0.8235 ms |
| C frontend p50 | 0.2100 ms | 0.2761 ms |
| C frontend reduction | 61.90% | 66.47% |
| B RGBA32Float intermediate | 802,816 bytes | 802,816 bytes |
| C RGBA32Float intermediate | 0 bytes | 0 bytes |
| top-1 output agreement | 100% | 100% |
| max activation absolute error | 9.059906e-6 | 9.059906e-6 |

Raw artifacts:

- `benchmarks/results/m5-mobilenetv2-final.json`
- `benchmarks/results/m5-mobilenetv2-final2.json`
- `proof/m5-validation-corpus.json`

The validation inputs are deterministic NV12 fixture variants. They establish
real pretrained-weight transformation, native-stem parity, and B/C tail
agreement; they do not claim ImageNet accuracy or semantic quality. A later
demo/release corpus must add real camera/photo frames before making a user-facing
quality claim.
