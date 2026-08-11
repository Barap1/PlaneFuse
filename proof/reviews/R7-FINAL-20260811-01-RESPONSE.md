# Parent response: R7-FINAL-20260811-01

Parent response recorded from commit `40e5fd7a4f7359d5cf60229c884af1842d7dc785`.
The human approved R7 evidence repair and explicitly prohibited the new-workload
path. No finding is marked closed by this response; each repaired finding requires
targeted validation and fresh independent review.

## Finding ID: F-001

- Disposition: deferred-with-approval
- Parent verification: `proof/r7-competition-targets.json` records T1/T2/T3 as false and T4 as pending/false; the hostile review correctly notes that the current 2.5013% result is below the 10% threshold. Human authorization is to repair evidence first.
- Change/evidence: Do not close. Preserve all thresholds and reconsider competition-worthiness only from the repaired authoritative evidence. No new workload, model change, R7.5 activation, or winning claim is authorized in this response.
- Targeted validation: Re-run the target evaluator against the regenerated final B2/C1 artifact and inspect all four target records without threshold changes.
- Closure evidence: Repaired authoritative target artifact plus a fresh independent Sol verdict. Re-review required: yes.

## Finding ID: F-002

- Disposition: valid
- Parent verification: `Sources/PlaneFuseCore/MobileNetV2DirectSharedBenchmark.swift:209-255` performs one warmup phase, labels one continuous run as five batches, and derives sample/order from global parity. The raw artifact has 1,000 records, 64 unique samples, and zero samples in both execution orders.
- Change/evidence: Replace the final protocol with five separately orchestrated Release executions/processes. Each batch will independently initialize state, warm at least 20 times, measure exactly 200 matched pairs, use fixed output-blind 64-input corpus and `.all` tail, rotate source offset and order phase, and preserve a batch identity plus raw records. Aggregate evidence will require both execution orders for every repeated source sample.
- Targeted validation: Add a fail-closed raw-record checker for five distinct executions, per-batch warmups, 200 pairs, 100/100 order balance, source distribution, both-order coverage, batch provenance, recomputed statistics, and deterministic bootstrap metadata. Run the repaired five-batch Release protocol and checker.
- Closure evidence: New performance artifact at the exact generating commit with five execution identities, raw records, regenerated statistics/targets, and checker pass. Re-review required: yes.

## Finding ID: F-003

- Disposition: valid
- Parent verification: Current `MetalMobileNetV2RGBPipeline.executeCHW` delegates to `executeCHWTimed`, which collects `ProcessInfo` timing and GPU timestamps. This differs from the historical performance artifact’s production path.
- Change/evidence: Restore production B2 to encode/commit/wait with no timing or GPU timestamp collection. Keep profiler timing in a separate path that shares only the same encoding helpers. Audit C1 production execution for the same property and add source/tests proving instrumentation is profiler-only and kernel/resource/order encoding is shared.
- Targeted validation: Source checker plus relevant Swift tests; inspect production and profiler symbols; rerun the repaired final five-batch Release benchmark at the clean source commit.
- Closure evidence: Clean-source performance artifact and source/test evidence showing production B2/C1 contain no profiler-only instrumentation. Re-review required: yes.

## Finding ID: F-004

- Disposition: valid
- Parent verification: `proof/profiler/r7-b2-c1-shared-command-buffers.xml` contains only a schema, and the TOC records the bounded capture’s SIGKILL/time-limit termination. The current checker does not reject empty exports.
- Change/evidence: Capture a short naturally terminating Release workload for exact B2-shared/C1-shared paths, export a small sanitized event-row artifact with actual nonzero B2/C1 command-buffer/GPU events and expected encoder structure, and preserve the exact commit/environment/command. Do not commit the large raw trace.
- Targeted validation: Strengthen the profiler checker to require event rows, expected B2/C1 counts/patterns, clean workload completion or explicit accepted status, export hash, generating commit, and a negative test proving the old schema-only export fails.
- Closure evidence: Committed hashed event-row export, passing positive checker and passing negative test, clean capture metadata, and fresh review. Re-review required: yes.

## Finding ID: F-005

- Disposition: valid
- Parent verification: The committed profiler TOC contains a device nickname, hardware UUID, and local process/application inventory. Simple deletion from the current file cannot remove already committed history.
- Change/evidence: Sanitize current-tree profiler exports and add a privacy checker rejecting device names, UUIDs, usernames/paths, PIDs, and unrelated process inventory. Preserve the existing private history; do not rewrite or force-push it.
- Targeted validation: Run the privacy checker over all final profiler proof artifacts and inspect the sanitized event export/TOC for only technically relevant environment metadata.
- Closure evidence: Privacy checker pass plus a release blocker documenting the human choice between approved history sanitization/rewrite and publication from a clean sanitized repository/history. Re-review required: yes.

## Finding ID: F-006

- Disposition: valid
- Parent verification: The current review packet does not contain the required row-by-row A/B1/B2/C0/C1/C2/C3/C4 selection matrix, including explicit B1/C0 dispositions.
- Change/evidence: Create checked machine-readable and human-readable matrices covering implementation status, boundary, precision, intermediates, bridge, tail/model, evidence, result, disposition, and matched-comparison eligibility. Reference existing evidence without rerunning obsolete paths. Keep R6.5 camera-space fusion separately documented as a negative extension.
- Targeted validation: Add a fail-closed matrix checker covering every required row and required dispositions: strongest B2/C1, contextual Pipeline A, superseded B1/C0, C2 quality rejection, C3 stable-toolchain infeasibility, and C4 polyphase disposition.
- Closure evidence: Matrix JSON/Markdown, checker pass, regenerated review packet, and fresh Sol review. Re-review required: yes.

