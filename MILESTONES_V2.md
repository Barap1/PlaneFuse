# PlaneFuse Phase 2 milestone stack

Status: active continuation after the original M11 snapshot

Branch: `phase2/continuum`

The parent may advance automatically when a gate passes. It must stop only at the hard stops defined below.

The repository already has more than 40 meaningful commits. Phase 2 should normally require roughly 8-15 additional coherent Conventional Commits, not dozens of micro-commits.

## Hard stops for the entire stack

Stop and ask the human before:

- changing the project away from sensor-native pretrained vision inference;
- installing Xcode 27 beta, macOS 27 beta, or changing the system's active Xcode globally;
- any system-wide package installation or `sudo` operation;
- making the repository public;
- submitting to Devpost or uploading a public video;
- accepting a new quality threshold after seeing a failing result;
- replacing MobileNetV2 with a different primary model;
- making a beta-only path the release dependency;
- choosing a project pivot after the final competition-worthiness gate fails;
- changing camera/privacy settings that require user action.

Project-local virtual environments, model downloads, generated artifacts, and local package dependencies remain allowed.

---

# R0 — Repository truth, evidence, and reproducibility hardening

This milestone is mandatory and must complete before any new frontier optimization.

## Goal

Fix every known inconsistency in the current “release candidate” and make the repository internally truthful, reproducible, and judge-safe.

## Required work

### Status and claim truth

- Change current status from release candidate to Phase 2 hardening until all final gates pass.
- Reconcile `STATUS.md`, `CLAIMS.md`, `SUBMISSION_CHECKLIST.md`, `README.md`, and proof indexes.
- Ensure the final docs distinguish current verified pre-Phase2 results from targets.
- Record that the previous hostile final Sol review did not return; rerun it and persist the actual verdict if available.

### Benchmark artifact hygiene

- Create a committed index classifying every benchmark artifact as `ACCEPTED`, `SUPERSEDED`, `REJECTED`, or `EXPERIMENTAL`.
- Move or clearly label old misleading files such as the pre-fix 50% M4 artifacts and rejected MobileNet “final” artifacts without deleting scientific history.
- Fix every broken evidence link.
- Restore/commit the referenced M6 raw artifacts if they still exist locally. If they do not exist, remove false references and explicitly record the loss.
- Add a schema/status field that prevents superseded files from appearing as accepted results.

### Memory wording

- Replace “allocated 802,816 bytes” with “802,816 logical payload bytes” unless `MTLTexture.allocatedSize` is actually recorded.
- Add actual Metal allocation values for B and C resources where available.
- Keep peak-memory and bandwidth claims disabled until measured.

### One-command setup

Implement:

```bash
./pf setup mobilenetv2
```

It must:

- create/reuse a project-local `.venv`;
- pin the exact working `coremltools` version in a requirements/lock file;
- download the Apple MobileNetV2 model;
- verify the source SHA-256;
- run the preparation script;
- compile StemArray, FullArray, and Tail assets with `coremlc`;
- validate the generated manifest and hashes;
- be idempotent;
- print compact success/failure output and keep detailed logs under `artifacts/logs/`.

No Homebrew or system Python modification.

### Fresh clone reproduction

- Clone the private repository into a fresh temporary directory.
- Run setup, build, test, verify, one quick benchmark, and sample demo from scratch.
- Record exact commands, wall time, tool versions, and result.
- Add a release validation command such as:

```bash
./pf release validate
```

### Source-model lineage closure

- Run the original Apple image-input MobileNetV2 directly on the real corpus.
- Compare its top-1/top-5 output to the derived FullArray path.
- Record any preprocessing/orientation differences.
- Require exact or separately justified strong agreement before retaining the “unchanged source model behavior” claim.

### Validation corpus expansion

- Add at least 32 total inputs at R0: a mixture of additional licensed real images and procedural source-grid stress cases.
- Preserve hashes and provenance for real images.
- Add top-5 and probability-vector comparison metrics.
- R7 will expand/strengthen this further.

### Camera smoke

- Run `./pf live --camera`.
- If macOS requires camera authorization, stop once and ask the human to approve the prompt/settings.
- Fix all runtime issues after permission is granted.
- Print actual B/C top label and confidence, not only agreement.
- Do not claim continuous live operation yet.

### README correction

- Remove stale “planned outputs.”
- Put current verified results and explicit limitations near the top.
- Do not write the final marketing README yet; R9 owns final presentation.

## Gate

R0 passes only when:

- all known broken references and misleading artifact names/statuses are fixed;
- one-command setup works;
- a fresh clone reproduces the supported workflow;
- original image-input versus derived model lineage is checked;
- at least 32 corpus inputs are in the quality harness;
- physical camera smoke either passes or is stopped solely on a documented human privacy action;
- no unverified public claim remains;
- `./pf build`, `./pf test quick`, and release-history checks pass;
- a hostile advisor review returns `SHIP` or all `FIX-FIRST` findings are resolved.

## Suggested coherent commits

- `docs(truth): reopen PlaneFuse for Phase 2 hardening`
- `fix(evidence): classify benchmark artifacts and repair provenance`
- `feat(setup): add reproducible MobileNetV2 bootstrap`
- `test(release): verify clean-clone workflow and source lineage`

---

# R1 — Bottleneck decomposition and adversarial baselines

## Goal

Measure where the roughly 51 ms current path is spent and establish the strongest conventional baselines before optimizing the bridge.

## Required work

### Component instrumentation

Measure, separately and together:

- input texture creation/binding;
- B RGB conversion;
- B RGB stem;
- C native stem;
- GPU wait;
- `MTLBuffer` to Swift array creation;
- `MLMultiArray` allocation;
- element-by-element population/boxing;
- Core ML tail prediction;
- output extraction;
- total input-ready to result.

Use signposts and compact machine-readable component results.

### Accelerator evidence

- Capture a Metal GPU trace or Instruments trace for current B and C.
- Export compact screenshots/artifacts without PII.
- Record actual GPU durations where supported.
- Show the B RGB resource and C's absence of it.

### Pipeline A

Add a representative ordinary Apple image-input/Core ML path using the original model and same corpus. Pipeline A is descriptive and may include framework preprocessing.

### Pipeline B2

Implement the strongest reasonable conventional materialized-RGB baseline practical on the stable toolchain.

Candidate order:

1. RGBA16Float or another compact Float16 representation;
2. RGB/CHW buffer avoiding an unused alpha channel;
3. normalization folded into the conventional first stem where fair;
4. shared bridge matched to the C candidate.

Do not weaken B deliberately. Record why B2 is the strongest accepted conventional baseline.

## Gate

- current path component profile is reproducible;
- a clear bottleneck ranking exists;
- Pipeline A runs;
- B2 is correct and independently reviewed;
- profiler evidence is committed;
- no new optimization is accepted without being compared to B2 where applicable.

## Suggested commit

- `bench(profile): decompose MobileNetV2 boundaries and add B2`

---

# R2 — Persistent shared-buffer Core ML bridge

## Hypothesis

A persistent `MLMultiArray` view over a retained shared `MTLBuffer` will eliminate the current Swift array, repeated allocation, and 602,112 boxed assignments, materially reducing end-to-end latency without changing the model or precision.

## Required implementation

- Introduce a lifetime-safe `BufferBackedMultiArray` abstraction.
- Use `MLMultiArray(dataPointer:shape:dataType:strides:deallocator:)` over retained shared buffer storage.
- Use exact CHW shape `[48, 112, 112]` and correct strides.
- Create the wrapper once per persistent B/C activation buffer.
- Reuse the same feature provider/multiarray where Core ML permits.
- Guarantee GPU completion/visibility before prediction.
- Add deallocation/lifetime and wrong-stride tests.
- Preserve the current boxed bridge as C0/B1 for ablation.

## Benchmark

Compare matched pairs:

- B1 boxed versus B1 shared;
- C0 boxed versus C1 shared;
- strongest shared B versus shared C.

Measure the bridge component directly.

## Acceptance target

Accept if quality passes and at least one is true with confirmation evidence:

- bridge time falls by at least 5x;
- end-to-end p50 falls by at least 10% relative to the same path with boxed bridge;
- an equivalent strong measured result survives hostile review.

If the API or Core ML runtime copies internally, retain only if the measured result justifies it.

## Gate

- no element-by-element activation population remains in C1;
- B/C use matched shared bridge semantics;
- source and B/C parity pass;
- raw and profiler evidence committed;
- claims use “buffer-backed view,” not unproven “zero-copy.”

## Suggested commit

- `perf(bridge): reuse buffer-backed Core ML activations`

---

# R3 — IOSurface-backed Float16 activation bridge

## Hypothesis

An IOSurface-backed one-component Float16 activation shared between Metal and Core ML can reduce bridge overhead and activation traffic beyond C1, while preserving task behavior under a separately declared Float16 contract.

## Required implementation

- Derive a Float16-input version of the same unchanged tail graph.
- Validate source-layer lineage and output behavior.
- Allocate an IOSurface-backed `kCVPixelFormatType_OneComponent16Half` pixel buffer sized to represent `[48,112,112]`.
- Create an `MLMultiArray(pixelBuffer:shape:)` view.
- Create a live Metal texture/buffer view over the same surface.
- Make B2 and C2 write the same Float16 activation layout.
- Reuse resources across predictions.
- Keep Float32 C1 as the quality/control path.

## Quality gate

Predeclare before benchmarking:

- source-derived Float16 reference threshold;
- B2/C2 activation threshold;
- top-1/top-5 and probability-vector thresholds.

Do not use the existing Float32 threshold blindly if the precision is intentionally changed.

## Acceptance

Keep C2 only if it improves a matched shared B2/C2 end-to-end pair beyond noise and passes all quality requirements.

## Gate

- storage is demonstrably IOSurface-backed;
- Metal and Core ML share the declared surface;
- no CPU element loop exists;
- precision and quality tradeoffs are explicit;
- accepted or rejected with committed evidence.

## Suggested commit if accepted

- `perf(bridge): add IOSurface-backed Float16 activation path`

---

# R4 — Metal 4 GPU-timeline model-tail feasibility and implementation

## Goal

Determine whether the current stable Xcode 26.6 environment can run the MobileNetV2 tail as an `MTLPackage` from an `MTLTensor`, then integrate it with the native stem without a CPU activation round trip.

## Feasibility spike

Before changing production code:

1. locate and inspect `metal-package-builder`;
2. confirm exact supported source model formats;
3. determine whether the existing neural-network tail can be converted to an equivalent ML Program;
4. if needed, create a provenance-preserving ML Program tail from a reproducible source representation;
5. package a tiny test model and execute it with `MTL4MachineLearningCommandEncoder`;
6. verify tensor layout and output parity.

No Xcode/macOS beta installation is allowed in this milestone.

## Full implementation if feasible

- Create `MTLTensor` views over shared activation storage with explicit strides.
- Encode B2 or C native-stem work with Metal 4 compute.
- synchronize compute output with the ML pass using Metal 4 barriers/fences;
- run the same MTLPackage tail for B and C;
- avoid CPU activation readback and `MLModel.prediction` inside the measured path;
- read only final output required for classification;
- profile the unified GPU timeline.

## Failure behavior

If the current Apple source model cannot be represented as a supported ML Program without compromising provenance:

- document the exact tool/API blocker;
- retain R2/R3 as the stable result;
- do not install beta tools automatically;
- continue to R5 with the best stable bridge.

## Acceptance target

A successful C3 should target a competition-level improvement against the strongest matched B path, preferably at least 10% end-to-end or a comparable sustained-throughput result.

## Gate

Either:

- GPU-timeline tail runs with quality preserved and confirmed improvement; or
- a precise reproducible infeasibility report is committed and the stable path remains intact.

## Suggested commit if accepted

- `perf(metal4): keep native stem and model tail on GPU timeline`

---

# R5 — Polyphase 4:2:0 source-grid compiler

## Goal

Create the primary algorithmic contribution beyond ordinary kernel fusion.

## Required research

- Write the formal mapping from RGB-domain 3x3 taps to full-resolution Y and subsampled UV coordinates.
- Identify unique UV coordinates for each output phase.
- Generate aggregated chroma coefficients at compile time.
- Preserve per-tap/source offsets and bottom/right padding semantics.
- Implement a Double-precision CPU reference.
- Add procedural chroma-phase and edge corpus cases.
- Generate Metal coefficients/code from the same compiler representation.

## Experiment A — exact current sampling mode

Under the existing nearest-sited NV12 contract, aggregate repeated UV contributions exactly.

## Experiment B — optional interpolation-aware mode

If a defensible camera chroma-siting/interpolation contract is available, precompose linear chroma reconstruction into phase-specific native-grid coefficients.

Do not mix the two modes in one claim.

## Benchmark

Run only on the strongest accepted bridge/tail path so frontend changes can affect application-level results.

Measure:

- unique Y/UV reads;
- arithmetic operation count from generated operator metadata;
- GPU duration;
- frontend and end-to-end latency;
- activation/task parity.

## Gate

- exact reference parity under the declared mode;
- at least one accepted compiler transformation or a rigorous documented negative result;
- no claim based solely on theoretical operation count;
- prior-art section updated.

## Suggested commit if accepted

- `perf(yuv420): compile polyphase chroma geometry into the stem`

---

# R6 — Direct camera textures and continuous PlaneFuse Live

## Goal

Turn the technical result into a credible live Mobile AI experience.

## Camera input

- Map camera `CVPixelBuffer` Y and UV planes with `CVMetalTextureCache`.
- Retain Core Video texture wrappers through GPU completion.
- Perform crop/resize on GPU in source planes.
- Eliminate the current Swift Y/UV array copy and CPU resize.
- Reuse ring-buffer resources; no per-frame model setup.

## Application

Build a signed local macOS SwiftUI/AppKit experience with:

- continuous preview;
- actual top-3 labels and confidence;
- B2/C selection or split comparison;
- live capture-to-result and model latency;
- stored final benchmark panel clearly labeled as stored;
- RGB intermediate payload/allocated bytes;
- CPU activation-copy status;
- parity indicator;
- dropped-frame/FPS counters;
- a simple dataflow visualization.

The UI must remain usable even if profiling mode is disabled.

## Gate

- at least 300 continuous frames on a permitted physical camera;
- no fabricated metrics;
- no RGB reconstruction in C camera preprocessing;
- camera resource lifetime validated;
- user can understand the optimization within 15 seconds;
- screenshot and screen recording artifacts captured.

## Suggested commit

- `feat(demo): add continuous native-plane camera experience`

---

# R7 — Adversarial evaluation and final result selection

## Goal

Make the final claim difficult for a skeptical systems/ML reviewer to dismiss.

## Required evaluation

- complete A/B1/B2/C0/C1/C2/C3/C4 matrix for implemented paths;
- at least 64 quality inputs as defined in the benchmark contract;
- original Apple image-input parity;
- 3+ confirm batches and 5 final batches for the headline pair;
- paired bootstrap confidence interval;
- p50, p95, mean, MAD, absolute and percentage differences;
- frontend, bridge, tail, e2e, and capture-to-result where applicable;
- CPU bytes copied and logical/allocated resource bytes;
- profiler captures for strongest B and C;
- sustained 300-frame camera throughput;
- failures/disagreements catalog.

## Final selection

Choose the headline path by preregistered criteria, not by the largest isolated percentage.

The selected path must meet one competition-worthiness target from `SPEC_V2_ADDENDUM.md`.

## Hard stop

If no target is met, stop and ask the human whether to:

- submit the honest research result;
- pursue the optional Core AI beta branch;
- change the workload;
- or pivot the project.

## Suggested commit

- `bench(final): publish adversarial PlaneFuse Continuum evaluation`

---

# RX — Optional Core AI integrated-model moonshot

This is not in the automatic mandatory chain.

Start only with explicit human approval after the stable R2-R7 path is preserved.

Potential objective:

```text
NV12 Y + UV NDArray / IOSurface inputs
    -> custom embedded Metal native-plane stem
    -> re-authored model tail
    -> one .aimodel asset
```

Possible technologies:

- Core AI `NDArray.RawView` over `MTLBuffer`/IOSurface;
- custom Metal kernel embedded through Core AI PyTorch Extensions;
- Core AI compute stream;
- Core AI Debugger and Instrument;
- target-aware layouts/quantization.

Any beta result must be labeled beta and must not silently replace the stable submission path.

---

# R8 — Developer workflow, cleanup, and clean release

## Goal

Make a fresh engineer capable of reproducing the supported result without manual source edits.

## Required work

- finalize `./pf setup mobilenetv2`;
- make `inspect`, real `compile/setup`, `verify`, `bench`, `profile`, and `live` roles explicit;
- replace preparation-only wording where implementation has advanced;
- provide expected compact outputs;
- add unsupported-case tests;
- clean benchmark directories and indexes;
- document all dependencies and model/image licenses;
- run another fresh-clone release validation;
- add CI for platform-independent tests/docs if useful, while keeping hardware validation local;
- produce architecture diagrams from source-of-truth descriptions.

## Gate

- five-minute quickstart for a machine with Xcode and network access;
- no misleading command names;
- no broken evidence links;
- release validation passes from a clean clone;
- repository contains no model weights, secrets, PII, or unlicensed assets.

## Suggested commit

- `docs(dx): finalize one-command PlaneFuse workflow`

---

# R9 — Demo, README, Devpost, and final audits

## Required outputs

- judge-first README;
- final architecture diagram;
- final benchmark/quality tables;
- under-3-minute demo video and script;
- Devpost draft filled from verified claims;
- exact Mobile AI track mapping;
- limitations and prior-art language;
- clean public-ready repository;
- completed submission checklist;
- hostile Sol technical review;
- separate Sol hackathon-rubric review;
- fixes for all `FIX-FIRST` findings.

## Final hard stop

Stop before:

- changing repository visibility;
- publishing the video;
- submitting Devpost.

Provide the human with exact publication commands and a final claim summary.

## Suggested commits

- `docs(readme): present PlaneFuse Continuum evidence`
- `docs(devpost): prepare final hackathon submission`
- `chore(release): prepare PlaneFuse Continuum candidate`
