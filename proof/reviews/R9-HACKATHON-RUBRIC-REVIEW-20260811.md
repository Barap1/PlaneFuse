# R9 hackathon-rubric review — 2026-08-11

This is a local rubric review, not a submission and not an external judge decision.

## Strengths supported by evidence

- Technical depth: transformed a real pretrained MobileNetV2 stem for Apple NV12 and added a source-reuse schedule with exact parity evidence.
- Optimization credibility: B2, accepted C1, R6.5 negative, and R7.5 are separated; the narrative explains reuse economics rather than claiming fusion always wins.
- Demonstration: `planefuse-live --app` provides a judge-facing local camera shell with top-3 output, live boundary timing, FPS/drop counters, parity, and RGB/CPU-copy indicators.
- Reproducibility: clean-clone PASS, fixed corpus, raw batches, deterministic checkers, profiler event export, and independent SHIP review.
- Honesty: Pipeline A context, procedural lineage qualification, retained disagreements, historical camera provenance, T2/T3 gaps, and publication gates remain visible.

## Remaining rubric risks

- Continuous physical-camera capture and final video still require a human-permitted machine/session; zero-callback failure must not be hidden.
- The measured result is one pretrained workload and one Apple-Silicon environment; no universal performance claim is valid.
- The R7.5 T1 result is a matched same-workload target result, not a claim that PlaneFuse beats every conventional pipeline.
- External publication and Devpost submission remain deliberately unperformed.

## Reviewer conclusion

Technically compelling and reproducible for local review, with the strongest score impact coming from the evidence quality and honest negative-result narrative. Finish only the human-gated camera/video/publication steps; do not add performance research.
