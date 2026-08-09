# PlaneFuse status

Current milestone: R6 - Direct camera textures and continuous PlaneFuse Live (IN PROGRESS)

Overall status: PHASE 2 CAMERA INTEGRATION

Current branch: phase2/continuum

Current best verified result: pre-Phase-2 control — M4 fixture C end-to-end p50 0.1948 ms vs B 0.2328 ms; 16.34% lower under equal-submission methodology. Release-state MobileNetV2 C p50 was 50.8605 ms vs B 51.8460 ms; 1.90098% lower.

Correctness status: R5 PASS — exact nearest-sited polyphase parity and a rigorous documented negative latency result are verified; prior R0-R4 evidence remains intact

Pipeline A status: not built

Pipeline B status: built; release quick artifact recorded

Pipeline C status: built; direct Y/UV fused stem with no RGB intermediate

Real model: Apple MobileNetV2 ImageNet integrated; unchanged 252-layer Core ML tail runs after the transformed 48-channel stem

PlaneFuse Live: CLI sample and camera NV12 inference path built; physical camera run permission-qualified

Known blockers: R6 must replace the camera path's Swift Y/UV copies and CPU resize with retained CVMetalTextureCache plane textures, then demonstrate 300 continuous permitted-camera frames and capture screenshot/screen-recording artifacts. R3 Float16, R4 Metal 4, and R5 latency improvement were rejected or negative on their documented gates. Public push/submission remains human-controlled.

Next highest-leverage action: implement the R6 camera-plane texture bridge with explicit Core Video resource lifetime and a reusable frame ring, then parity-test it against the accepted one-frame camera path.

Human decision currently required: no; camera authorization may become a one-time R0 permission boundary.

Last milestone summary: R5 passed after two hostile review corrections: the exact compiler reduced generated UV instructions 9→4 and weighted multiplications 27→17, preserved independent Double/Metal parity, and recorded three corrected 200-pair batches (+0.23%, -0.64%, +0.39%) without a consistent e2e win. R2 remains the strongest accepted bridge result; R3 Float16 and R4 Metal 4 were rejected on documented quality/format gates.

Notes:
- Keep this file short.
- Update only when milestone, best result, blocker, or next action materially changes.
