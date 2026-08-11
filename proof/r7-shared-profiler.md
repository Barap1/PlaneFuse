# R7 strongest B/C profiler evidence

Status: F-004 profiler attribution repair complete; fresh hostile re-review required

The old `proof/r7-final-component-profile.json` remains indexed `EXPERIMENTAL` and is not final evidence: it was generated at `8bea11d` and profiles the historical boxed MLMultiArray population path with separate diagnostic B conversion/stem submissions.

The exact accepted shared paths have a separate, naturally terminating Release profile command:

```text
./pf profile mobilenetv2 shared
```

The repaired profile implementation is committed at `b6285f2eb6b9329f925cde81db5936f5f2a8de98` and uses the accepted B2-shared and C1-shared paths, persistent `BufferBackedMultiArray` views, and the same `.all` `CoreMLMobileNetV2TailAdapter.predict(sharedActivation:)` tail. It is separate from the five-process final benchmark. Production execution does not collect profiler timings; only the profile methods add GPU timestamps, labels, and profiler-only signposts while sharing the same encoding helpers.

Compact profile artifact: `proof/r7-final-shared-path-profile-repaired-conditions.json`

- environment: arm64, Apple M5 Pro, macOS 26.6.1, Xcode 26.6, Release;
- profile samples: 5 warmups, 20 measured B2/C1 path samples;
- B2 GPU p50 and input-to-result p50 are recorded in the artifact (the profiler run is descriptive, not the final benchmark);
- C1 GPU p50 and input-to-result p50 are recorded in the artifact (the profiler run is descriptive, not the final benchmark);
- top-1 agreement `1.0`, activation max absolute error `8.58306884765625e-6`;
- B2 RGB logical/Metal allocated bytes `602112/606208`;
- C1 RGB logical/Metal allocated bytes `0/0` (only the required activation buffer remains);
- persistent activation `[48,112,112]`, strides `[12544,112,1]`, Float32, 2,408,448-byte B2/C1 buffers;
- PlaneFuse element-by-element activation copy bytes `0`.

Profiler capture: `proof/profiler/r7-b2-c1-shared-repaired-labeled.trace` (local raw Metal System Trace bundle, intentionally outside the commit) and sanitized event export `proof/profiler/r7-b2-c1-shared-repaired-events-full.json`. The export contains 50 command-buffer rows, 100 GPU execution rows, 50 encoder rows, and 100 observed submission-to-command-buffer mapping rows. The trace itself observes 25 `planefuse.b2.shared` command labels with the combined ordered `planefuse.b2.rgb & planefuse.b2.stem` encoder label and 25 `planefuse.c1.shared` labels with `planefuse.c1.native_stem`; command-buffer IDs join the encoder and GPU/submission rows. The checker requires exact 50/100/50/100 cardinalities, profiler workload 5/20, canonical encoder count 1, complete per-command mapping/GPU joins bound into every invocation, unique mapped submissions, observed alternating order, valid source hashes, generating-commit equality, and rejects rehashed blank/generic-only, schema-only, truncation, wrong-path, wrong-cardinality, broken-join, wrong-workload, null-encoder, wrong-commit, and wrong-encoder mutations for named semantic reasons. No device nickname, UUID, username, PID, path inventory, or unrelated process inventory is committed.

```text
xcrun xctrace record --template 'Metal System Trace' --time-limit 10s --no-prompt --output proof/profiler/r7-b2-c1-shared-repaired-labeled.trace --launch -- .build/arm64-apple-macosx/release/planefuse profile mobilenetv2 shared
xcrun xctrace export --input proof/profiler/r7-b2-c1-shared-repaired-labeled.trace --toc --output /tmp/r7-repaired-labeled-toc.xml
xcrun xctrace export --input proof/profiler/r7-b2-c1-shared-repaired-labeled.trace --xpath '/trace-toc/run[@number="1"]/data/table[@schema="metal-application-command-buffer-submissions"]' --output /tmp/r7-repaired-labeled-command.xml
xcrun xctrace export --input proof/profiler/r7-b2-c1-shared-repaired-labeled.trace --xpath '/trace-toc/run[@number="1"]/data/table[@schema="metal-gpu-execution-points"]' --output /tmp/r7-repaired-labeled-gpu.xml
xcrun xctrace export --input proof/profiler/r7-b2-c1-shared-repaired-labeled.trace --xpath '/trace-toc/run[@number="1"]/data/table[@schema="metal-application-encoders-list"]' --output /tmp/r7-repaired-labeled-encoders.xml
xcrun xctrace export --input proof/profiler/r7-b2-c1-shared-repaired-labeled.trace --xpath '/trace-toc/run[@number="1"]/data/table[@schema="metal-gpu-submission-to-command-buffer-id"]' --output /tmp/r7-repaired-labeled-map.xml
python3 -B scripts/sanitize_r7_profiler_events.py --profile proof/r7-final-shared-path-profile-repaired-conditions.json --toc /tmp/r7-repaired-labeled-toc.xml --command-events /tmp/r7-repaired-labeled-command.xml --gpu-events /tmp/r7-repaired-labeled-gpu.xml --encoder-events /tmp/r7-repaired-labeled-encoders.xml --submission-map /tmp/r7-repaired-labeled-map.xml --output proof/profiler/r7-b2-c1-shared-repaired-events-full.json
python3 -B scripts/check_r7_shared_profiler.py proof/r7-final-shared-path-profile-repaired-conditions.json --events proof/profiler/r7-b2-c1-shared-repaired-events-full.json --expected-commit b6285f2eb6b9329f925cde81db5936f5f2a8de98
```

The trace was captured as a separate profiling run; its instrumentation is not used for any normal benchmark result. The profile artifact and sanitized event rows are evidence for resource/path inspection, not a new performance claim. The previous schema-only XML exports were removed from the current tree and are retained only as historical review context; the old boxed component profile is not promoted.
