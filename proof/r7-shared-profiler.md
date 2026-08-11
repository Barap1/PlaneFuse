# R7 strongest B/C profiler evidence

Status: EXPERIMENTAL PROFILER EVIDENCE PENDING HOSTILE REVIEW

The old `proof/r7-final-component-profile.json` remains indexed `EXPERIMENTAL` and is not final evidence: it was generated at `8bea11d` and profiles the historical boxed MLMultiArray population path with separate diagnostic B conversion/stem submissions.

The exact accepted shared paths have a separate profile command:

```text
./pf profile mobilenetv2 shared
```

The profile implementation is committed at `f615847fe6e1aa6e56fbfc442b17f25fda5d5d83` and uses the production `MetalMobileNetV2RGBPipeline.executeCHWTimed`/`encodeCHWConversion`/`encodeCHWStem`, `MetalMobileNetV2NativeStem.executeTimed`/`encode`, persistent `BufferBackedMultiArray` views, and the same `.all` `CoreMLMobileNetV2TailAdapter.predict(sharedActivation:)` tail. It is separate from the five-batch final benchmark.

Compact profile artifact: `proof/r7-final-shared-path-profile.json`

- environment: arm64, Apple M5 Pro, macOS 26.6.1, Xcode 26.6, Release;
- profile samples: 5 warmups, 20 measured B2/C1 path samples;
- B2 GPU p50 `0.3056 ms`, input-to-result p50 `2.1871 ms`;
- C1 GPU p50 `0.2396 ms`, input-to-result p50 `1.9924 ms`;
- top-1 agreement `1.0`, activation max absolute error `8.58306884765625e-6`;
- B2 RGB logical/Metal allocated bytes `602112/606208`;
- C1 RGB logical/Metal allocated bytes `0/0` (only the required activation buffer remains);
- persistent activation `[48,112,112]`, strides `[12544,112,1]`, Float32, 2,408,448-byte B2/C1 buffers;
- PlaneFuse element-by-element activation copy bytes `0`.

Profiler capture: `proof/profiler/r7-b2-c1-shared.trace` (local 261 MB Metal System Trace bundle) and compact export `proof/profiler/r7-b2-c1-shared-toc.xml`. The trace TOC identifies the launched `planefuse profile mobilenetv2 shared` process on the Apple M5 Pro/macOS 26.6.1, the Metal System Trace template, and Metal command-buffer/GPU execution schemas. The raw bundle is intentionally kept outside the commit because of its size; the compact export and exact reproducible command are committed with the review packet:

```text
xcrun xctrace record --template 'Metal System Trace' --time-limit 45s --output proof/profiler/r7-b2-c1-shared.trace --launch -- .build/arm64-apple-macosx/release/planefuse profile mobilenetv2 shared
xcrun xctrace export --input proof/profiler/r7-b2-c1-shared.trace --toc --output proof/profiler/r7-b2-c1-shared-toc.xml
python3 -B scripts/check_r7_shared_profiler.py
```

The trace was captured as a separate profiling run; its instrumentation is not used for any normal benchmark result. The profile artifact and trace summary are evidence for resource/path inspection, not a new performance claim.
