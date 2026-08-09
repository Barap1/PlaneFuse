# PlaneFuse status

Current milestone: M6 - Novel 4:2:0/source-grid optimization round

Overall status: IN PROGRESS

Current branch: main (expected)

Current best verified result: MobileNetV2 C end-to-end p50 54.6994 ms vs B 56.6585 ms; 3.46% lower in post-commit confirmation batch 1

Correctness status: M5 PASS — MobileNetV2 native stem max activation error 9.059906e-6 <= 1e-5; 100% B/C top-1 agreement over 8 samples

Pipeline A status: not built

Pipeline B status: built; release quick artifact recorded

Pipeline C status: built; direct Y/UV fused stem with no RGB intermediate

Real model: Apple MobileNetV2 ImageNet integrated; unchanged 252-layer Core ML tail runs after the transformed 48-channel stem

PlaneFuse Live: not started

Known blockers: M6 must determine whether deeper 4:2:0/source-grid optimization beats the accepted MobileNetV2 baseline; no random tuning after three bounded experiments

Next highest-leverage action: run the first bounded M6 experiment on MobileNetV2 source-grid/chroma handling, starting from profiler/timing evidence rather than changing the accepted M5 path blindly.

Human decision currently required: no

Last milestone summary: M5 PASS — real Apple MobileNetV2 Conv/BN/ReLU6 stem transformation with unchanged Core ML tail, two post-commit equal-submission confirmations showing 2.11-3.46% C end-to-end p50 reduction, 61.90-66.47% isolated frontend reduction, 9.059906e-6 activation error, 100% output agreement, and zero C RGBA32Float intermediate bytes.

Notes:
- Keep this file short.
- Update only when milestone, best result, blocker, or next action materially changes.
