# PlaneFuse status

Current milestone: R4 - Metal 4 GPU-timeline model-tail feasibility (IN PROGRESS)

Overall status: PHASE 2 FRONTIER READY

Current branch: phase2/continuum

Current best verified result: pre-Phase-2 control — M4 fixture C end-to-end p50 0.1948 ms vs B 0.2328 ms; 16.34% lower under equal-submission methodology. Release-state MobileNetV2 C p50 was 50.8605 ms vs B 51.8460 ms; 1.90098% lower.

Correctness status: R0 PASS — 32-sample corpus, source lineage, clean-clone reproduction, allocation evidence, and physical-camera smoke are verified

Pipeline A status: not built

Pipeline B status: built; release quick artifact recorded

Pipeline C status: built; direct Y/UV fused stem with no RGB intermediate

Real model: Apple MobileNetV2 ImageNet integrated; unchanged 252-layer Core ML tail runs after the transformed 48-channel stem

PlaneFuse Live: CLI sample and camera NV12 inference path built; physical camera run permission-qualified

Known blockers: R4 must establish whether the stable Xcode 26.6 environment can execute the unchanged tail as a supported Metal 4 ML Program/MTLPackage path. R3 Float16 was rejected on predeclared quality thresholds. Public push/submission and any continuous-video capture remain human-controlled.

Next highest-leverage action: inspect installed Metal 4 machine-learning tooling and attempt a provenance-preserving tail feasibility path; retain the accepted Float32 shared bridge as the control.

Human decision currently required: no; camera authorization may become a one-time R0 permission boundary.

Last milestone summary: R2 passed hostile review with lifetime-safe buffer-backed views, three 200-iteration confirmation batches, ~97.3% handoff reduction, ~95.6%-95.8% end-to-end reduction, and preserved parity. R3 Float16 feasibility was rejected: max probability error 0.01288722 exceeded 0.005; R4 is now active.

Notes:
- Keep this file short.
- Update only when milestone, best result, blocker, or next action materially changes.
