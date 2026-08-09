# PlaneFuse status

Current milestone: M11 - Technical and hackathon audit / release preparation (COMPLETE)

Overall status: RELEASE CANDIDATE

Current branch: main (expected)

Current best verified result: M4 fixture C end-to-end p50 0.1948 ms vs B 0.2328 ms; 16.34% lower under equal-submission methodology

Correctness status: M10 PASS — final current-state MobileNetV2 confirmation, evidence index, system metadata, and claims audit are recorded

Pipeline A status: not built

Pipeline B status: built; release quick artifact recorded

Pipeline C status: built; direct Y/UV fused stem with no RGB intermediate

Real model: Apple MobileNetV2 ImageNet integrated; unchanged 252-layer Core ML tail runs after the transformed 48-channel stem

PlaneFuse Live: CLI sample and camera NV12 inference path built; physical camera run permission-qualified

Known blockers: public push/submission approval and a permitted physical camera run for any video claim remain human-controlled. MobileCLIP and Arm Performix remain optional and were not allowed to jeopardize the core.

Next highest-leverage action: if release is desired, review `proof/m11-release-audit.md`, run `./pf live --camera` on a permitted Apple-Silicon device, then explicitly approve any public push/submission.

Human decision currently required: no

Last milestone summary: M11 release candidate — technical, benchmark, developer-tooling, local-demo, claim, and hackathon audits are synchronized; no external publication performed.

Notes:
- Keep this file short.
- Update only when milestone, best result, blocker, or next action materially changes.
