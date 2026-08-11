VERDICT: RETHINK

Review ID: R7-FINAL-REPAIRED-20260811-04-HOSTILE  
Review type: independent hostile closure review  
Reviewer role: sol_advisor_advisor  
Repository: `<repository-root>`
Head commit reviewed: `4c756798e2ac28b3d8c6591038417fb5aa9abfc4`  
Comparison/base commit: `e5a3cc195cee660045bd7d0616af6f801dd3e2b3`  
Generating commit verified: `b6285f2eb6b9329f925cde81db5936f5f2a8de98`  
Date UTC: `2026-08-11T15:02:24Z`  
Scope files: repaired R7 packet; review response; profiler source/export/checkers; production B2/C1 paths; five raw benchmark batches; quality, source-lineage, Pipeline A, camera, privacy, matrix, and T1–T4 artifacts.  
Isolation: behaviorally read-only. No files, builds, benchmarks, logs, or caches were created. Native Sol binding was unavailable because its companion-profile exactness check reported both reviewer/implementer profiles missing; no model or enforced read-only claim is made.

Finding ID: F-001  
Severity: high  
Category: claim  
Evidence: `SPEC_V2_ADDENDUM.md:149-161` requires one competition-worthiness target; `MILESTONES_V2.md:482-491` imposes a human hard stop otherwise. `proof/r7-competition-targets-repaired-conditions.json:19-65` records T1–T4 false: T1 is `2.115766%`, below 10%; T2 throughput is `-0.079705%` with worse C1 frame-delivery p50; T3 is only `13.919868%` frontend and `2.115766%` end-to-end, below 2x and 5%; T4 has no independently accepted equivalent result. The target checker passed without threshold reinterpretation.  
Risk: R7 establishes a reproducible positive but sub-target C1 result, not a competition-worthy optimization under the preregistered claim strategy. Treating R7 as accepted or “winning” would invalidate the central claim.  
Required fix: Invoke the documented human hard stop and record one explicit strategy decision: submit the honest sub-target research result, authorize a materially different preregistered branch/workload, pursue the optional beta branch, or pivot. Preserve all thresholds and negative evidence.  
Closure evidence: Recorded human decision and corresponding milestone/claims disposition; alternatively, new preregistered evidence genuinely passing T1, T2, T3, or independently accepted T4, followed by fresh hostile review.

Finding ID: F-004  
Severity: high  
Category: reproducibility  
Evidence: The committed profiler artifact itself contains the claimed 50 command rows, 50 encoder rows, 100 nonzero GPU rows, and 100 mapping rows, with observed B2/C1 labels and command-buffer joins at `proof/profiler/r7-b2-c1-shared-repaired-events-full.json` JSON paths `payload.event_tables`, `payload.workload`, and `payload.capture`. However:

- `scripts/check_r7_shared_profiler.py:17-23` checks the canonical hash before semantic validation.
- Its negative mutations at `scripts/check_r7_shared_profiler.py:125-149` do not recompute that hash and accept any `SystemExit`; targeted execution showed all three advertised tests fail only with `event export canonical hash mismatch`.
- `scripts/check_r7_shared_profiler.py:38-41` requires only nonzero GPU/encoder counts, not the asserted 100/50 counts.
- `scripts/check_r7_shared_profiler.py:74-79` requires mapping coverage plus only one matching GPU submission, not complete row-level joins.
- `scripts/check_r7_shared_profiler.py:72-73,84-90` checks path totals but not the observed alternating schedule.
- `scripts/check_r7_shared_profiler.py:97-98` checks only source-hash key names; it does not validate hash form or bind `payload.generating_commit` to the profile/expected commit.

A targeted `python3 -B` in-memory test recomputed the canonical hash after each mutation. `validate_event_export` incorrectly accepted: GPU rows reduced `100→2`; mapping rows reduced `100→50`; nonalternating observed command order; fake source hashes; generating commit changed to forty zeroes; and every command’s encoder count changed to `999`.  
Risk: F-004’s actual export appears internally valid, but its claimed fail-closed checker and negative-test closure are false. Future corruption or fabrication of the load-bearing attribution structure could pass validation, weakening reproducibility and the profiler claim.  
Required fix: Strengthen semantic validation to require exact `50/50/100/100` cardinalities, complete GPU↔submission↔command joins, expected per-command mapping structure, observed B2/C1 alternation, valid source hashes, matching generating commit, and canonical encoder fields. Recompute canonical hashes in every negative fixture—or explicitly test semantic validation below the integrity layer—and assert the expected semantic rejection reason. Add mutations for missing labels, broken joins, altered order, wrong cardinality, wrong generating commit, and malformed hashes.  
Closure evidence: Updated checker passing the current artifact and rejecting every rehashed mutation above for its intended semantic reason, followed by fresh behaviorally read-only hostile review.

Verified without additional findings:

- Profiler identity is derived from observed Metal command/encoder labels, not array parity: `scripts/sanitize_r7_profiler_events.py:161-190`.
- Actual labels show 25 B2 `planefuse.b2.shared` rows with observed `planefuse.b2.rgb & planefuse.b2.stem`, and 25 C1 rows with `planefuse.c1.native_stem`.
- Export SHA-256 `96c7e43…36826`, canonical hash `eb50f16…633300`, profiler hash `2c5fd6c…08fb7`, and the packet’s other authoritative hashes match.
- Production `executeCHW` and `execute` are uninstrumented; profiler-only methods carry labels/timestamps. Production sources are byte-identical from `b6285f2` through HEAD.
- Five tracked Release batches reconstruct 1,000 pairs, 20 warmups and 200 pairs per process, 100/100 order balance, 64/64 both-order coverage, and complete AC/Low-Power/thermal conditions.
- Quality records 32 real plus 32 procedural inputs, 64/64 top-1 agreement, activation error `8.583068e-6`, and both retained real-image top-5 disagreements.
- Pipeline A remains contextual at `1.148292 ms`; the eight-row matrix defensibly selects B2/C1.
- Camera evidence is correctly historical; the fresh R7 attempt produced zero callbacks and no inferred result.
- Current-tree profiler exports pass privacy checks. Existing Git-history privacy remains explicitly blocked from publication pending human-authorized sanitization or clean-history publication.
