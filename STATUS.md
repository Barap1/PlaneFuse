# PlaneFuse status

Current milestone: R7.5 - same-workload source-reuse fallback under independent review (R6.5 accepted negative)

Overall status: PHASE 2 R7 evidence repair complete; repaired R7 hostile review preserved the F-001 hard stop; R7.5 source-reuse confirmation is complete and technically promising, pending fresh independent review

Current branch: phase2/continuum

Current real-model result: authoritative R7.5 confirmation at `52db138` measures B2 p50 1.737875 ms, accepted C1 p50 1.633458 ms, and C1-SR p50 1.532583 ms over five independent 240-triple Release processes. C1-SR is 6.1755% lower than C1 and 11.8128% lower than B2; paired C1-minus-C1-SR median bootstrap CI is [0.091125, 0.101750] ms. Full 64-sample quality is top-1/top-5 set/top-5 ranking 1.0 and activation max error 5.960464e-6. This is promising evidence, not an accepted competition claim until fresh hostile review. The repaired R7 B2/C1 result remains 2.115766% below the original ≥10% target. Pipeline A remains contextual at p50 1.1483 ms under its distinct pre-rendered image-input boundary. R6.5 remains negative.

Correctness status: Condition-complete repaired R7 B2/C1 quality gates pass on 32 real plus 32 procedural samples; two real-image top-5 disagreements remain retained and recorded. The profiler repair now preserves observed B2/C1 command and encoder labels, command-buffer/GPU submission joins, source hashes, and clean workload completion. R6.5 remains accepted as a bounded negative experiment after SHIP review; prior R0-R5 evidence remains intact.

Pipeline A status: Release contextual benchmark built and measured; original image-input path is faster under its distinct input/model boundary

Pipeline B status: built; release quick artifact recorded

Pipeline C status: accepted C1 retained for R7; direct camera-space fusion was measured and rejected as slower

Real model: Apple MobileNetV2 ImageNet integrated; unchanged 252-layer Core ML tail runs after the transformed 48-channel stem

PlaneFuse Live: Release replay/paired/live benchmark path built and previously completed successfully; a fresh R7 physical-camera invocation received zero callbacks before timeout, so no new camera result is inferred. Judge-facing UI remains unfinished

Known blockers: R7 remains formally unaccepted because its four preregistered targets were false/pending at the repaired evidence gate. The authorized one-shot R7.5 source-reuse experiment is now complete, including permitted confirmation, and must receive fresh independent hostile review before any acceptance or target claim. The profiler privacy publication blocker remains. Public push/submission remains human-controlled.

Next highest-leverage action: obtain a fresh behaviorally read-only Sol review of the repaired R7 packet plus the R7.5 confirmation artifact; if valid and SHIP, freeze performance research and proceed to R8/R9.

Human decision currently required: after fresh Sol review, decide only the contract-defined next step. Publication, repository visibility, video upload, history rewrite, and submission remain human-controlled.

Last milestone summary: R5 passed after two hostile review corrections: the exact compiler reduced generated UV instructions 9→4 and weighted multiplications 27→17, preserved independent Double/Metal parity, and recorded three corrected 200-pair batches (+0.23%, -0.64%, +0.39%) without a consistent e2e win. R2 remains the strongest accepted bridge result; R3 Float16 and R4 Metal 4 were rejected on documented quality/format gates.

Notes:
- Keep this file short.
- Update only when milestone, best result, blocker, or next action materially changes.
