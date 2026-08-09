# PlaneFuse status

Current milestone: M6 - Novel 4:2:0/source-grid optimization round

Overall status: IN PROGRESS

Current branch: main (expected)

Current best verified result: M4 fixture C end-to-end p50 0.1948 ms vs B 0.2328 ms; 16.34% lower under equal-submission methodology

Correctness status: M5 PASS — real four-image corpus, original-derived Core ML stem/full-model checks, exact tail provenance, and two 100-iteration confirmations pass

Pipeline A status: not built

Pipeline B status: built; release quick artifact recorded

Pipeline C status: built; direct Y/UV fused stem with no RGB intermediate

Real model: Apple MobileNetV2 ImageNet integrated; unchanged 252-layer Core ML tail runs after the transformed 48-channel stem

PlaneFuse Live: not started

Known blockers: M6 has no accepted optimization yet; retain the simpler native stem if bounded 4:2:0 experiments do not improve it. MobileCLIP remains deferred until the proven core is secure.

Next highest-leverage action: inspect M5 profiler evidence, run at most three bounded 4:2:0/source-grid hypotheses, and preserve a measured plateau conclusion if none improves the accepted result

Human decision currently required: no

Last milestone summary: M5 PASS — corrected bottom/right-heavy SAME padding, real hashed CC0 corpus, independent CPU-only Core ML StemArray/FullArray checks, exact tail lineage, and two 100-iteration confirmations at commit b8b7850.

Notes:
- Keep this file short.
- Update only when milestone, best result, blocker, or next action materially changes.
