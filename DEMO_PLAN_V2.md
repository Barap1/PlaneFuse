# PlaneFuse Continuum demo plan

Target length: 2:30-2:45

Primary audience: a technically skeptical Arm hackathon judge who may never run the repository.

## The visual promise

The judge should understand this within 15 seconds:

```text
ordinary path
camera Y+UV -> RGB image -> learned stem -> CPU tensor bridge -> model tail

PlaneFuse Continuum
camera Y+UV -> source-native learned stem -> shared tensor -> model tail
```

The optimized path eliminates the full RGB intermediate. The strongest Phase 2 path should also eliminate the element-by-element CPU activation copy, and may keep the model tail on the GPU timeline if R4 succeeds.

## Application screen

Build one clear macOS window:

### Left: live camera and predictions

- camera preview;
- top-3 labels and confidence;
- current mode: A / B2 / PlaneFuse;
- parity status.

### Right: representation and performance

- animated but truthful dataflow;
- frontend latency;
- bridge latency;
- end-to-end/capture-to-result latency;
- FPS and dropped frames;
- RGB intermediate logical and allocated bytes;
- CPU activation copy: boxed / shared / none;
- stored benchmark confidence interval, labeled “verified benchmark.”

Do not animate fake counters. Live values come from the actual run. Stored values are labeled.

## Recommended video sequence

### 0:00-0:12 — Hook

“Your Mac camera already produces a compact YUV image. Most vision models expand that frame into RGB, then immediately multiply it into another representation. PlaneFuse compiles away that detour.”

Show RGB intermediate appearing in B and disappearing in C.

### 0:12-0:30 — Useful local experience

Point the camera at several objects. Show local MobileNetV2 predictions and confidence. Turn network connectivity off or show that no cloud service is used.

### 0:30-0:55 — Fair A/B comparison

Toggle B2 and PlaneFuse on the same replayed/captured frames. Show the same labels and real measured latency.

### 0:55-1:20 — Technical reveal

Simple diagram:

```text
YUV conversion + normalization + Conv + BN
                    ↓ compiler
native Y/UV convolution coefficients
```

Then show the polyphase 4:2:0 insight: nine RGB-domain taps collapse onto fewer physical chroma samples.

### 1:20-1:45 — Execution-continuum reveal

Show the old boxed activation bridge and the accepted new bridge:

```text
old: 602,112 boxed assignments
new: shared activation view / MTLTensor
```

Only show “one GPU timeline” if R4 actually succeeds.

### 1:45-2:10 — Evidence

Show:

- final p50/p95 and confidence interval;
- real/expanded corpus agreement;
- profiler resource/timeline capture;
- RGB intermediate bytes;
- clean-clone command.

### 2:10-2:32 — Developer impact

Run compact commands:

```bash
./pf setup mobilenetv2
./pf inspect mobilenetv2
./pf verify mobilenetv2
./pf bench final
```

Show explicit rejection of an unsupported spec.

### 2:32-2:40 — Close

“Same pretrained model. Same local vision result. Less representation work between the camera and the answer — built on Arm-powered Apple Silicon.”

## Mandatory capture assets

- app screenshot in B2 mode;
- app screenshot in PlaneFuse mode;
- continuous camera recording;
- architecture diagram;
- B/C Metal/Instruments trace screenshots;
- final benchmark and quality table;
- CLI clean-clone/setup output;
- system summary without usernames/serial numbers.

## Demo acceptance gate

- continuous camera works for at least 300 frames;
- same frame stream is used for compared modes or a replay buffer is used;
- labels/confidence are visible;
- metrics are not placeholders;
- no denied camera run is presented as success;
- no beta-only result is shown without a beta label;
- no universal or world-first claim;
- video is under 3 minutes.
