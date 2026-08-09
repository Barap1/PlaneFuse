# M11 release-preparation audit

Status: release candidate prepared; external publication and physical camera
capture remain human-controlled

## Technical audit

- M1 reference parity: PASS, 512 deterministic samples, max error
  `2.2204460492503131e-15` against `1e-12`.
- M4 fair B/C fixture: PASS, equal one-submission methodology and repeated
  end-to-end improvement preserved in `benchmarks/best.json`.
- M5 real pretrained proof: PASS, Apple MobileNetV2 ImageNet, unchanged tail,
  four hashed CC0 images, two 100-iteration accepted confirmations.
- M6 optimization discipline: PASS, two source-grid hypotheses rejected after
  end-to-end regressions; no threshold or baseline weakening.
- M7 reuse: PASS, shared inspection contract plus explicit second reference
  configuration; no false second-pretrained-model claim.
- M8 developer experience: PASS, `inspect`, preparation-only `compile`,
  asset-aware `verify`, and measured `bench` commands.
- M9 local experience: PASS with environment qualification, real sample mode
  and compiled/correctness-checked camera NV12 capture path.
- M10 evidence: PASS, current-state result, machine-readable matrix/history,
  non-PII environment snapshot, and synchronized claims ledger.

## Mobile AI dimensions

- Latency: measured frontend and end-to-end p50/p95 for fair B/C.
- Memory/intermediate elimination: observed B RGBA32Float intermediate is
  802,816 bytes; C records zero for that intermediate. No peak-memory claim.
- Arm64/on-device: release confirmation records arm64 Apple M5 Pro and local
  Core ML/Metal execution; no cloud dependency is required by the proof.
- Developer tooling: shared compatibility inspection plus reproducible CLI.
- Local AI experience: MobileNetV2 sample and camera adapter run locally; a
  physical camera video still requires a permitted device.

## Claims deliberately excluded

No power, energy, measured GPU-bandwidth, universal-model, MobileCLIP, or
second-pretrained-model claim is made. Arm Performix was not installed and no
system-wide software was changed.

## Human-controlled release items

- Approve any public GitHub push or external submission.
- On a permitted Apple-Silicon machine, run `./pf live --camera` and capture
  the optional under-three-minute demo if desired.
- Keep repository visibility and credentials unchanged until explicitly
  approved.
