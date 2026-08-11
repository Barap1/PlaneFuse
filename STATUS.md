# PlaneFuse status

Current milestone: Release hardening - product polish, repository hygiene, and submission preparation (performance frozen)

Overall status: R7.5 evidence independently accepted for technical progression; performance research frozen; release hardening in progress

Current branch: phase2/continuum

Current real-model result: authoritative R7.5 confirmation at `52db138` measures B2 p50 1.737875 ms, accepted C1 p50 1.633458 ms, and C1-SR p50 1.532583 ms over five independent 240-triple Release processes. C1-SR is 6.1755% lower than C1 and 11.8128% lower than B2; paired B2-minus-C1-SR median bootstrap CI is [0.180250, 0.198792] ms. Full 64-sample quality is top-1/top-5 set/top-5 ranking 1.0 and activation max error 5.960464e-6. Independent hostile review returned SHIP with no findings; T1 passed. The repaired R7 B2/C1 result remains 2.115766% below the original ≥10% target. Pipeline A remains contextual at p50 1.1483 ms under its distinct pre-rendered image-input boundary. R6.5 remains negative.

Correctness status: Condition-complete repaired R7 B2/C1 quality gates pass on 32 real plus 32 procedural samples; two real-image top-5 disagreements remain retained and recorded. The profiler repair now preserves observed B2/C1 command and encoder labels, command-buffer/GPU submission joins, source hashes, and clean workload completion. R6.5 remains accepted as a bounded negative experiment after SHIP review; prior R0-R5 evidence remains intact.

Pipeline A status: Release contextual benchmark built and measured; original image-input path is faster under its distinct input/model boundary

Pipeline B status: built; release quick artifact recorded

Pipeline C status: accepted C1 retained for R7; direct camera-space fusion was measured and rejected as slower

Real model: Apple MobileNetV2 ImageNet integrated; unchanged 252-layer Core ML tail runs after the transformed 48-channel stem

PlaneFuse Live: judge-facing AppKit dashboard runs at `./pf live --app` in Release mode; it separates LIVE camera/runtime values from STORED evidence, labels comparison-loop FPS and post-resize timing precisely, and reports camera unavailability without inference. A fresh R7 physical-camera invocation received zero callbacks before timeout, so no new camera result is inferred. Human-permitted final camera/video capture remains open.

Known blockers: T2/T3 remain not met or established; T4 was not invoked. R7.5 T1 is accepted as the measured same-workload target result in the independent SHIP review, not as a universal speedup claim. Finish release documentation, final app QA, and publication preparation. The profiler privacy publication blocker remains. Public push/submission remains human-controlled.

Next highest-leverage action: run the final local app smoke/visual inspection, then capture approved screenshots/video and make the human publication decisions. No new performance experiments are authorized.

Human decision currently required: choose the privacy-safe public-history strategy and approve publication only after final local QA. Repository visibility, default branch, video upload, and submission remain human-controlled.

Last milestone summary: R5 passed after two hostile review corrections: the exact compiler reduced generated UV instructions 9→4 and weighted multiplications 27→17, preserved independent Double/Metal parity, and recorded three corrected 200-pair batches (+0.23%, -0.64%, +0.39%) without a consistent e2e win. R2 remains the strongest accepted bridge result; R3 Float16 and R4 Metal 4 were rejected on documented quality/format gates.

Notes:
- Keep this file short.
- Update only when milestone, best result, blocker, or next action materially changes.
