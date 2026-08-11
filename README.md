# PlaneFuse

PlaneFuse recompiles a compatible pretrained RGB vision stem to operate
directly on native NV12 camera planes, then reuses source tiles across learned
channels instead of materializing a full RGB input.

**11.8% lower matched p50 latency** on the reviewed MobileNetV2/NV12
comparison, with no retraining, the same pretrained tail, and no full-RGB
intermediate in the PlaneFuse path.

## See it

On a supported Apple-Silicon Mac with camera permission and local model assets:

```bash
./pf setup mobilenetv2
./pf live --app
```

`PlaneFuse Live` is a local AppKit dashboard. It shows the real NV12 camera
preview, actual top-3 predictions, selected B2/PlaneFuse mode, comparison-loop
FPS, post-resize-to-result timing, parity, and resource boundaries. If camera
permission or assets are unavailable, it shows a friendly unavailable state and
does not fabricate live metrics. Stored R7.5 evidence is labeled separately.

## Why this exists

Most camera AI paths look like:

```text
camera NV12 → materialized RGB → learned RGB stem → model tail
```

PlaneFuse composes the YUV-to-RGB affine transform, normalization, and learned
first stem into one source-domain operator:

```text
camera NV12 → transformed/reuse-aware learned stem → unchanged model tail
```

The supported MobileNetV2 stem is compiled analytically; the tail and weights
are unchanged. The implementation and source-reuse schedule are explained in
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Reviewed result

| Path | Matched Release p50 | Meaning |
| --- | ---: | --- |
| B2 | 1.737875 ms | strongest credible materialized-RGB baseline |
| C1 | 1.633458 ms | accepted native-plane stem with persistent shared activation |
| C1-SR | 1.532583 ms | final source-reuse variant |

C1-SR is 11.8128% below B2 and 6.1755% below C1 by the difference of marginal
p50 values. The paired B2 − C1-SR median bootstrap 95% CI is `[0.180250,
0.198792] ms`; it is a different estimand and is shown separately.

Quality over the fixed 64-input corpus: 32 provenance-bearing real and 32
deterministic procedural inputs, top-1/top-5-set/top-5-ranking agreement all
1.0, and activation maximum error `5.960464e-6`. Independent hostile review:
**SHIP**, no findings.

## Evidence

Start with [`docs/JUDGE_EVIDENCE.md`](docs/JUDGE_EVIDENCE.md), generated from
the authoritative JSON artifacts. The architecture, claims, raw evidence, and
review navigation are linked from [`proof/evidence-index.md`](proof/evidence-index.md).

## Reproduce in five minutes

```bash
./pf doctor
./pf setup mobilenetv2
./pf inspect mobilenetv2
./pf verify
./pf bench quick
./pf evidence --check
```

For a clean-clone release check, run `./scripts/release_validate.sh`. It
recreates local model assets, builds in Release where timing matters, runs the
tests and sample workload, and writes verbose logs under `artifacts/logs/`.

## CLI

- `./pf doctor` — supported machine/toolchain preflight.
- `./pf setup mobilenetv2` — create/reuse the project-local environment and
  derive/compile the local model assets.
- `./pf inspect mobilenetv2` — inspect the supported model/stem contract.
- `./pf compile mobilenetv2` — report the preparation contract and assets.
- `./pf verify` / `./pf verify lineage` — run model and source-lineage checks.
- `./pf bench quick` — run the compact Release benchmark harness.
- `./pf evidence` — regenerate and print the judge evidence page.
- `./pf live --sample` — run the local sample workload.
- `./pf live --app` — open the Release judge-facing camera dashboard.

If model assets are missing, setup is required. Unsupported formats, toolchains,
or camera conditions fail clearly; this is a reproducible MobileNetV2 path, not
a universal graph compiler.

## Negative results and limits

Float16 failed its declared quality gate. Metal 4 could not consume this model
format on the stable toolchain. The polyphase compiler was mathematically
correct but produced no stable end-to-end win. Naïve direct camera-space fusion
was slower because removing an intermediate also removed useful reuse.

MobileNetV2 is the only claimed pretrained workload on one Apple-Silicon
environment. Pipeline A is faster under its distinct pre-rendered image-input
boundary and is contextual. T2/T3 were not met or established. No power,
bandwidth, universal-model, or Apple-wide speed claim is made.

## Project and publication status

Performance research is frozen after the accepted R7.5 result and independent
SHIP review. Repository publication, default-branch selection, video upload,
and Devpost submission remain human-controlled. See
[`STATUS.md`](STATUS.md), [`SUBMISSION_CHECKLIST.md`](SUBMISSION_CHECKLIST.md),
and [`docs/PUBLICATION_PLAN.md`](docs/PUBLICATION_PLAN.md).

## License and notices

Source is MIT licensed. Model, image, and third-party terms are collected in
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).
