# PlaneFuse status

Current milestone: M10 - Evidence and submission package

Overall status: IN PROGRESS

Current branch: main (expected)

Current best verified result: M4 fixture C end-to-end p50 0.1948 ms vs B 0.2328 ms; 16.34% lower under equal-submission methodology

Correctness status: M9 PASS (environment-qualified) — local sample inference is validated; camera NV12 capture/resize/B-C inference builds and reports honestly, but this machine denied camera access

Pipeline A status: not built

Pipeline B status: built; release quick artifact recorded

Pipeline C status: built; direct Y/UV fused stem with no RGB intermediate

Real model: Apple MobileNetV2 ImageNet integrated; unchanged 252-layer Core ML tail runs after the transformed 48-channel stem

PlaneFuse Live: not started

Known blockers: A permitted physical camera run and polished video capture remain outstanding; no privacy setting will be changed autonomously. The MobileNetV2 core is proven; MobileCLIP remains optional.

Next highest-leverage action: assemble final benchmark/profiler/system evidence, audit every public claim, and prepare clean-clone release instructions.

Human decision currently required: no

Last milestone summary: M9 PASS (qualified) — `planefuse-live --sample` runs real local B/C inference; `--camera` captures native NV12, resizes without RGB, and runs measured B/C inference when permission/assets are available.

Notes:
- Keep this file short.
- Update only when milestone, best result, blocker, or next action materially changes.
