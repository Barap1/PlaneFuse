VERDICT: RETHINK

Review ID: `R7-FINAL-20260811-01`  
Review type: hostile technical acceptance and T1–T4 evaluation  
Reviewer role: `sol_advisor_advisor` review protocol; native delegated role binding was unavailable, so no delegated isolation is claimed  
Repository: `PlaneFuse`  
Head commit reviewed: `1710ee606f39da701c384fe2d91e7b3d86041195`  
Comparison/base commit: `72457c7686be1a348be2f66a38b3c3c88f513775`  
Date UTC: `2026-08-11T04:45:53Z`  
Scope files: R7 packet, review/spec/benchmark contracts, R7 implementation symbols, authoritative JSON evidence, camera provenance, profiler exports/checker, Git tree/diff  
Worktree: tracked tree clean; packet is a docs-only descendant of the evidence head. The raw profiler bundle and three unrelated files are untracked. No files were changed and no build or benchmark was run.

Finding ID: F-001  
Severity: high  
Category: claim  
Evidence: `MILESTONES_V2.md:478-491` requires one competition-worthiness target and invokes the hard stop otherwise. `proof/r7-competition-targets.json:targets` records T1–T4 as false/pending.  
Risk: R7 cannot satisfy its acceptance gate. The current claim strategy needs a human decision or materially different measured result; T4 has no comparably strong evidence.  
Required fix: Preserve the thresholds and choose a hard-stop path with explicit human approval: submit the honest sub-target result, pursue an approved new branch/workload, or pivot. Alternatively, produce new preregistered evidence that genuinely meets T1, T2, T3, or T4.  
Closure evidence: Human-approved hard-stop decision or a new authoritative target artifact, followed by a fresh independent `VERDICT: SHIP`.

Finding ID: F-002  
Severity: high  
Category: fairness  
Evidence: `proof/reviews/R7-REVIEW-PACKET.md:34` claims five independent batches with 20 warmups per batch. `Sources/PlaneFuseCore/MobileNetV2DirectSharedBenchmark.swift:209-218` performs warmups once; `:226-255` divides one continuous run into five labels. At `:231-233`, both frame identity and execution order derive from global-pair parity. Inspection of `proof/r7-final-b2-c1-shared-current.json:measurement.raw_paired_records` shows every sample appears in only one execution order. The preregistered camera protocol instead warms each batch and rotates order at `Sources/PlaneFuseLive/main.swift:895-923`.  
Risk: The five labels are not independent runs, and sample identity is confounded with first/second execution order. The hierarchical bootstrap’s positive interval is therefore not supported by the stated protocol. The 2.5013% marginal-p50 result remains descriptive but does not cure this defect.  
Required fix: Run genuinely separated batches with per-batch warmups and batch-boundary order rotation so repeated samples occur in both orders; record the independence mechanism. Regenerate performance, target, ledger, and packet evidence without weakening thresholds.  
Closure evidence: A current-source 5×200 artifact plus a checker proving per-batch warmups, 100/100 order balance, both orders per repeated sample, recomputed statistics, and a fresh independent review.

Finding ID: F-003  
Severity: medium  
Category: reproducibility  
Evidence: The authoritative performance artifact records commit `8f9e98dd…`. Current `Sources/PlaneFuseCore/MetalMobileNetV2RGBPipeline.swift:80-102` makes production `executeCHW` delegate to the profiling method, adding uptime and GPU-timestamp collection. `git diff 8f9e98d..HEAD -- Sources/PlaneFuseCore/MetalMobileNetV2RGBPipeline.swift` confirms this post-artifact change, while `proof/reviews/R7-REVIEW-PACKET.md:74` says profiling did not alter the performance implementation.  
Risk: The benchmark is reproducible at its pinned commit, but it no longer measures the exact current implementation described by the packet. The added B2-side work cannot be inferred to preserve current-tree timing.  
Required fix: Isolate profiling instrumentation from production execution or rerun the final benchmark on the intended current implementation. Correct the packet’s equivalence statement.  
Closure evidence: Either a source diff proving production execution is unchanged by profiling or a new clean-source artifact whose generation commit contains the reviewed implementation.

Finding ID: F-004  
Severity: high  
Category: reproducibility  
Evidence: `proof/profiler/r7-b2-c1-shared-command-buffers.xml:1-3` contains only a table schema and no command-buffer event rows. `proof/profiler/r7-b2-c1-shared-toc.xml:7-18` records exit status 9/SIGKILL at the time limit. `scripts/check_r7_shared_profiler.py:57-74` checks JSON counts, file existence, and strings but never verifies trace event rows, B2/C1 encoder patterns, workload completion, or trace-to-commit binding. The 261 MB raw trace is local and untracked.  
Risk: A clean-clone reviewer cannot verify the required strongest-B/C Metal capture. The checker would accept a schema-only export, so the claimed durable trace evidence is insufficient even though source and JSON support the resource accounting.  
Required fix: Commit a bounded, sanitized export containing actual PlaneFuse GPU/command-buffer rows—preferably labeled B2/C1 with the expected two-encoder versus one-encoder structure—and strengthen the checker to reject empty/schema-only exports. Qualify the time-limit termination or capture a cleanly terminating run.  
Closure evidence: Hashed event-row export, nonzero expected event counts, checker negative test for an empty export, exact capture command/environment/commit, and re-review.

Finding ID: F-005  
Severity: medium  
Category: safety  
Evidence: `proof/profiler/r7-b2-c1-shared-toc.xml:7` contains a user-chosen device name and hardware UUID; `:41-98` exposes the local process/application inventory.  
Risk: Publishing or pushing this proof leaks persistent machine identity and local application information, contrary to repository policy.  
Required fix: Replace it with a minimal sanitized profiler export retaining only technically relevant environment and trace metadata.  
Closure evidence: A privacy check demonstrating removal of device names, UUIDs, PIDs, and unrelated process inventory.

Finding ID: F-006  
Severity: medium  
Category: scope  
Evidence: `MILESTONES_V2.md:464-476` requires a complete A/B1/B2/C0/C1/C2/C3/C4 matrix. `proof/reviews/R7-REVIEW-PACKET.md:22-45,108-117` documents B2/C1, Pipeline A, and selected negative experiments but does not provide the required row-by-row final matrix, notably omitting explicit B1/C0 disposition.  
Risk: Strongest-baseline selection and the status of every implemented candidate cannot be audited from one authoritative R7 selection record.  
Required fix: Add a final matrix listing each row’s implementation status, boundary, precision, tail, bridge class, authoritative artifact, result, and rejection/selection reason. Existing valid evidence may be referenced.  
Closure evidence: Checked matrix covering every required row and identifying the strongest comparable B and C without cherry-picking.

Competition targets:

- T1: false. C1’s marginal-p50 improvement is `2.5013%`, not `≥10%`; the paired CI also has the F-002 protocol defect.
- T2: false. Historical throughput changed by `−0.0797%`; C1 frame-delivery p50 was `21.82%` higher/worse. The fresh zero-callback attempt yields no inference.
- T3: false. Zero RGB and zero element-population copy pass, but camera frontend reduction is `15.03%`, profiler GPU frontend is only about `1.275×`, and end-to-end improvement is `2.5013%`, below `5%`.
- T4: false. No alternative result is comparably strong and hostile-review acceptable.

The old component profile is correctly excluded, B2 materialized-RGB/C1 no-RGB and persistent handoff are source-supported, camera provenance is appropriately historical, the zero-callback failure is preserved without inference, source-lineage divergence is separately qualified, quality disagreements remain visible, and Pipeline A and negative results are represented fairly. Those strengths do not overcome the hard stop or the benchmark/profiler evidence defects.
