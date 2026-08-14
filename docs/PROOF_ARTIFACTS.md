# Proof artifacts

This is the public map of PlaneFuse's technical evidence. The files below are
committed, linkable, and intentionally separated by what they prove.

| Artifact | What it proves | Evidence kind |
| --- | --- | --- |
| [PlaneFuse Live source](../Sources/PlaneFuseLive/PlaneFuseDashboardApp.swift) | A local AppKit camera application with live B2 and C1-SR paths | Source |
| [System architecture](diagrams/planefuse-architecture.svg) | The materialized-RGB path and source-reuse path before the common tail | Generated diagram |
| [Source-reuse schedule](diagrams/source-reuse.svg) | Tile staging and reuse across output channels | Generated diagram |
| [Latency comparison](assets/latency-comparison.svg) | B2, C1, and C1-SR p50 values from the reviewed JSON | Generated graph |
| [RGB boundary](assets/rgb-intermediate.svg) | Full RGB intermediate allocation boundary, not total memory | Generated graph |
| [Source-reuse scaling](assets/source-reuse-scaling.svg) | Stem-only wall p50 as active output channels share staged source tiles | Generated graph |
| [Reviewed benchmark](../proof/r7.5-source-reuse-final-52db138-20260811T1605Z-confirm.json) | Five-batch R7.5 raw and aggregate timing record | Stored reviewed evidence |
| [Scaling aggregate](../proof/final/source-reuse-scaling.json) | Three-batch controlled C1/C1-SR channel-width result with parity and analytical reuse counts | Stored microbenchmark |
| [Scaling raw batches](../proof/final/source-reuse-scaling-batches/) | Independent raw Release samples behind the scaling aggregate | Stored microbenchmark inputs |
| [Target evaluation](../proof/r7.5-competition-targets.json) | T1 status and the declared limits of T2 and T3 | Stored reviewed evidence |
| [Quality conditions](../proof/r7-b2-c1-shared-quality-conditions.json) | B2/C1 quality conditions and retained disagreements | Stored validation |
| [Profiler summary](../proof/r7-final-shared-path-profile-repaired-conditions.json) | Resource boundary and command/encoder evidence | Stored profiler evidence |
| [Corpus manifest](../proof/m5-validation-corpus.json) | Fixed 64-input corpus, provenance, and hashes | Stored corpus record |
| [Independent review](../proof/r7.5-independent-review.md) | Technical review outcome for the frozen result | Stored review |
| [Reproducibility record](../proof/final/reproducibility.json) | Toolchain, hashes, commands, and checker paths | Compact proof record |
| [Public-clone reproduction](../proof/final/public-clone-reproduction.json) | Sanitized stranger-from-scratch GitHub clone and fresh quick/full results | Release proof |
| [Integration example](../Examples/PlaneFuseIntegration/README.md) | Compile-checked facade usage and camera handoff boundary | Integration source |
| [Reproduction instructions](REPRODUCIBILITY.md) | Quick and full rerun paths without overwriting history | Reproduction guide |

## Evidence status

The graphs and results page are generated from committed source artifacts. A
stored benchmark is not a current live measurement. A reproduction run is
newly collected evidence and must report its own hardware and toolchain.

## Visual capture

The final sanitized PlaneFuse Live screenshot is a human capture step because
camera frames can contain private surroundings. The application can be launched
with:

```bash
./pf live --app
```

The repository intentionally does not fabricate a screenshot or upload one.
After local review, a human can add a sanitized capture to `docs/assets/` for
the submission package.
