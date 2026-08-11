VERDICT: RETHINK

Review ID: R7-F004-REPAIRED-4-COMPACT-HOSTILE-20260811  
Review type: behaviorally read-only hostile closure review  
Reviewer role: sol_advisor_advisor  
Head commit reviewed: `075d38a07af1957fb018b5cbf09124aac3281eab`  
Comparison/base commit: `4c756798e2ac28b3d8c6591038417fb5aa9abfc4`  
Repair commit: `3a2709602bf4eff680c30157855176a7018f0190`  
Generating commit: `b6285f2eb6b9329f925cde81db5936f5f2a8de98`  
Date UTC: `2026-08-11T15:14:58Z`

Finding ID: F-001  
Severity: high  
Category: claim  
Evidence: `SPEC_V2_ADDENDUM.md:155-160`; `MILESTONES_V2.md:486-491`; `proof/r7-competition-targets-repaired-conditions.json:26-64`. T1 is `2.115766%`, not 10%; T2 and T3 are false; T4 is pending/false. The target checker passed without threshold reinterpretation.  
Risk: R7 does not satisfy the preregistered competition-worthiness gate. Accepting R7 or presenting it as a winning optimization would invalidate the central claim.  
Required fix: Preserve the hard stop and obtain the documented human strategy decision: submit the honest sub-target result, authorize a preregistered alternative workload/branch, pursue the optional beta branch, or pivot.  
Closure evidence: Recorded human decision, or new evidence genuinely passing T1–T4 followed by hostile review.

Finding ID: F-004  
Severity: high  
Category: reproducibility  
Evidence: `proof/reviews/R7-REVIEW-PACKET-REPAIRED-4.md:31` and `proof/reviews/R7-FINAL-REPAIRED-20260811-04-HOSTILE-RESPONSE.md:17-19` overclaim closure:

- `scripts/check_r7_shared_profiler.py:140-150` gives the schema-only fixture `sha256(b"{}")`, not the canonical hash of its payload. Independent execution confirmed it passes its negative test only through `event export canonical hash mismatch`.
- `scripts/check_r7_shared_profiler.py:51-52` validates observed event counts but never requires canonical workload values `warmup_iterations=5` and `measured_iterations=20`. A rehashed `999/999` mutation was accepted.
- `scripts/check_r7_shared_profiler.py:60` explicitly permits `encoder_count=None`; a rehashed all-null mutation was accepted despite the claimed canonical value being exactly `1`.
- `scripts/check_r7_shared_profiler.py:93-107` does not bind each invocation’s recorded GPU submission IDs to its command’s mappings or enforce a one-to-one command/submission relation. A cardinality-preserving cross-command swap of mapped GPU submission IDs was accepted.
- `scripts/check_r7_shared_profiler.py:159-166` accepts any non-hash `SystemExit`, rather than asserting the intended rejection. The purported broken-join fixture at line 187 truncates the mapping table and therefore fails cardinality before exercising join validation.

Risk: The committed export is internally valid, but the advertised fail-closed and negative-test guarantees remain false. Cardinality-preserving corruption of load-bearing attribution can pass, weakening reproducibility and profiler claims.

Required fix: Require exact `5/20` workload counts and `encoder_count == 1`; bind every invocation’s submission IDs to its command’s mapping rows; enforce unique mapped GPU submissions across commands; rehash the schema fixture; and make each negative test assert the intended semantic rejection. Add cardinality-preserving broken-join, null-encoder, wrong-workload, and order-preserving-count mutations.

Closure evidence: The positive checker must pass, while independently rehashed tests reject schema-only, truncation, wrong path/order, wrong cardinality, cardinality-preserving broken joins, fake source hash, wrong commit, null/incorrect encoder count, wrong workload counts, and blank/generic rows for their intended reasons, followed by fresh hostile review.

Verified without additional findings: the current export itself has exact `50/100/50/100` rows, workload `5/20`, alternating `25 B2/25 C1`, two mappings per command, one mapped GPU submission with two execution points per command, canonical encoder count `1`, observed encoder structures, fixed source-export hashes, clean exit, and matching profile/export commit. File SHA-256 `96c7e43…36826` and canonical hash `eb50f16e…633300` recompute correctly. Production instrumentation separation, five-batch fairness/conditions, quality and both retained disagreements, Pipeline A qualification, source lineage, historical camera provenance, committed-export privacy, A/B/C matrix, and fixed T1–T4 thresholds showed no regression.
