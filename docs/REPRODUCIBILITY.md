# Reproducibility

PlaneFuse keeps the reviewed R7.5 result immutable. New runs write to a fresh
directory under `artifacts/reproduction/` and are compared by structure and
quality, not expected to reproduce the same microseconds on every machine.

## Requirements

- Apple Silicon macOS with Swift and Xcode command line tools.
- Camera permission is needed only for `./pf live --app` and physical-camera
  commands.
- The bundled MobileNetV2 setup downloads the Apple model and requires network
  access once. Inference and verification run locally after assets are present.

## Quick verification

```bash
git clone https://github.com/Barap1/PlaneFuse.git
cd PlaneFuse

./pf doctor
./pf setup mobilenetv2
./pf reproduce quick
./pf evidence --check
```

`pf setup mobilenetv2` creates or reuses `.venv`, installs the pinned
`coremltools` version, downloads the Apple MobileNetV2 model, checks its
SHA-256, prepares the stem and tail assets, compiles the three Core ML models,
and validates the derived manifest. Detailed setup output is kept under
`artifacts/logs/`.

Quick output is stored in a timestamped directory with a benchmark JSON and a
run log. The quick benchmark is a smoke check, not the frozen headline result.

## Full reviewed-protocol reproduction

```bash
./pf reproduce final
```

This wrapper verifies the environment, prepares the model, builds the Release
targets, checks model lineage, runs five independent R7.5 three-way batches,
aggregates the raw records, and checks the public evidence path. It writes:

```text
artifacts/reproduction/<timestamp>/r7.5-batches/
artifacts/reproduction/<timestamp>/r7.5-final.json
artifacts/reproduction/<timestamp>/run.log
```

The wrapper deliberately passes a new output directory to the existing
R7.5 harness. It never overwrites the accepted files under `proof/`.

## What a successful reproduction means

- the same Release paths compile on arm64;
- the MobileNetV2 source, derived assets, and 64-input corpus hashes verify;
- B2 and C1-SR use the declared shared activation and Core ML tail boundary;
- activation and output quality checks pass under the existing contract;
- five batches contain balanced path order and 240 measured triples each;
- a new result is available for comparison, with hardware variability reported
  instead of hidden.

## Frozen reference

The reviewed record is
`proof/r7.5-source-reuse-final-52db138-20260811T1605Z-confirm.json`.
It reports B2 p50 `1.737875 ms`, C1 p50 `1.633458 ms`, and C1-SR p50
`1.532583 ms`, with C1-SR 11.8128% lower than B2 by marginal p50. The
reviewed environment was arm64 Apple Silicon on macOS 26.6.1 with Xcode 26.6
and Swift 6.3.3. The complete hashes and checker paths are in
`proof/final/reproducibility.json`.
