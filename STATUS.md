# PlaneFuse status

Current milestone: R1 - Bottleneck decomposition and adversarial baselines (IN PROGRESS)

Overall status: PHASE 2 FRONTIER READY

Current branch: phase2/continuum

Current best verified result: pre-Phase-2 control — M4 fixture C end-to-end p50 0.1948 ms vs B 0.2328 ms; 16.34% lower under equal-submission methodology. Release-state MobileNetV2 C p50 was 50.8605 ms vs B 51.8460 ms; 1.90098% lower.

Correctness status: R0 PASS — 32-sample corpus, source lineage, clean-clone reproduction, allocation evidence, and physical-camera smoke are verified

Pipeline A status: not built

Pipeline B status: built; release quick artifact recorded

Pipeline C status: built; direct Y/UV fused stem with no RGB intermediate

Real model: Apple MobileNetV2 ImageNet integrated; unchanged 252-layer Core ML tail runs after the transformed 48-channel stem

PlaneFuse Live: CLI sample and camera NV12 inference path built; physical camera run permission-qualified

Known blockers: R1 needs reproducible component instrumentation, accelerator evidence, Pipeline A, and a strong B2 baseline. Public push/submission and any continuous-video capture remain human-controlled.

Next highest-leverage action: instrument the current B1/C0 path and establish the strongest fair conventional B2 baseline before bridge optimization.

Human decision currently required: no; camera authorization may become a one-time R0 permission boundary.

Last milestone summary: R0 passed after setup, lineage, corpus, artifact, allocation, camera-smoke, clean-clone, and hostile-review closure; R1 is now active.

Notes:
- Keep this file short.
- Update only when milestone, best result, blocker, or next action materially changes.
