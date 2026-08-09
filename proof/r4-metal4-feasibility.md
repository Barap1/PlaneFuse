# R4 Metal 4 GPU-timeline tail feasibility

Status: INFEASIBLE on the stable Xcode 26.6 toolchain; R4 gate passed by
reproducible blocker report.

Environment: macOS 26.6, Xcode 26.6. No beta tooling or system changes were
installed.

## Tool availability

The stable toolchain contains:

- `metal-package-builder`;
- `MTLTensor` and `MTL4MachineLearningCommandEncoder` headers;
- `metal-package-builder -ml` for ML Metal packages.

## Exact blocker

The provenance-preserving derived tail is a Core ML specification-version-1
`neuralNetworkClassifier`/Espresso model. The following attempts were run
against the unchanged `models/derived/MobileNetV2Tail.mlmodel`:

1. `coremlc upgrade ...` failed with `upgrade command failed`.
2. `coremlc compile ... --add-mlprogram-if-eligible force` failed while adding
   an ML Program to the compiled model.
3. Normal stable compilation produced `model.espresso.*` and
   `neural_network_optionals/coremldata.bin`, not an ML Program package with a
   manifest that `metal-package-builder` can consume.
4. `coremltools==9.0` cannot infer a source framework when asked to convert
   this already-authored Core ML spec to `mlprogram`; the original training
   framework/source representation is not present in the repository.

This is a format/provenance blocker, not a performance result. Re-authoring
the tail from an untracked source framework or installing beta tooling would
change the declared model boundary and is outside the accepted R4 scope.

Decision: retain the accepted Float32 R2 bridge and continue to R5. Do not
claim GPU-timeline tail execution.
