# PlaneFuse Live — 2:30–2:45 demo package

Status: INTERNAL CAPTURE PLAN — do not record or upload without human approval.

## Exact spoken script and shot list

### 0:00–0:15 — problem and result

Shot: title card or clean dashboard overview.

Spoken: “Your camera already produces NV12. Most AI pipelines expand it to RGB
before the model throws that representation away. PlaneFuse recompiles the
learned input stem to work on native planes. On our reviewed MobileNetV2 test,
it cuts matched p50 latency by 11.8% without retraining.”

On screen: `11.8128% lower matched p50`, `NO RETRAINING`, `FULL RGB: 0 B`.

### 0:15–0:45 — live camera

Shot: real camera preview in `./pf live --app`, with the dashboard visible.

Spoken: “This is local inference on the Mac. The preview is NV12, and the
dashboard reports actual top-3 predictions and confidence only after a real
camera callback.”

Point to: `LIVE`, `NV12 VIDEO-RANGE`, top-3 output, selected mode, and the exact
`POST-RESIZE → RESULT` label. Do not call comparison-loop FPS sustained
throughput.

### 0:45–1:20 — B2 versus PlaneFuse

Shot: toggle `B2 · RGB` and `PLANEFUSE · NV12`.

Spoken: “B2 materializes normalized Float32 RGB before the ordinary stem. C1-SR
reads the Y and UV planes directly, stages a small source tile, and reuses it
across output channels. Both hand the same persistent Float32 activation to the
same pretrained tail.”

Point to: B2 `602,112 B logical / 606,208 B Metal allocated`; C1-SR `full RGB
intermediate NONE`; both `CPU activation element-copy 0 B`; `PASS · top-1`.

### 1:20–1:50 — stored reviewed evidence

Shot: stored evidence panel or `docs/JUDGE_EVIDENCE.md`.

Spoken: “These are stored reviewed measurements, not camera claims: B2 is
1.737875 milliseconds, accepted C1 is 1.633458, and C1-SR is 1.532583. That
is 11.8128% below B2 and 6.1755% below C1. The paired median interval is shown
separately because it is a different statistic.”

On screen: `STORED EVIDENCE`, p50 table, paired CI `[0.180250, 0.198792] ms`,
quality agreement `1.0`.

### 1:50–2:15 — architecture and reuse lesson

Shot: architecture diagram or source-reuse shader/code.

Spoken: “The transformation composes YUV conversion, normalization, and the
first learned operator analytically. R6.5 taught us that deleting an
intermediate can delete useful reuse. PlaneFuse keeps the native representation
and restores reuse in the schedule.”

### 2:15–2:35 — honest limits

Shot: negative-results/limits section of the README.

Spoken: “Float16 and Metal 4 did not pass their gates on the stable toolchain,
and direct camera-space fusion was slower. MobileNetV2 is the only claimed
workload on this Apple-Silicon environment. T2 and T3 are not established, so
this is a precise measured result, not a universal speedup claim.”

### 2:35–2:45 — reproduction

Shot: terminal with a clean, privacy-safe prompt.

Spoken: “Clone the repository, run setup, verify, and `./pf live --app`. The
evidence page links every number to its checker.”

## Capture checklist

- Confirm camera permission and device availability before recording.
- Use a clean Release `./pf live --app` launch; do not record a debug terminal.
- Keep `LIVE` and `STORED EVIDENCE` visibly distinct.
- Show real top-3 labels/confidence; never type or paste metrics into the app.
- If the camera is unavailable, show the friendly unavailable state or stop;
  never substitute stored values for live values.
- Capture the B2/PlaneFuse toggle and resource-boundary text at readable scale.
- Include the 64-input quality result and paired-CI distinction.
- Keep the frame free of usernames, home paths, device nicknames, UUIDs, PIDs,
  unrelated process lists, tokens, private email, and unlicensed music/assets.
- Human approval is required before recording, uploading, or linking the video.
