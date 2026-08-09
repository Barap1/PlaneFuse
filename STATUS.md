# PlaneFuse status

Current milestone: R0 - Repository truth, evidence, and reproducibility hardening (IN PROGRESS)

Overall status: PHASE 2 HARDENING

Current branch: phase2/continuum

Current best verified result: pre-Phase-2 control — M4 fixture C end-to-end p50 0.1948 ms vs B 0.2328 ms; 16.34% lower under equal-submission methodology. Release-state MobileNetV2 C p50 was 50.8605 ms vs B 51.8460 ms; 1.90098% lower.

Correctness status: pre-Phase-2 MobileNetV2 evidence remains accepted; R0 corpus/setup/lineage closure is in progress

Pipeline A status: not built

Pipeline B status: built; release quick artifact recorded

Pipeline C status: built; direct Y/UV fused stem with no RGB intermediate

Real model: Apple MobileNetV2 ImageNet integrated; unchanged 252-layer Core ML tail runs after the transformed 48-channel stem

PlaneFuse Live: CLI sample and camera NV12 inference path built; physical camera run permission-qualified

Known blockers: R0 still needs clean-clone setup validation, final artifact/reference cleanup, and a returned hostile review after fixes. Public push/submission and any continuous-video capture remain human-controlled.

Next highest-leverage action: finish the R0 hardening commit, then run the hostile R0 review before starting the shared-buffer bridge.

Human decision currently required: no; camera authorization may become a one-time R0 permission boundary.

Last milestone summary: Phase 2 planning package committed; the former M11 release-candidate label is reopened for mandatory R0 truth/reproducibility hardening.

Notes:
- Keep this file short.
- Update only when milestone, best result, blocker, or next action materially changes.
