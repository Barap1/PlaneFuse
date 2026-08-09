# PlaneFuse

PlaneFuse Continuum is an experimental native-plane vision-inference compiler/runtime for Arm client devices, initially targeting Apple Silicon. Phase 2 is currently in R0 repository hardening; the accepted pre-Phase-2 evidence remains the control while reproducibility and frontier experiments are added.

The hypothesis: many camera AI pipelines convert native NV12/YUV frames into a full RGB representation before a pretrained vision model immediately transforms those values again. For compatible model stems, PlaneFuse aims to compile/fuse the input transform toward the camera's native Y and UV planes so the model's first features can be produced without materializing a full RGB intermediate.

The first real pretrained proof is Apple MobileNetV2 ImageNet: PlaneFuse transforms its 3x3 stride-2 Conv+BatchNorm+ReLU6 stem to consume NV12 Y+UV planes, then hands the activation to the unchanged model tail. The accepted M5 evidence is in [`proof/m5-mobilenetv2.md`](proof/m5-mobilenetv2.md); M6 records two rejected shader-tuning experiments and a measured plateau rather than claiming an unsupported win.

The reusable inspection contract currently supports the 224x224 → 112x112, 3x3/stride-2, SAME-bottom/right family. It includes a non-pretrained reference fixture to test parameterization; it does not claim a second pretrained model.

The current verified MobileNetV2 result is qualified to the measured Apple M5 Pro environment: C reduced equal-submission end-to-end p50 by 1.90% in the release-state confirmation, with a 54.43% frontend reduction and no full RGBA32Float intermediate in C. This is not a universal speed or memory claim.

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
- The R6 camera path maps CVPixelBuffer Y/UV planes with CVMetalTextureCache and resizes on the GPU with persistent B/C resources; the 300-frame physical-camera gate is not yet accepted because the current session is not delivering frames.
- Power, peak-memory, bandwidth, population-accuracy, and universal-model claims are intentionally excluded.

## Start development

See `START_HERE.md`.

## Project rules

Codex should follow `AGENTS.md`, `SPEC.md`, `SPEC_V2_ADDENDUM.md`, `MILESTONES_V2.md`, and `BENCHMARK_CONTRACT_V2.md`.

## License

MIT. See `LICENSE`.
