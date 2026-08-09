# PlaneFuse status

Current milestone: M9 - PlaneFuse Live showcase

Overall status: IN PROGRESS

Current branch: main (expected)

Current best verified result: M4 fixture C end-to-end p50 0.1948 ms vs B 0.2328 ms; 16.34% lower under equal-submission methodology

Correctness status: M8 PASS — inspect/compile/verify/bench commands are reproducible, JSON-backed, and honest about missing model assets

Pipeline A status: not built

Pipeline B status: built; release quick artifact recorded

Pipeline C status: built; direct Y/UV fused stem with no RGB intermediate

Real model: Apple MobileNetV2 ImageNet integrated; unchanged 252-layer Core ML tail runs after the transformed 48-channel stem

PlaneFuse Live: not started

Known blockers: M9 camera shell and task UI are not started. The MobileNetV2 local workload is proven; MobileCLIP remains optional and must not jeopardize that core.

Next highest-leverage action: build a local macOS camera/frame showcase that uses the real MobileNetV2 path and displays only measured runtime state.

Human decision currently required: no

Last milestone summary: M8 PASS — `./pf inspect`, `compile`, `verify`, and `bench` expose the supported example without manual source edits; unsupported/missing state is explicit.

Notes:
- Keep this file short.
- Update only when milestone, best result, blocker, or next action materially changes.
