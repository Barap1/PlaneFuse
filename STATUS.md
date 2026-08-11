# PlaneFuse status

Current milestone: R7 - final adversarial evaluation (R6.5 accepted negative; C1 retained)

Overall status: PHASE 2 R7 evidence repair complete; final compact hostile review complete; R7.5 preparation authorized

Current branch: phase2/continuum

Current real-model result: condition-complete repaired R7 direct Release B2-shared p50 1.595167 ms versus C1-shared 1.561417 ms over 64 samples and five genuinely separate 200-pair processes; the marginal-p50 difference is 0.033750 ms and C1 is 2.115766% lower. The median paired difference and deterministic bootstrap CI are in `proof/r7-final-b2-c1-shared-repaired-conditions.json`. This remains below the ≥10% competition target and is pending fresh hostile re-review. Prior 2.5013%, 2.808866%, and conditionless artifacts remain preserved as historical/superseded. Pipeline A remains faster contextually at p50 1.1483 ms under its distinct pre-rendered image-input boundary. R6.5 remains negative.

Correctness status: Condition-complete repaired R7 B2/C1 quality gates pass on 32 real plus 32 procedural samples; two real-image top-5 disagreements remain retained and recorded. The profiler repair now preserves observed B2/C1 command and encoder labels, command-buffer/GPU submission joins, source hashes, and clean workload completion. R6.5 remains accepted as a bounded negative experiment after SHIP review; prior R0-R5 evidence remains intact.

Pipeline A status: Release contextual benchmark built and measured; original image-input path is faster under its distinct input/model boundary

Pipeline B status: built; release quick artifact recorded

Pipeline C status: accepted C1 retained for R7; direct camera-space fusion was measured and rejected as slower

Real model: Apple MobileNetV2 ImageNet integrated; unchanged 252-layer Core ML tail runs after the transformed 48-channel stem

PlaneFuse Live: Release replay/paired/live benchmark path built and previously completed successfully; a fresh R7 physical-camera invocation received zero callbacks before timeout, so no new camera result is inferred. Judge-facing UI remains unfinished

Known blockers: final compact hostile review `R7-F004-REPAIRED-5-COMPACT-HOSTILE-20260811` verified F-004 closure but returned RETHINK for the valid F-001 strategic hard stop: all four condition-complete R7 competition targets are false/pending. Per the human authorization, exactly one same-workload R7.5 source-reuse investigation may now be prepared, subject to profiler confirmation, architecture review, preregistration, and the strict one-experiment budget. Do not claim R7 acceptance or a win. The profiler privacy publication blocker remains. Public push/submission remains human-controlled.

Next highest-leverage action: confirm the R7.5 source-reuse hypothesis from repaired profiler evidence and have the high-complexity worker derive its execution schedule; no implementation or benchmark until that design/pre-registration gate is complete.

Human decision currently required: after fresh Sol review, decide only the contract-defined next step. Publication, repository visibility, video upload, history rewrite, and submission remain human-controlled.

Last milestone summary: R5 passed after two hostile review corrections: the exact compiler reduced generated UV instructions 9→4 and weighted multiplications 27→17, preserved independent Double/Metal parity, and recorded three corrected 200-pair batches (+0.23%, -0.64%, +0.39%) without a consistent e2e win. R2 remains the strongest accepted bridge result; R3 Float16 and R4 Metal 4 were rejected on documented quality/format gates.

Notes:
- Keep this file short.
- Update only when milestone, best result, blocker, or next action materially changes.
