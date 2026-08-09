# R6 camera texture gate

Status: BLOCKED — local camera session did not deliver frames

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

The first post-implementation camera invocation reached frame delivery but exposed
a duplicate queued-frame sequencing bug; that was fixed before the current gate
attempts. Three subsequent invocations after the fix timed out before receiving a
frame (`pf-live-20260809T230020Z.log`, `230044Z.log`, and `230122Z.log`). No
300-frame metric, camera parity result, screenshot, or recording is claimed.

This is an external-state hard stop: the hardware is enumerated, but the local
capture session is currently not delivering frames. Resume after the user restores
camera availability/permission or closes any competing camera client, then rerun
`./pf live --camera`.
