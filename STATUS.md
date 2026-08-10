# PlaneFuse status

Current milestone: R6.1 - Release-grade live benchmark (IN PROGRESS; R6 camera-delivery gate passed)

Overall status: PHASE 2 CAMERA INTEGRATION

Current branch: phase2/continuum

Current best verified result: pre-Phase-2 control remains the accepted historical reference — M4 fixture C end-to-end p50 0.1948 ms vs B 0.2328 ms; 16.34% lower under equal-submission methodology. The successful R6 camera run is Debug technical-gate evidence only; no final camera speedup is accepted.

Correctness status: R5 PASS — exact nearest-sited polyphase parity and a rigorous documented negative latency result are verified; prior R0-R4 evidence remains intact

Pipeline A status: not built

Pipeline B status: built; release quick artifact recorded

Pipeline C status: built; direct Y/UV fused stem with no RGB intermediate

Real model: Apple MobileNetV2 ImageNet integrated; unchanged 252-layer Core ML tail runs after the transformed 48-channel stem

PlaneFuse Live: R6 GPU camera texture path built; permitted physical-camera 300-frame gate passed in the current Debug path; judge-facing UI and Release benchmark remain unfinished

Known blockers: release-grade camera evidence is still required: strongest B2 versus C1, alternating paired order, separate B-only/C-only throughput, true frame-delivery-to-result timing, p95/mean/MAD, dropped/late-frame counts, thermal metadata, and persisted JSON. R3 Float16, R4 Metal 4, and R5 latency improvement were rejected or negative on their documented gates. Public push/submission remains human-controlled.

Next highest-leverage action: implement `./pf bench camera` in Release with matched B2/C1 boundaries and defensible frame-delivery timing, then run the offline direct B2-shared versus C1-shared confirmation.

Human decision currently required: no for the active implementation path; publication, repository visibility, and submission remain human-controlled.

Last milestone summary: R5 passed after two hostile review corrections: the exact compiler reduced generated UV instructions 9→4 and weighted multiplications 27→17, preserved independent Double/Metal parity, and recorded three corrected 200-pair batches (+0.23%, -0.64%, +0.39%) without a consistent e2e win. R2 remains the strongest accepted bridge result; R3 Float16 and R4 Metal 4 were rejected on documented quality/format gates.

Notes:
- Keep this file short.
- Update only when milestone, best result, blocker, or next action materially changes.
