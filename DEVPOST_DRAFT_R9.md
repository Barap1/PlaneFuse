# PlaneFuse — Devpost submission draft

Status: INTERNAL DRAFT — HUMAN PUBLICATION REQUIRED

## Inspiration / Problem

Camera sensors commonly deliver NV12/YUV planes while pretrained vision models
are authored for RGB. A conventional path expands the camera representation,
then feeds RGB into the learned stem. That boundary moves a large amount of
data before the model has done any useful work.

## What PlaneFuse does

PlaneFuse analytically composes the YUV-to-RGB affine transform, model
normalization, and the first learned MobileNetV2 stem. The generated operator
reads native NV12 Y/UV planes directly, stages source tiles cooperatively, and
reuses those source values across output channels. It keeps the pretrained
weights and unchanged model tail. There is no retraining.

Before:

```text
NV12 → Float32 RGB → RGB stem → persistent activation → Core ML tail
```

After:

```text
NV12 → source-reuse transformed stem → persistent activation → same Core ML tail
```

## How we built it

The implementation is local Swift, Metal, Core ML, AVFoundation, and
CVMetalTextureCache on Apple Silicon/Arm. The stem writes a persistent
48×112×112 Float32 activation through a shared buffer-backed `MLMultiArray`.
The benchmark harness uses a deterministic 64-input corpus, independent
Release processes, raw paired records, and machine-readable checkers.
`PlaneFuse Live` is a local AppKit camera dashboard that keeps live runtime
values separate from stored reviewed evidence.

## Final result

The reviewed R7.5 confirmation measured:

- B2 matched p50: **1.737875 ms**
- accepted C1 matched p50: **1.633458 ms**
- C1-SR matched p50: **1.532583 ms**
- C1-SR: **6.1755% below C1** and **11.8128% below B2** by marginal p50
- paired B2 − C1-SR median bootstrap 95% CI: **[0.180250, 0.198792] ms**

The percentage and paired interval are different estimands and are reported
separately. B2 materializes 602,112 logical RGB payload bytes and records
606,208 Metal-allocated bytes; C1-SR materializes no full RGB intermediate.

## Validation

Across 64 fixed inputs — 32 provenance-bearing real images and 32 deterministic
procedural stress inputs — C1-SR versus C1 recorded top-1, top-5 set, and top-5
ranking agreement of **1.0**, with activation maximum absolute error
`5.960464e-6`. Both paths use the same pretrained tail and `.all` Core ML
policy. The final protocol used five independent Release processes, 20 warmup
triples, 240 measured triples, all six path permutations, and a deterministic
10,000-replicate paired bootstrap. An independent hostile technical review
returned **SHIP** with no findings.

## What failed / what we learned

Float16 was rejected by its predeclared quality gate. Metal 4 could not consume
this model format on the stable toolchain. The polyphase 4:2:0 compiler was
mathematically correct and reduced generated UV work, but did not establish a
stable end-to-end win. R6.5 direct camera-space fusion was slower than a fair
source-space materialized-RGB baseline.

The important lesson is reuse economics: deleting an intermediate can also
delete spatial or channel reuse. C1-SR solved the measured problem by retaining
native-plane input while restoring source reuse in the execution schedule.

## Arm relevance

Apple Silicon is an Arm target. This project focuses on a concrete mobile-style
camera/vision boundary: native sensor representation, learned preprocessing,
memory movement, and local accelerator execution. The result is measured on one
Apple-Silicon environment and one pretrained workload; it is not generalized to
all Arm devices or models.

## Why it matters

The technique could be useful for continuous on-device vision in accessibility,
robotics, smart cameras, AR, and industrial inspection. These are potential
applications, not measured deployments or performance guarantees.

## Challenges

The hard parts were preserving color-range, chroma-siting, resize, padding,
normalization, layout, and model-tail semantics while changing the first
operator; building a fair B2 baseline; and proving a small latency difference
with independent processes and paired statistics. The negative camera-space
result prevented a misleading “fusion always wins” story.

## Accomplishments

- A no-retraining analytical transform of a real pretrained MobileNetV2 stem.
- A source-reuse Metal schedule over native NV12 planes.
- An 11.8% reviewed matched p50 result versus the strongest B2 baseline.
- Full 64-input parity evidence and independent hostile review.
- A local PlaneFuse Live camera experience with honest live/stored boundaries.
- Reproducible setup, checks, benchmark artifacts, and a judge-facing evidence page.

## Reproduce

```bash
git clone <repository-url>
cd PlaneFuse
./pf doctor
./pf setup mobilenetv2
./pf inspect mobilenetv2
./pf verify
./pf bench quick
./pf live --app
```

The repository's [`docs/JUDGE_EVIDENCE.md`](docs/JUDGE_EVIDENCE.md) links the
authoritative artifacts and exact verification commands.

## Limitations and next steps

MobileNetV2 is the only claimed pretrained workload. Pipeline A is faster under
its distinct pre-rendered image-input boundary and is contextual. T2/T3 were
not met or established; T4 was not invoked. No power, bandwidth, universal
speedup, or Apple-wide claim is made. The next engineering step is broader
compatibility and model coverage with the same proof discipline.

## Publication note

The repository, video, and Devpost entry remain private/internal until a human
selects the privacy-safe history strategy and approves publication.
