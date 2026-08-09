# PlaneFuse status

Current milestone: M7 - Reusability / second compatible target

Overall status: IN PROGRESS

Current branch: main (expected)

Current best verified result: M4 fixture C end-to-end p50 0.1948 ms vs B 0.2328 ms; 16.34% lower under equal-submission methodology

Correctness status: M6 PASS — two bounded source-grid experiments preserved parity but regressed the model boundary; accepted simple native stem retained as the practical optimum

Pipeline A status: not built

Pipeline B status: built; release quick artifact recorded

Pipeline C status: built; direct Y/UV fused stem with no RGB intermediate

Real model: Apple MobileNetV2 ImageNet integrated; unchanged 252-layer Core ML tail runs after the transformed 48-channel stem

PlaneFuse Live: not started

Known blockers: M7 has no second pretrained model; the reusable contract currently proves a second parameterized reference configuration, while MobileCLIP remains optional and must not jeopardize the MobileNetV2 core.

Next highest-leverage action: validate and expose the reusable native-stem configuration contract, then add inspect/compile/verify/bench developer commands.

Human decision currently required: no

Last milestone summary: M6 PASS — E005/E006 were rejected after end-to-end regressions; the 8x8 native stem remains the accepted implementation and no correctness threshold was changed.

Notes:
- Keep this file short.
- Update only when milestone, best result, blocker, or next action materially changes.
