# Arm hackathon scorecard for PlaneFuse

Source snapshot checked: 2026-08-09. See `REFERENCES.md`.

Official submission deadline: August 14, 2026 at 4:00 PM PDT.

Selected track: Mobile AI.

Mobile AI fit to emphasize:

- fully local inference on an Arm-powered client device;
- vision/camera intelligence;
- low latency/responsiveness;
- memory/bandwidth efficiency;
- offline/privacy value;
- reusable developer tooling.

## Judging weights

### Technological Implementation - 40 points

Target evidence:

- real Apple-Silicon/Arm implementation;
- mathematical/reference proof;
- custom native-plane Metal work;
- fair optimized baseline;
- profiler/allocation evidence;
- model-output validation;
- reproducible benchmark harness;
- technically precise limitations.

Internal target: 38-40 only if evidence genuinely supports it.

Current self-score: 2/40 (concept only)

### User/Developer Experience - 15 points

Target evidence:

- `planefuse inspect/compile/verify/bench` style workflow;
- one-command supported example;
- clear README;
- compact failure messages;
- clean-clone reproduction;
- PlaneFuse Live demonstrates value without hiding engineering details.

Current self-score: 1/15

### Potential Impact - 20 points

Target evidence:

- reusable native-plane technique, not one hard-coded app;
- at least two compatible configurations if feasible;
- clear path to other Arm client camera formats/backends;
- benchmark/proof assets reusable by developers;
- real camera-AI use case.

Current self-score: 2/20

### WOW factor - 25 points

Target evidence/story:

- "the RGB image never exists in the optimized path";
- live camera AI still gives the same useful result;
- immediate A/B performance visualization;
- technically surprising but simple explanation;
- polished 2:30-ish video.

Current self-score: 3/25

## Evidence snapshot before judging

This is an evidence map, not a self-awarded judge score:

- Technological Implementation: strong evidence for native Metal fusion, fair
  B/C methodology, real MobileNetV2 tail preservation, numerical/task parity,
  and eliminated intermediate; profiler screenshots and peak-memory numbers
  are not claimed.
- User/Developer Experience: reproducible inspect/compile/verify/bench CLI and
  local sample/camera executable; polished GUI/video capture remains optional.
- Potential Impact: reusable narrow stem contract and local Arm64 workload;
  second configuration is explicitly a reference fixture, not a second
  pretrained model.
- WOW factor: the real model still agrees while C avoids the full RGB
  intermediate; the current showcase is a truthful CLI/local camera proof.

Do not convert this snapshot into a numeric score without judge evidence.

## Advancement rule

At each milestone ask:

"What is the single highest-leverage missing artifact preventing this from looking like a 95/100 submission?"

The answer should influence the next milestone only if it remains within the approved project direction.

## Mandatory submission requirements to protect

Before release confirm:

- public repository URL;
- MIT or Apache 2.0 license visible;
- project overview and why it should win;
- functionality/output description;
- step-by-step build/run/validation instructions on Arm hardware;
- project functions as depicted;
- third-party licenses respected;
- proof artifacts included where needed;
- optional demo video is <3 minutes and shows the project operating on intended device;
- judges can understand the result without running the code.
