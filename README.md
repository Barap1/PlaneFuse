# PlaneFuse

PlaneFuse is an experimental native-plane vision-inference compiler/runtime for Arm client devices, initially targeting Apple Silicon.

The hypothesis: many camera AI pipelines convert native NV12/YUV frames into a full RGB representation before a pretrained vision model immediately transforms those values again. For compatible model stems, PlaneFuse aims to compile/fuse the input transform toward the camera's native Y and UV planes so the model's first features can be produced without materializing a full RGB intermediate.

This repository is currently a hackathon research/build workspace. Measured claims will be added only after the benchmark and correctness gates pass.

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
