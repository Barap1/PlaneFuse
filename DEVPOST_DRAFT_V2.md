# PlaneFuse Devpost draft — evidence-controlled working copy

Do not publish this file unchanged. Codex must replace bracketed fields only from verified Phase 2 evidence and synchronize every quantitative statement with `CLAIMS.md`.

## Project title

PlaneFuse Continuum

## One-line description

PlaneFuse compiles a pretrained RGB vision model toward the camera's native NV12 planes and keeps the first activation in shared accelerator storage, eliminating unnecessary RGB and CPU tensor-copy work on Apple Silicon.

## Track

Mobile AI

## Inspiration

Arm-powered phones and laptops increasingly run camera AI locally, but the software path often retains assumptions from desktop training pipelines. A camera produces compact luma and chroma planes. A model expects dense RGB. The device reconstructs RGB, normalizes it, and immediately applies a learned transformation.

We asked a systems question:

> What if the model were compiled toward the physical representation the camera already provides?

## What it does

PlaneFuse analyzes a compatible pretrained model stem and composes:

- YUV-to-RGB conversion;
- channel normalization;
- the first learned convolution;
- BatchNorm;
- ReLU6;

into a native-plane operator. The optimized path reads Y and UV directly and produces the exact first activation expected by the unchanged model tail.

PlaneFuse Continuum extends that idea across the next boundary by replacing the element-by-element CPU activation bridge with [BUFFER-BACKED / IOSURFACE / METAL-4 RESULT].

The live macOS experience runs fully local camera classification and compares a strong conventional materialized-RGB pipeline against PlaneFuse on the same frames.

## How we built it

### 1. Exact source-domain compilation

For affine source conversion `r = A s + c`, normalization `x = D(r - mu)`, and learned linear operation `h = W x + b`, PlaneFuse generates:

```text
W_source = W D A
b_source = b + W D(c - mu)
```

The spatial compiler applies this per convolution tap and preserves padding semantics.

### 2. Real pretrained model lineage

The primary workload is Apple's MobileNetV2 ImageNet model. The preparation tool:

- verifies the source SHA-256 and graph structure;
- validates its bottom/right-heavy SAME padding;
- exports the actual pretrained 3x3 Conv and BatchNorm parameters;
- derives an independently checkable stem, full model, and unchanged tail;
- records hashes and exact tensor contracts.

### 3. Native Metal runtime

Pipeline B materializes a conventional RGB representation and runs the ordinary learned stem. Pipeline C reads camera Y and UV planes and directly writes the `48 x 112 x 112` activation expected by the same tail.

### 4. Continuum bridge

[Describe the strongest accepted Phase 2 bridge precisely. Never use “zero-copy” unless the evidence proves the named boundary.]

### 5. Polyphase 4:2:0 compiler

[Include only if R5 is accepted.] PlaneFuse groups chroma contributions by their physical UV-grid coordinate, generating phase-specific native-grid coefficients instead of repeatedly emulating reconstructed RGB samples.

## Measured results

### Current verified pre-Phase2 reference

Before Phase 2, the release-state MobileNetV2 run on Apple M5 Pro measured:

- frontend p50: 0.50075 ms B versus 0.22821 ms C;
- end-to-end p50: 51.8460 ms B versus 50.8605 ms C;
- 802,816 logical RGBA32Float payload bytes in B versus no full-RGB intermediate in C;
- max B/C activation difference `9.298325e-6`;
- 4/4 top-1 agreement on the original hashed smoke corpus.

These are historical verified values, not necessarily the final headline.

### Final Phase 2 result

Replace this section with the final preregistered strongest B-versus-C pair:

| Metric | Strong conventional B | PlaneFuse | Difference |
|---|---:|---:|---:|
| Frontend p50 | [ ] | [ ] | [ ] |
| Bridge p50 | [ ] | [ ] | [ ] |
| End-to-end p50 | [ ] | [ ] | [ ] |
| End-to-end p95 | [ ] | [ ] | [ ] |
| Capture-to-result p50 | [ ] | [ ] | [ ] |
| Sustained FPS | [ ] | [ ] | [ ] |
| Full RGB intermediate | [ ] | [ ] | [ ] |
| CPU activation-copy bytes | [ ] | [ ] | [ ] |
| Top-1 agreement | — | [ ] | — |
| Top-5 agreement | — | [ ] | — |
| Paired 95% CI | — | [ ] | — |

Hardware/software: [exact non-PII environment]

Raw evidence: [paths]

## Why this is Arm-specific

PlaneFuse targets the data and execution path of an Arm-powered client device:

- camera-native bi-planar YUV input;
- Apple-Silicon unified memory;
- custom Metal compute;
- local Core ML/Metal model execution;
- optional Metal 4 tensor/ML-command integration;
- no cloud inference dependency.

The broader technique applies to camera-first Arm clients where model input representations and native sensor/video formats do not match.

## Developer experience

Supported workflow:

```bash
./pf setup mobilenetv2
./pf inspect mobilenetv2
./pf verify mobilenetv2
./pf bench final
./pf live --camera
```

Unsupported geometry, padding, normalization, precision, or source lineage fails explicitly rather than silently changing model semantics.

## Challenges

- preserving exact padding and chroma semantics;
- proving the tail really comes from the inspected pretrained model;
- making benchmark submissions and synchronization fair;
- separating GPU arithmetic parity from backend-specific Core ML reference parity;
- preventing an isolated kernel win from being presented as an end-to-end win;
- [Phase 2 bridge/Metal 4 challenge].

## Accomplishments

Use only verified items:

- transformed a real pretrained 3x3/stride-2 Conv+BN+ReLU6 stem without retraining;
- preserved the unchanged source-derived classifier tail;
- removed the full RGB intermediate from the optimized path;
- [removed boxed bridge / shared IOSurface / GPU-timeline result];
- built fair baselines and preserved rejected experiments;
- built a continuous local camera experience;
- made the workflow reproducible from a clean clone.

## What we learned

The largest lesson was that performance claims depend on boundaries. An early result looked much larger because the conventional path paid for an extra command submission. We corrected the benchmark, superseded the claim, and rebuilt the evaluation around equal work.

Phase 2 showed [insert evidence-based lesson about bridge/timeline/polyphase].

## What's next

- extend the compatibility family to more pretrained stems;
- support additional YUV matrices, ranges, and chroma siting;
- investigate Core AI custom-kernel model assets on stable OS releases;
- evaluate Android/Vulkan or other Arm client backends;
- explore temporal native-plane reuse as a separate research direction.

## Built with

- Swift
- Metal
- Core Video / AVFoundation
- Core ML
- Core ML Tools
- [Metal 4 MTLTensor/ML encoder if accepted]
- Apple Silicon / Arm64

## Disclosures and limitations

- No universal-model claim.
- No world-first claim.
- No power/energy claim unless separately measured.
- No measured-bandwidth claim unless profiler evidence exists.
- Results are scoped to the declared device, model, input, and software environment.
- [Any beta path is explicitly labeled and not required for the stable result.]
