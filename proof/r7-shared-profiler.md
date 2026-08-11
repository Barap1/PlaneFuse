# R7 strongest B/C profiler evidence

Status: REPAIRED PROFILER EVIDENCE PENDING FRESH HOSTILE REVIEW

The old `proof/r7-final-component-profile.json` remains indexed `EXPERIMENTAL` and is not final evidence: it was generated at `8bea11d` and profiles the historical boxed MLMultiArray population path with separate diagnostic B conversion/stem submissions.

The exact accepted shared paths have a separate, naturally terminating Release profile command:

```text
./pf profile mobilenetv2 shared
```

The repaired profile implementation is committed at `fbebf546fb7d76b531c0e7b6653f509a0d9cbfec` and uses the accepted B2-shared and C1-shared paths, persistent `BufferBackedMultiArray` views, and the same `.all` `CoreMLMobileNetV2TailAdapter.predict(sharedActivation:)` tail. It is separate from the five-process final benchmark. Production execution does not collect profiler timings; only the profile methods add GPU timestamps and labels while sharing the same encoding helpers.

Compact profile artifact: `proof/r7-final-shared-path-profile-repaired-labeled.json`

- environment: arm64, Apple M5 Pro, macOS 26.6.1, Xcode 26.6, Release;
- profile samples: 5 warmups, 20 measured B2/C1 path samples;
- B2 GPU p50 and input-to-result p50 are recorded in the artifact (the profiler run is descriptive, not the final benchmark);
- C1 GPU p50 and input-to-result p50 are recorded in the artifact (the profiler run is descriptive, not the final benchmark);
- top-1 agreement `1.0`, activation max absolute error `8.58306884765625e-6`;
- B2 RGB logical/Metal allocated bytes `602112/606208`;
- C1 RGB logical/Metal allocated bytes `0/0` (only the required activation buffer remains);
- persistent activation `[48,112,112]`, strides `[12544,112,1]`, Float32, 2,408,448-byte B2/C1 buffers;
- PlaneFuse element-by-element activation copy bytes `0`.

Profiler capture: `proof/profiler/r7-b2-c1-shared-repaired-labeled.trace` (local raw Metal System Trace bundle, intentionally outside the commit) and sanitized event export `proof/profiler/r7-b2-c1-shared-repaired-events.json`. The export contains actual nonzero command-buffer, GPU-execution, and encoder event rows: 50 command-buffer rows, 164 GPU execution rows, and 50 encoder rows, with 25 B2 and 25 C1 measured command-buffer invocations. The workload exited cleanly with status 0. xctrace normalized the source labels in the exported rows to generic command/encoder names; the source-level labels and exact B2/C1 encoder structure are checked from the generating source and profile artifact. No device nickname, UUID, username, PID, path inventory, or unrelated process inventory is committed.

```text
xcrun xctrace record --template 'Metal System Trace' --output proof/profiler/r7-b2-c1-shared-repaired-labeled.trace --launch -- .build/arm64-apple-macosx/release/planefuse profile mobilenetv2 shared
xcrun xctrace export --input proof/profiler/r7-b2-c1-shared-repaired-labeled.trace --xpath '/trace-toc' --output /tmp/r7-repaired-labeled-toc.xml
xcrun xctrace export --input proof/profiler/r7-b2-c1-shared-repaired-labeled.trace --xpath '/trace-query-result/row' --schema metal-application-command-buffer-submissions --output /tmp/r7-repaired-labeled-command.xml
xcrun xctrace export --input proof/profiler/r7-b2-c1-shared-repaired-labeled.trace --xpath '/trace-query-result/row' --schema metal-gpu-execution-points --output /tmp/r7-repaired-labeled-gpu.xml
xcrun xctrace export --input proof/profiler/r7-b2-c1-shared-repaired-labeled.trace --xpath '/trace-query-result/row' --schema metal-application-encoders-list --output /tmp/r7-repaired-labeled-encoders.xml
python3 -B scripts/sanitize_r7_profiler_events.py --trace-toc /tmp/r7-repaired-labeled-toc.xml --command-events /tmp/r7-repaired-labeled-command.xml --gpu-events /tmp/r7-repaired-labeled-gpu.xml --encoder-events /tmp/r7-repaired-labeled-encoders.xml --output proof/profiler/r7-b2-c1-shared-repaired-events.json
python3 -B scripts/check_r7_shared_profiler.py --expected-commit fbebf546fb7d76b531c0e7b6653f509a0d9cbfec
```

The trace was captured as a separate profiling run; its instrumentation is not used for any normal benchmark result. The profile artifact and sanitized event rows are evidence for resource/path inspection, not a new performance claim. The previous schema-only XML exports were removed from the current tree and are retained only as historical review context; the old boxed component profile is not promoted.
