# Devpost draft — R9 review copy

Status: INTERNAL DRAFT. Do not publish.

## One-line description

PlaneFuse selectively removes camera/model representation boundaries on Apple Silicon while preserving the pretrained model tail.

## What is demonstrated

PlaneFuse Live shows a local NV12 camera path, real top-3 inference output, precise live timing labels, parity, and the RGB/CPU-copy resource boundary. The strongest measured same-workload result is the reviewed R7.5 C1-SR source-reuse schedule.

## Verified result

The independent SHIP review accepted the R7.5 evidence: C1-SR measured 6.1755% below accepted C1 and 11.8128% below fresh B2 on the fixed Release protocol, with full 64-sample quality agreement and activation max error 5.960464e-6. This is a MobileNetV2/NV12 result, not a universal claim.

## Honest framing

The original repaired R7 matched B2/C1 result was 2.115766% in C1's favor, below the 10% target. Pipeline A is faster under a different pre-rendered image-input boundary. R6.5 direct camera-space fusion was a negative result because the removed intermediate had reuse value. T2/T3 were not met or established; T4 was not invoked.

## Demo plan placeholder

- [ ] Human-approved camera capture on the intended Apple-Silicon machine.
- [ ] Human-approved under-three-minute video capture.
- [ ] Human-approved external upload.

Do not replace these placeholders with invented live measurements.
