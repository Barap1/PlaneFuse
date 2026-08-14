# Proof artifacts

This is the public map of PlaneFuse's technical evidence. The files below are
committed, linkable, and intentionally separated by what they prove.

## Judge-facing proof path

Start here:

1. [PlaneFuse Live screenshot](assets/planefuse-live.png) — app-only capture of
   the local camera path, live predictions, metrics, representation comparison,
   and reviewed benchmark panel.
2. Demo video — placeholder; add the final recording link once available.
3. [Results and evidence](RESULTS_AND_EVIDENCE.md) — the compact technical
   summary and claim boundaries.
4. [Clean-clone reproduction](../proof/final/public-clone-reproduction.json) —
   fresh public-repository reproduction and sanitized results.
5. [Latency comparison](assets/latency-comparison.svg) — reviewed B2/C1/C1-SR
   p50 values.

Raw JSON, profiler, corpus, and batch artifacts remain available below for
deeper inspection.

| Artifact | What it proves | Evidence kind |
| --- | --- | --- |
| [PlaneFuse Live source](../Sources/PlaneFuseLive/PlaneFuseDashboardApp.swift) | A local AppKit camera application with live B2 and C1-SR paths | Source |
| [PlaneFuse Live screenshot](assets/planefuse-live.png) | Privacy-safe app-only capture with real camera state and stored reviewed panel | Presentation artifact |
| [System architecture](diagrams/planefuse-architecture.svg) | The materialized-RGB path and source-reuse path before the common tail | Generated diagram |
| [Source-reuse schedule](diagrams/source-reuse.svg) | Tile staging and reuse across output channels | Generated diagram |
| [Latency comparison](assets/latency-comparison.svg) | B2, C1, and C1-SR p50 values from the reviewed JSON | Generated graph |
| [RGB boundary](assets/rgb-intermediate.svg) | Full RGB intermediate allocation boundary, not total memory | Generated graph |
| [Source-reuse scaling](assets/source-reuse-scaling.svg) | Stem-only wall p50 as active output channels share staged source tiles | Generated graph |
| [Reviewed benchmark](../proof/r7.5-source-reuse-final-52db138-20260811T1605Z-confirm.json) | Five-batch R7.5 raw and aggregate timing record | Stored reviewed evidence |
| [Scaling aggregate](../proof/final/source-reuse-scaling.json) | Three-batch controlled C1/C1-SR channel-width result with parity and analytical reuse counts | Stored microbenchmark |
| [Scaling raw batches](../proof/final/source-reuse-scaling-batches/) | Independent raw Release samples behind the scaling aggregate | Stored microbenchmark inputs |
| [Target evaluation](../proof/r7.5-competition-targets.json) | Accepted benchmark result and documented scope limits | Stored reviewed evidence |
| [Quality conditions](../proof/r7-b2-c1-shared-quality-conditions.json) | B2/C1 quality conditions and retained disagreements | Stored validation |
| [Profiler summary](../proof/r7-final-shared-path-profile-repaired-conditions.json) | Resource boundary and command/encoder evidence | Stored profiler evidence |
| [Corpus manifest](../proof/m5-validation-corpus.json) | Fixed 64-input corpus, provenance, and hashes | Stored corpus record |
| [Read-only, model-based GPT-5.6 Sol adversarial review (not an external human audit)](../proof/r7.5-independent-review.md) | Model-based review outcome for the frozen result | Stored review |
| [Reproducibility record](../proof/final/reproducibility.json) | Toolchain, hashes, commands, and checker paths | Compact proof record |
| [Clean-clone reproduction](../proof/final/public-clone-reproduction.json) | Fresh public-repository clone with no local project state and quick/full results | Release proof |
| [Retained public-clone evidence](../proof/final/public-clone-reproduction/7eb1c3d30424adb6aff844ed950e98d5a036b9f3/) | Checked aggregate, five raw batches, and canonical batch hashes behind the fresh result | Recomputable release proof |
| [Integration example](../Examples/PlaneFuseIntegration/README.md) | Compile-checked facade usage and camera handoff boundary | Integration source |
| [Reproduction instructions](REPRODUCIBILITY.md) | Quick and full rerun paths without overwriting history | Reproduction guide |

## Evidence status

The graphs and results page are generated from committed source artifacts. A
stored benchmark is not a current live measurement. A reproduction run is
newly collected evidence and must report its own hardware and toolchain.

## Visual capture

The committed capture is an app-only, privacy-safe PlaneFuse Live window. To
make a new local capture, launch:

```bash
./pf live --app
```
