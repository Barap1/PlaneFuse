# M5 — Apple MobileNetV2 proof

Status: **accepted** at commits `6e685a6`, `b8b7850`, and `df5f573`.

PlaneFuse applies its native-plane compiler/runtime boundary to Apple’s
pretrained MobileNetV2 ImageNet model. The source asset is downloaded locally
and identified by SHA-256; it is not committed.

Source: <https://ml-assets.apple.com/coreml/models/Image/ImageClassification/MobileNetV2/MobileNetV2.mlmodel>

SHA-256: `cb5a35f593582232140556bbfa4618e66b37b8ff2fc33ba17db909e1050fd144`

## Boundary and provenance

The preparation tool verifies the source graph’s actual `BOTTOM_RIGHT_HEAVY`
SAME asymmetry, then derives:

```text
source image/array
  -> Conv 3x3, stride 2, 3 -> 48, SAME bottom/right-heavy
  -> BatchNorm -> ReLU6
  -> planefuse_mobilenetv2_stem_features [48, 112, 112]
  -> unchanged source layers 6...tail and classifier
```

Pipeline B is the optimized conventional path: NV12 → normalized RGBA32Float →
ordinary RGB stem. Pipeline C reads Y/UV directly and emits the CHW stem
activation without a full RGB intermediate. Both invoke the same compiled tail;
the explicit CPU-visible Float32 `MLMultiArray` handoff is included in e2e time.

`models/derived/manifest.json` records source, derived StemArray/FullArray/Tail
hashes, exact input names/shapes, layer boundary, and the checked asymmetry.

## Reproduce

```bash
python3 -m venv .venv
.venv/bin/pip install coremltools
curl -L --fail -o models/MobileNetV2.mlmodel \
  https://ml-assets.apple.com/coreml/models/Image/ImageClassification/MobileNetV2/MobileNetV2.mlmodel
VIRTUAL_ENV=.venv .venv/bin/python scripts/prepare_mobilenetv2.py \
  models/MobileNetV2.mlmodel models/derived
rm -rf models/derived/stem-array-compiled models/derived/full-array-compiled models/derived/tail-compiled
xcrun coremlc compile models/derived/MobileNetV2Stem.mlmodel \
  models/derived/stem-array-compiled --platform macOS --deployment-target 13.0
xcrun coremlc compile models/derived/MobileNetV2FullArray.mlmodel \
  models/derived/full-array-compiled --platform macOS --deployment-target 13.0
xcrun coremlc compile models/derived/MobileNetV2Tail.mlmodel \
  models/derived/tail-compiled --platform macOS --deployment-target 13.0
./pf test quick
./pf bench mobilenetv2 confirm
```

The benchmark consumes the tracked, hashed corpus in `proof/m5-corpus/`, decodes
each image with ImageIO, deterministically resizes it,
and converts them to BT.601 video-range NV12. It does not generate synthetic
byte-offset fixtures for M5 acceptance.

## Confirmation evidence

Hardware: Apple M5 Pro, macOS 26.6, Xcode 26.6, Release, 10 warmups and 100
measured iterations per batch, four real corpus samples, commit `df5f573`.

| Metric | Batch 1 | Batch 2 |
| --- | ---: | ---: |
| B end-to-end p50 | 53.4647 ms | 53.6828 ms |
| C end-to-end p50 | 52.3829 ms | 52.6675 ms |
| C reduction vs B | 2.02% | 1.89% |
| B frontend p50 | 0.6503 ms | 0.4233 ms |
| C frontend p50 | 0.2517 ms | 0.2047 ms |
| C frontend reduction | 61.29% | 51.65% |
| B e2e p95 | 55.1639 ms | 54.6733 ms |
| C e2e p95 | 53.5133 ms | 53.7329 ms |
| B RGBA32Float intermediate logical payload | 802,816 bytes | 802,816 bytes |
| C RGBA32Float intermediate logical payload | 0 bytes | 0 bytes |
| B/C top-1 agreement | 100% | 100% |
| raw B/C max activation error | 9.298325e-6 | 9.298325e-6 |
| FullArray vs split StemArray+tail | 100% | 100% |

The raw B/C Metal threshold remains `<=1e-5` (D008). The independent
source-derived StemArray/FullArray reference runs CPU-only in Core ML and has a
separate `<=1e-4` reference-math threshold for backend accumulation/order; its
measured max errors were `3.904105e-5` vs B and `3.892183e-5` vs C. The task
agreement threshold is unchanged at `>=0.995`. These thresholds and the
reference backend are emitted in each benchmark artifact.

Artifacts:

- `benchmarks/results/m5-mobilenetv2-confirm1.json`
- `benchmarks/results/m5-mobilenetv2-confirm2.json`
- `benchmarks/history.jsonl`
- `proof/m5-validation-corpus.json`
- `models/derived/manifest.json` (generated locally)
