# R3 Float16 tail feasibility

Status: REJECTED candidate; Float16 IOSurface bridge not accepted.

Preparation and check:

```bash
./.venv/bin/python scripts/prepare_mobilenetv2_float16.py \
  models/derived/MobileNetV2Tail.mlmodel \
  /private/tmp/planefuse-f16/MobileNetV2TailFloat16-v7.mlmodel
xcrun coremlc compile /private/tmp/planefuse-f16/MobileNetV2TailFloat16-v7.mlmodel \
  /private/tmp/planefuse-f16 --platform macOS --deployment-target 13.0
PF_MOBILENET_FLOAT16_TAIL=/private/tmp/planefuse-f16/MobileNetV2TailFloat16-v7.mlmodelc \
  ./pf verify float16
```

The derived tail graph is unchanged; only the input feature declaration is
Float16 and the minimum Core ML specification version is raised to 7. The
candidate compiled successfully on stable Xcode 26.6. Before any IOSurface or
Metal timing, it was compared with the accepted Float32 CPU-only tail over all
32 corpus frames using the predeclared thresholds:

- top-1 agreement ≥ 0.995;
- maximum probability absolute error ≤ 0.005;
- mean probability L1 distance ≤ 0.05.

Observed: top-1 agreement `1.0`, maximum probability absolute error
`0.01288722`, and mean probability L1 distance `0.01548487`. The maximum
probability absolute error fails its `0.005` threshold; the mean probability
L1 distance passes its `0.05` threshold. R3 remains rejected because the
maximum-error gate failed, so no IOSurface bridge benchmark was run and no
threshold was relaxed.
The accepted R2 Float32 shared bridge remains the control for R4.

Machine-readable result: `proof/r3-float16-feasibility.json`.
