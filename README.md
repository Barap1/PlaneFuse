# PlaneFuse

PlaneFuse is an experimental native-plane vision-inference compiler/runtime for Arm client devices, initially targeting Apple Silicon.

The hypothesis: many camera AI pipelines convert native NV12/YUV frames into a full RGB representation before a pretrained vision model immediately transforms those values again. For compatible model stems, PlaneFuse aims to compile/fuse the input transform toward the camera's native Y and UV planes so the model's first features can be produced without materializing a full RGB intermediate.

The first real pretrained proof is Apple MobileNetV2 ImageNet: PlaneFuse transforms its 3x3 stride-2 Conv+BatchNorm+ReLU6 stem to consume NV12 Y+UV planes, then hands the activation to the unchanged model tail. The accepted M5 evidence is in [`proof/m5-mobilenetv2.md`](proof/m5-mobilenetv2.md); M6 records two rejected shader-tuning experiments and a measured plateau rather than claiming an unsupported win.

The reusable inspection contract currently supports the 224x224 → 112x112, 3x3/stride-2, SAME-bottom/right family. It includes a non-pretrained reference fixture to test parameterization; it does not claim a second pretrained model.

## Reproduce the supported workflow

```bash
./pf doctor
./pf inspect mobilenetv2
./pf inspect fixture
./pf compile mobilenetv2
./pf test quick
./pf bench mobilenetv2 confirm
```

`compile mobilenetv2` is intentionally a preparation contract: it reports the required local model assets and never pretends to compile missing weights. `verify mobilenetv2` runs the real proof when those assets are present and reports missing assets otherwise. See [`proof/m7-reusability.md`](proof/m7-reusability.md) for compatibility limits and [`proof/m5-mobilenetv2.md`](proof/m5-mobilenetv2.md) for the benchmark contract.

## Planned outputs

- reference NV12/RGB/native-plane equivalence tests;
- optimized RGB Metal baseline;
- native-plane Metal stem;
- real pretrained vision-model integration;
- reproducible A/B/C benchmark harness;
- developer CLI/workflow;
- PlaneFuse Live local semantic-camera showcase;
- profiler and quality evidence.

## Start development

See `START_HERE.md`.

## Project rules

Codex should follow `AGENTS.md`, `SPEC.md`, `MILESTONES.md`, and `BENCHMARK_CONTRACT.md`.

## License

MIT. See `LICENSE`.
