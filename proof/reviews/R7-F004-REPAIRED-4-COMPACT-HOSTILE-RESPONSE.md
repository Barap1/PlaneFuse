# Parent response: R7-F004-REPAIRED-4-COMPACT-HOSTILE-20260811

The compact independent re-review returned `RETHINK` with one further valid F-004 checker-hardening scope. The parent validated each point and repaired only the profiler checker/test fixtures. The actual profiler export, source, benchmark, model, workload, thresholds, and performance implementation are unchanged.

## F-001 — competition-worthiness hard stop

- Disposition: OPEN / VALID; unchanged.
- Parent action: preserve the fixed target gate and honest sub-target result. T1/T2/T3 remain false and T4 remains pending/false; no R7 acceptance or winning claim is made.
- Targeted validation: `python3 -B scripts/check_r7_repaired_targets.py proof/r7-competition-targets-repaired-conditions.json`.
- Closure evidence: none; human strategy decision remains required after technical evidence closure.
- Re-review required: yes.

## F-004 — final semantic checker hardening

- Disposition: VALID / FIXED; pending fresh compact hostile re-review.
- Finding validated: the previous checker did not require profiler workload `5/20`, allowed null encoder counts, did not bind invocation GPU IDs to their command mappings, did not enforce unique mapped submissions across commands, and its schema-only negative fixture failed at the hash layer.
- Exact repair: require exact `warmup_iterations=5` and `measured_iterations=20`; require every observed command `encoder_count == 1`; require 50 unique invocation command IDs and exact per-invocation equality between recorded GPU submission IDs and that command’s two observed mapping rows; require all 100 mapped submission IDs to be unique; rehash the schema-only fixture from its actual payload; and make every negative fixture assert an intended semantic error rather than accepting any `SystemExit`.
- Targeted validation: `python3 -B scripts/check_r7_shared_profiler.py proof/r7-final-shared-path-profile-repaired-conditions.json --events proof/profiler/r7-b2-c1-shared-repaired-events-full.json --expected-commit b6285f2eb6b9329f925cde81db5936f5f2a8de98`; `python3 -m py_compile scripts/check_r7_shared_profiler.py`.
- Closure evidence: positive artifact passes; rehashed tests reject schema-only, truncated attribution, wrong observed path, wrong GPU cardinality, incomplete map cardinality, fake source hash, wrong generating commit, wrong encoder count, wrong workload counts, null encoder count, cardinality-preserving cross-command mapping swap, invocation order/ID corruption, and blank/generic rows for named semantic reasons.
- Re-review required: yes.

## Decision gate

Do not activate R7.5 or proceed to R8/R9 from this response. Request one fresh independent hostile review of the repaired checker and packet; F-001 remains a separate strategic hard stop.
