VERDICT: RETHINK

Review ID: R7-FINAL-REPAIRED-20260811-03-HOSTILE  
Review type: fresh hostile technical re-review and T1–T4 evaluation  
Reviewer role: sol_advisor_advisor  
Repository: PlaneFuse  
Head commit reviewed: `7abbedaf9605ed58d5978e8c1d812e04d583ab6e`  
Comparison/base commit: `870fa7fe618067db467baf7b6a4e2a717c538dc0`  
Date UTC: `2026-08-11T14:39:48Z`  
Scope files: review contract and repaired packet/response; Phase 2 specification and benchmark contracts; repair diff; B2/C1 benchmark, quality, profiler, corpus and source-lineage evidence; A/B/C selection matrix; Pipeline A; camera provenance; privacy controls; T1–T4 evaluation; production/profiler source paths and read-only checkers.  
Worktree: tracked tree clean. Untracked raw profiler trace and unrelated files exist and were not treated as durable closure evidence. No files were changed, and no build or benchmark was run.

Finding ID: F-001  
Severity: high  
Category: claim  
Evidence: `SPEC_V2_ADDENDUM.md:149-160` requires at least one unchanged competition-worthiness target. `MILESTONES_V2.md:478-491` requires final selection to meet one target and imposes a human hard stop otherwise. `proof/r7-competition-targets-repaired-conditions.json:19-64` records T1–T4 false: T1 is 2.115766%, below 10%; T2 throughput changes by −0.079705% and camera latency worsens; T3 frontend improves 13.919868%, not 2x, while end-to-end improves only 2.115766%, below 5%; T4 has no independently accepted equivalent result. The read-only target checker passed without reinterpretation.  
Risk: PlaneFuse has no competition-worthiness result under its preregistered criteria. Proceeding as though R7 established a winning optimization would invalidate the project’s central claim strategy.  
Required fix: Invoke the documented human hard stop and record an explicit strategy decision: submit the honest sub-target research result, authorize a materially different branch/workload, pursue the optional beta branch, or pivot. Preserve all thresholds and negative evidence.  
Closure evidence: A recorded human strategy decision and corresponding milestone/claim disposition; alternatively, new preregistered evidence genuinely meeting T1, T2, T3, or independently accepted T4, followed by fresh hostile review.

Finding ID: F-004  
Severity: high  
Category: reproducibility  
Evidence: Production source creates two ordered B2 encoders at `Sources/PlaneFuseCore/MetalMobileNetV2RGBPipeline.swift:92-101`, versus one C1 encoder at `Sources/PlaneFuseCore/MetalMobileNetV2NativeStem.swift:89-96`. However, `proof/profiler/r7-b2-c1-shared-repaired-events-full.json:21-417` reports `encoder_count: 1` for every command row; its encoder table has only 50 generic `Compute Command 0` rows at `:427-780`, rather than an observed B2 two-encoder/C1 one-encoder pattern. Its 164 GPU rows carry zero timestamps and submission IDs. The claimed path join is stored at `:1828`, while observed counts appear at `:2407-2409`. `scripts/sanitize_r7_profiler_events.py:120-137` assigns B2/C1 and source labels solely from array parity and maps one encoder row to every invocation. `scripts/check_r7_shared_profiler.py:32-56` checks lengths and this generated attribution metadata, not row content or observed path identity. A targeted in-memory negative test replaced every committed event row with `{}`, recomputed the canonical hash, and `validate_event_export` still passed. `CLAIMS.md:311` therefore overstates the artifact as complete row-level attribution.  
Risk: A clean-clone reviewer cannot derive which observed submissions are B2 or C1, verify B2’s two ordered encoders, or bind the GPU rows to either path. The durable profiler evidence does not satisfy the accelerator-attribution claim, despite the checker reporting PASS.  
Required fix: Produce a privacy-safe export containing observed path-identifying signposts/labels or a defensible timestamp/frame join, plus observed encoder relationships that demonstrate 25 B2 submissions with two ordered encoders and 25 C1 submissions with one encoder. Preserve meaningful timestamps/IDs or document and validate equivalent trace semantics. Make the checker derive attribution from those observed fields and reject blank, generic-only, duplicated, unjoined, or wrong-encoder-pattern rows. Remove the current “complete row-level attribution” claim until this succeeds.  
Closure evidence: A committed resolved export and checker that independently reconstruct all 50 path identities and the B2/C1 encoder structure from observed data; negative tests must reject empty-content rows, missing path labels/signposts, broken joins, altered ordering, and incorrect encoder cardinality. Follow with fresh hostile review.

Verified closure and scope checks:

- F-007 is closed for the benchmark contract: all five raw batch artifacts contain AC/battery state, Low Power Mode, and thermal state at start and end; every value is `AC Power`, `0`, and `nominal`, and aggregate copies match the raw records. The benchmark checker independently recomputed 1,000 records, order balance, statistics, and bootstrap CI. AC/Low Power Mode were sampled once by `scripts/run_r7_repaired_shared_batches.sh:20-33` and injected into each process; thermal state was sampled at each process boundary.
- Fairness is supported: B2/C1 share the same 64 inputs, Float32 activation shape/layout, persistent buffer-backed bridge, `.all` Core ML tail, timing boundary, and balanced execution order (`MobileNetV2DirectSharedBatchBenchmark.swift:142-220,306-317`).
- Quality passes unchanged thresholds: activation maximum error `8.583068e-6 ≤ 1e-5`, top-1 `1.0`, top-5 set `0.984375`, top-5 ranking `0.96875`; both retained real-image disagreements remain recorded.
- B2 is the strongest credible matched B and C1 the strongest stable C. C2 remains quality-rejected, C3 stable-toolchain-infeasible, C4 has no stable end-to-end win, and R6.5 is slower.
- Pipeline A remains visible at p50 `1.148292 ms` under its distinct pre-rendered image-input boundary and is not substituted for B2.
- Camera evidence is correctly qualified as historical; the fresh R7 attempt received zero callbacks and contributes no inferred performance result.
- Current committed profiler exports pass the privacy checker. Existing private-history publication remains blocked by `proof/profiler/RELEASE-PRIVACY-BLOCKER.md`.
- The authoritative performance artifact was generated at `b6285f2eb6b9329f925cde81db5936f5f2a8de98`; there are no production-source changes from that commit to the review head.
