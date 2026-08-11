VERDICT: RETHINK

Review ID: R7-FINAL-REPAIRED-20260811-02  
Review type: hostile technical acceptance and T1–T4 evaluation  
Reviewer role: sol_advisor_advisor  
Repository: PlaneFuse  
Head commit reviewed: `870fa7fe618067db467baf7b6a4e2a717c538dc0`  
Comparison/base commit: `40e5fd7a4f7359d5cf60229c884af1842d7dc785`  
Date UTC: `2026-08-11T14:09:32Z`  
Scope files: repaired review packet/response, architecture/specification/benchmark contracts, repair diff, B2/C1 production and profiler paths, raw paired records, quality/corpus evidence, selection matrix, Pipeline A, camera provenance, profiler export/privacy, T1–T4 evaluation, and read-only checkers  
Worktree: tracked and staged trees clean; acknowledged untracked raw traces and unrelated files remain. No files were changed and no build or benchmark was run.

Finding ID: F-001  
Severity: high  
Category: claim  
Evidence: `MILESTONES_V2.md:478-491` requires at least one competition-worthiness target and imposes a human hard stop otherwise. `SPEC_V2_ADDENDUM.md:149-160` preserves T1–T4. `proof/r7-competition-targets-repaired.json:19-64` records all four as false. T1 is 2.808866%, below 10%; T2 throughput is −0.079705% with worse camera latency; T3 frontend improvement is 13.919868%, not 2x, and end-to-end improvement is below 5%; no alternative result qualifies for T4.  
Risk: R7 cannot satisfy its final-selection gate, and presenting PlaneFuse as a competition-winning optimization would overstate the measured result.  
Required fix: Invoke the documented human hard stop and choose an explicit strategy: submit the honest sub-target research result, authorize a materially different branch/workload, or pivot. Preserve all thresholds and negative evidence.  
Closure evidence: A recorded human decision and corresponding claim/milestone strategy; alternatively, new preregistered evidence that genuinely meets T1, T2, T3, or independently accepted T4, followed by fresh hostile review.

Finding ID: F-004  
Severity: high  
Category: reproducibility  
Evidence: `proof/r7-b2-c1-shared-repaired-events.json:20-158,161-264,266-397` commits only nine sampled rows from each event table. Its encoder samples have no encoder labels and eight of nine rows are otherwise blank (`:163-262`). The claimed 50/164/50 totals and 25/25 path mapping are stored assertions at `:447-455`; the expected two-encoder B2 and one-encoder C1 structures at `:400-417` come from source metadata, not observed rows. `scripts/sanitize_r7_profiler_events.py:91-105` deliberately retains only the first six and last three rows, while `scripts/check_r7_shared_profiler.py:26-47` validates stored counts and expected-structure metadata rather than deriving the B2/C1 pattern from committed events.  
Risk: A clean-clone reviewer cannot attribute the captured events to 25 B2 two-encoder submissions and 25 C1 one-encoder submissions. The checker’s PASS therefore overstates what the durable profiler export proves.  
Required fix: Commit a privacy-safe resolved export from which the checker can derive the complete command-buffer/path mapping and 2:1 encoder structure. Resolve xctrace reference-compressed fields, retain sufficient labeled/signposted rows, hash the source XML exports, and make the checker recompute counts and ordering rather than trust metadata.  
Closure evidence: A committed export showing 25 attributable B2 submissions with two ordered encoders and 25 C1 submissions with one encoder, source-export hashes, clean exit binding, and negative tests that reject altered counts, missing labels, and incorrect encoder patterns.

Finding ID: F-007  
Severity: medium  
Category: reproducibility  
Evidence: `BENCHMARK_CONTRACT_V2.md:97-103` requires final evidence to include system, power, and thermal state; `BENCHMARK_CONTRACT.md:24-52` additionally requires stable-condition metadata including AC-power state and relevant Low Power Mode. `proof/r7-final-b2-c1-shared-repaired.json:3-9,1487-1489` records architecture, release configuration, OS/toolchain, and chip, but no power or thermal state.  
Risk: The 2.808866% result is small enough that unrecorded power or thermal conditions materially weaken exact final-run reproducibility, even though matched pairing and consistent batch results reduce fairness risk.  
Required fix: If this result is retained as final benchmark evidence, rerun the unchanged protocol while recording AC/battery state, Low Power Mode where available, and thermal state at batch start/end.  
Closure evidence: A regenerated five-process artifact containing those fields for every batch and a checker that fails when any required environmental state is absent.

Prior finding dispositions:

- F-002: closed. Five separate Release invocations, batch-local warmups, 5×200 raw records, 100/100 order balance per batch, both orders for all 64 sources, and deterministic recomputation were independently verified. The repaired latency result is technically credible as a descriptive sub-target measurement.
- F-003: closed. Production `executeCHW` and `execute` paths contain no profiler timing or GPU timestamp collection and share encoding helpers with separate profiler methods.
- F-005: closed for the current committed tree. The privacy checker passes, and `proof/profiler/RELEASE-PRIVACY-BLOCKER.md:1-16` correctly blocks publication of old private history pending human-approved sanitization or clean-history publication.
- F-006: closed. The checked A/B1/B2/C0/C1/C2/C3/C4 matrix supports B2 as the strongest credible matched conventional baseline and C1 as the strongest stable candidate. Pipeline A remains visibly faster under its distinct pre-rendered boundary.

Quality, corpus provenance, source-lineage qualification, camera provenance, disagreement retention, resource terminology, and threshold preservation are acceptable. The repaired B2/C1 performance and quality evidence is admissible as an honest sub-target result, but the complete R7 package is not technically closed because of F-004 and F-007. Independently, all four competition targets fail, requiring the strategic RETHINK verdict.
