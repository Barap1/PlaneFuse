# R6 camera texture gate

Status: R6 CAMERA DELIVERY GATE PASSED — release-grade benchmark still pending

Committed implementation: `92820ba feat(camera): add retained GPU native-plane stream`

The R6 path now:

- maps camera video-range NV12 Y and UV planes through `CVMetalTextureCache`;
- retains the Core Video texture wrappers until the resize command buffer completes;
- performs even-aligned center-square crop and nearest source-grid Y/UV resize in
  Metal into `r8Uint`/`rg8Uint` output textures;
- reuses a three-texture output ring;
- reuses B/C Metal pipelines, activation buffers, and persistent buffer-backed
  `MLMultiArray` views across frames;
- reports live resize GPU timing, B/C latency, first-frame activation parity,
  top-1 agreement, and the 300-frame count without fabricating unavailable metrics.

Validation completed:

- `./pf build` — PASS;
- `./pf test quick` — PASS (35 tests);
- `./pf live --help` — PASS and describes the GPU camera path;
- `system_profiler SPCameraDataType` — MacBook Pro Camera hardware present.
- Human-performed permitted-camera run: 300 processed native-plane frames
  completed successfully on 2026-08-10. The durable machine-readable record is
  `proof/r6-camera-300-frame.json`; the committed raw console log is
  `proof/r6-camera-300-frame.log`. The original ignored log remains at
  `artifacts/logs/pf-live-20260810T200322Z.log`.

The first post-implementation camera invocation reached frame delivery but exposed
a duplicate queued-frame sequencing bug; that was fixed before the successful
run. Three subsequent invocations after the fix timed out before receiving a
frame (`pf-live-20260809T230020Z.log`, `230044Z.log`, and `230122Z.log`). Those
timeouts remain historical evidence and are not overwritten by the successful
run.

The successful run proves camera delivery, CVMetalTextureCache plane mapping,
GPU native-plane resize, persistent B/C resources, first-frame parity, and
300 processed-frame top-1 agreement. Its last callback sequence was 317; the
current run did not count dropped/late callbacks, so it does not establish
drop-free delivery. It was launched through the current Debug
`./pf live --camera` path and its B/C measurements begin after camera resize;
therefore it is R6 technical-gate evidence, not release-grade capture-to-result
or final B-versus-C performance evidence. Release benchmarking must use the
strongest B2 path, explicit matched Core ML compute units, alternating order,
separate B-only/C-only throughput runs, and defensible capture/frame-delivery
timing.
