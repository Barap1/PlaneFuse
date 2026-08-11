# R7 historical camera evidence provenance

Status: QUALIFIED HISTORICAL EVIDENCE; no fresh camera performance result

The successful Release B2/C1 camera evidence is `proof/r6.1-camera-benchmark-release.json`. Its benchmark artifact was recorded in documentation commit `46fbe3d5cf3df1d1d25f82d181d130ad8305959e`; the camera harness and accepted B2/C1 execution path were introduced by `93a701632df6a83df4c01d06511c5432a688cd9e`.

The fresh R7 acquisition is separately recorded in `proof/r7-camera-session-attempt-20260811.json` at the historical attempt commit `8bea11d3e71257723dfdbb355e95ac0413e438f4`. It received zero callbacks before timeout. No latency, FPS, drop, or parity values are inferred from that attempt.

## Current-path comparison

The benchmark-relevant accepted path was compared from `93a7016` to the current reviewed source:

- `Sources/PlaneFuseLive/main.swift`: `CameraInferenceRunner.inferB2` still calls `MetalMobileNetV2RGBPipeline.executeCHW` and `CoreMLMobileNetV2TailAdapter.predict(sharedActivation:)`; `inferC1` still calls `MetalMobileNetV2NativeStem.execute` and the same shared tail. The later additions are R6.5 camera-space candidates and helper accessors; they are not used by the R6.1 evidence path.
- `Sources/PlaneFuseCore/MetalMobileNetV2RGBPipeline.swift`: B2 `executeCHW` still submits the same NV12-to-CHW conversion and RGB stem. `executeCHWTimed` is a profiling-only wrapper whose encoded work is identical.
- `Sources/PlaneFuseCore/MetalMobileNetV2NativeStem.swift`: C1 `execute` and its native-plane shader path are unchanged.
- `Sources/PlaneFuseCore/MobileNetV2Integration.swift`: the shared Float32 buffer-backed tail adapter and `predict(sharedActivation:)` contract are unchanged.
- `Sources/PlaneFuseLive/CameraNV12MetalBridge.swift`: `execute(pixelBuffer:into:)` was factored through `sourceTextures`/`encodeResize` and now retains the Core Video texture wrappers through GPU completion. The same video-range NV12 format checks, crop geometry, resize shaders, output sizes, and wait boundary remain in the accepted replay/live path. The new source-space overload is used only by R6.5.
- `Sources/PlaneFuseLive/CameraBenchmarkSupport.swift`: additions are source-resolution R6.5 replay records; the original 224x224 R6.1 replay structures remain.

The comparison commands were:

```text
git log --follow -- proof/r6.1-camera-benchmark-release.json
git diff --unified=0 93a7016..f615847 -- Sources/PlaneFuseLive/main.swift Sources/PlaneFuseLive/CameraBenchmarkSupport.swift Sources/PlaneFuseLive/CameraNV12MetalBridge.swift Sources/PlaneFuseCore/MobileNetV2Integration.swift Sources/PlaneFuseCore/MetalMobileNetV2RGBPipeline.swift Sources/PlaneFuseCore/MetalMobileNetV2NativeStem.swift
rg -n "inferB2|inferC1|executeCHW|sharedActivation|func execute\(" Sources/PlaneFuseLive/main.swift Sources/PlaneFuseCore
```

Conclusion: the historical Release B2/C1 measurements exercise the same accepted B2/C1 execution semantics. The evidence remains historical because current physical-camera acquisition was unavailable; equivalence does not create a new current-camera measurement.
