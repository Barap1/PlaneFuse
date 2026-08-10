# PlaneFuse

PlaneFuse Continuum is an experimental native-plane vision-inference compiler/runtime for Arm client devices, initially targeting Apple Silicon. Phase 2 is in R6.1 release-grade camera benchmarking: the permitted 300-frame camera-delivery gate passes in the current Debug path, while the fair Release B2/C1 benchmark and judge-facing UI remain unfinished.

The hypothesis: many camera AI pipelines convert native NV12/YUV frames into a full RGB representation before a pretrained vision model immediately transforms those values again. For compatible model stems, PlaneFuse aims to compile/fuse the input transform toward the camera's native Y and UV planes so the model's first features can be produced without materializing a full RGB intermediate.

The first real pretrained proof is Apple MobileNetV2 ImageNet: PlaneFuse transforms its 3x3 stride-2 Conv+BatchNorm+ReLU6 stem to consume NV12 Y+UV planes, then hands the activation to the unchanged model tail. The accepted M5 evidence is in [`proof/m5-mobilenetv2.md`](proof/m5-mobilenetv2.md); M6 records two rejected shader-tuning experiments and a measured plateau rather than claiming an unsupported win.

The reusable inspection contract currently supports the 224x224 → 112x112, 3x3/stride-2, SAME-bottom/right family. It includes a non-pretrained reference fixture to test parameterization; it does not claim a second pretrained model.

The accepted pre-Phase-2 MobileNetV2 result remains historical control evidence. It is not the final Phase 2 camera claim: the current camera run uses B1 RGBA32Float, Debug, serial B-then-C execution, and post-resize timing. Final claims are gated on Release B2/C1 measurements.

## Reproduce the supported workflow

```bash
./pf setup mobilenetv2
./pf doctor
./pf inspect mobilenetv2
./pf inspect fixture
./pf compile mobilenetv2
./pf test quick
./pf bench mobilenetv2 confirm
```

`setup mobilenetv2` creates/reuses the project-local environment, verifies the official Apple source hash, derives the stem/tail assets, and compiles the three local Core ML artifacts. `compile mobilenetv2` remains an inspection/preparation report. `verify mobilenetv2` runs the real proof when those assets are present. See [`proof/m7-reusability.md`](proof/m7-reusability.md) for compatibility limits and [`proof/m5-mobilenetv2.md`](proof/m5-mobilenetv2.md) for the benchmark contract.

## Current scope and limitations

- Apple MobileNetV2 is the only pretrained workload claimed.
- The accepted tail handoff is CPU-visible Float32 `MLMultiArray`; it is not called zero-copy.
- The R6 camera path maps CVPixelBuffer Y/UV planes with CVMetalTextureCache and resizes on the GPU with persistent B/C resources; its 300-frame physical-camera delivery gate passed in Debug. Release-grade B2/C1 timing, frame-delivery boundaries, dropped-frame/thermal metadata, and the final UI are still pending.
- Power, peak-memory, bandwidth, population-accuracy, and universal-model claims are intentionally excluded.

## Start development

See `START_HERE.md`.

## Project rules

Codex should follow `AGENTS.md`, `SPEC.md`, `SPEC_V2_ADDENDUM.md`, `MILESTONES_V2.md`, and `BENCHMARK_CONTRACT_V2.md`.

## License

MIT. See `LICENSE`.
