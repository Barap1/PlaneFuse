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

PlaneFuse Live: R6 GPU camera texture path built; 300-frame physical-camera gate not accepted

Known blockers: the R6 implementation is built, but three post-fix camera invocations timed out before receiving a frame. Hardware is present, but the local capture session is not currently delivering frames; restore the permitted camera stream, then rerun the 300-frame gate and capture screenshot/screen-recording artifacts. R3 Float16, R4 Metal 4, and R5 latency improvement were rejected or negative on their documented gates. Public push/submission remains human-controlled.

Next highest-leverage action: after the camera stream is restored, rerun `./pf live --camera`; it will validate retained CVMetalTextureCache planes, GPU resize, persistent B/C resources, parity, and 300 frames.

Human decision currently required: yes — restore/allow the local camera capture stream if another process or macOS privacy/session state is holding it; no code-signing or publication approval is requested.

Last milestone summary: R5 passed after two hostile review corrections: the exact compiler reduced generated UV instructions 9→4 and weighted multiplications 27→17, preserved independent Double/Metal parity, and recorded three corrected 200-pair batches (+0.23%, -0.64%, +0.39%) without a consistent e2e win. R2 remains the strongest accepted bridge result; R3 Float16 and R4 Metal 4 were rejected on documented quality/format gates.

Notes:
- Keep this file short.
- Update only when milestone, best result, blocker, or next action materially changes.
