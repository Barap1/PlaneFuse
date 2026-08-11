# PlaneFuse

PlaneFuse is a local Apple-Silicon compiler/runtime experiment for camera AI. It selectively removes a camera/model representation boundary when materializing that representation costs more than the reuse value it provides.

## See it first

On a permitted macOS camera machine with the local MobileNetV2 assets installed:

```bash
./pf setup mobilenetv2
./pf live --app
```

The PlaneFuse Live dashboard shows a real NV12 camera preview, top-3 predictions, live measured timing, FPS/drop counters, parity, and resource-boundary indicators. If the camera is unavailable, it reports that state and does not invent live metrics. The stored benchmark panel is labeled `STORED EVIDENCE`.

## The technical idea

The accepted MobileNetV2 workload has a 3x3 stride-2 stem. B2 materializes normalized RGB before the learned stem. PlaneFuse C1-SR keeps the exact NV12 Y/UV mapping and transformed pretrained operator, but cooperatively loads source tiles and reuses those taps across output channels before handing the persistent Float32 activation to the unchanged Core ML tail.

Architecture source: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Verified evidence

| Comparison | Result | Status |
| --- | ---: | --- |
| R7.5 C1-SR versus accepted C1, matched Release p50 | 6.1755% lower | VERIFIED / Sol SHIP |
| R7.5 C1-SR versus fresh strongest B2, matched Release p50 | 11.8128% lower | VERIFIED / T1 passed |
| R7.5 C1-SR activation max error | 5.960464e-6 | VERIFIED |
| R7.5 top-1 / top-5 set / top-5 ranking agreement | 1.0 / 1.0 / 1.0 | VERIFIED |
| Repaired R7 B2 versus C1 matched p50 | 2.115766% C1 lower | QUALIFIED; below 10% |
| Pipeline A | faster under a distinct pre-rendered image-input boundary | QUALIFIED CONTEXT |

The authoritative R7.5 confirmation is [`proof/r7.5-source-reuse-final-52db138-20260811T1605Z-confirm.json`](proof/r7.5-source-reuse-final-52db138-20260811T1605Z-confirm.json), independently reviewed in [`proof/reviews/R7-R75-HOSTILE-9DAFDBC-20260811.md`](proof/reviews/R7-R75-HOSTILE-9DAFDBC-20260811.md). The paired CI and the difference of marginal p50s are different estimands; see [`CLAIMS.md`](CLAIMS.md).

## Reproduce and inspect

```bash
./pf doctor
./pf inspect mobilenetv2
./pf test quick
./pf bench mobilenetv2 quick
python3 -B scripts/check_r75_source_reuse.py \
  proof/r7.5-source-reuse-final-52db138-20260811T1605Z-confirm.json \
  --expected-commit 52db138feef3d6fc52bcb5839a419423fd992019
```

The compact evidence map is [`proof/evidence-index.md`](proof/evidence-index.md). The clean-clone validation command is [`scripts/release_validate.sh`](scripts/release_validate.sh).

## Honest limits

- MobileNetV2 is the only claimed pretrained workload.
- T2 and T3 were not met or established; T4 was not used as an escape hatch.
- R6.5 direct camera-space fusion is retained as a negative result: eliminating an intermediate can lose useful reuse.
- A fresh R7 physical-camera attempt received zero callbacks; no current camera performance value was inferred.
- No power, bandwidth, universal-model, or publication claim is made.

## Project state

Performance research is frozen after the independent SHIP review. R8/R9 work is limited to the judge-facing app, reproducibility, evidence navigation, claims audit, and submission preparation. Repository publication, video publication, and Devpost submission remain human gates.

See [`STATUS.md`](STATUS.md), [`SPEC_V2_ADDENDUM.md`](SPEC_V2_ADDENDUM.md), and [`BENCHMARK_CONTRACT_V2.md`](BENCHMARK_CONTRACT_V2.md).

## License and notices

PlaneFuse source is MIT licensed. Model/source attribution and third-party terms are collected in [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).
