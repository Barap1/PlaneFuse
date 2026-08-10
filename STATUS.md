# PlaneFuse status

Current milestone: R6.1 - Release-grade live benchmark (IMPLEMENTED; result is qualified/inconclusive for competition-worthiness)

Overall status: PHASE 2 CAMERA INTEGRATION

Current branch: phase2/continuum

Current best verified result: pre-Phase-2 control remains the accepted historical reference — M4 fixture C end-to-end p50 0.1948 ms vs B 0.2328 ms; 16.34% lower under equal-submission methodology. The first committed Release camera benchmark at 93a7016 measured direct paired B2-C1 p50 difference 0.0460 ms / 3.8033% with median bootstrap CI [-0.0244, 0.1094] ms; because the CI crosses zero, no final camera speedup is accepted.

Correctness status: R5 PASS — exact nearest-sited polyphase parity and a rigorous documented negative latency result are verified; prior R0-R4 evidence remains intact

Pipeline A status: Release contextual benchmark built and measured; original image-input path is faster under its distinct input/model boundary

Pipeline B status: built; release quick artifact recorded

Pipeline C status: built; direct Y/UV fused stem with no RGB intermediate

Real model: Apple MobileNetV2 ImageNet integrated; unchanged 252-layer Core ML tail runs after the transformed 48-channel stem

PlaneFuse Live: Release replay/paired/live benchmark path built and run; judge-facing UI remains unfinished

Known blockers: direct B2/C1 is stable but below the competition target; Pipeline A is faster in its distinct framework-optimized image-input boundary and must remain visible in evaluation; the 64-input R7 corpus, profiler/go-no-go for camera-space fusion, and judge-facing UI remain. R3 Float16, R4 Metal 4, and R5 latency improvement were rejected or negative on their documented gates. Public push/submission remains human-controlled.

Next highest-leverage action: make the profiler-driven camera-space fusion go/no-go decision, then expand the quality corpus and run R7 adversarial evaluation without hiding Pipeline A.

Human decision currently required: no for the active implementation path; publication, repository visibility, and submission remain human-controlled.

Last milestone summary: R5 passed after two hostile review corrections: the exact compiler reduced generated UV instructions 9→4 and weighted multiplications 27→17, preserved independent Double/Metal parity, and recorded three corrected 200-pair batches (+0.23%, -0.64%, +0.39%) without a consistent e2e win. R2 remains the strongest accepted bridge result; R3 Float16 and R4 Metal 4 were rejected on documented quality/format gates.

Notes:
- Keep this file short.
- Update only when milestone, best result, blocker, or next action materially changes.
