# M10 evidence index

Status: accepted evidence package

## Reproducibility

```bash
./pf doctor
./pf build
./pf test quick
./pf verify
./pf inspect mobilenetv2
./pf compile mobilenetv2
./pf bench mobilenetv2 confirm
./pf live --sample
```

The final current-state MobileNetV2 confirmation is committed as
`benchmarks/results/m10-mobilenetv2-confirm-current.json` and summarized in
`benchmarks/final-matrix.json`. It uses 10 warmups, 100 measured iterations,
four hashed real images, Release configuration, arm64 Apple M5 Pro, macOS
26.6/Xcode 26.6.

## Defensible measured result

At commit `139c92a`, equal-submission B/C MobileNetV2 p50 was 51.8460 ms / 50.8605
ms end-to-end, a 1.90098% C reduction. Frontend p50 was 0.50075 ms / 0.22821
ms, a 54.4267% C reduction. B allocated an 802,816-byte RGBA32Float
intermediate; C recorded zero bytes for that intermediate. B/C max activation
error was `9.298325e-6`, task agreement was 100%, and the independent CPU-only
source-derived reference errors were `3.904105e-5` / `3.892183e-5`.

The two accepted M5 confirmation batches remain the primary repeated claim and
are preserved separately in `benchmarks/results/m5-mobilenetv2-confirm1.json`
and `benchmarks/results/m5-mobilenetv2-confirm2.json`. The current run is a
release-state confirmation, not a replacement of that two-batch evidence.

## Structural and quality evidence

- `proof/m5-mobilenetv2.md`: real-model boundary, lineage, corpus, and parity.
- `proof/m7-reusability.md`: common configuration contract and explicit limits.
- `proof/m8-developer-workflow.md`: reproducible inspect/compile/verify/bench.
- `proof/m9-live.md`: local sample and camera NV12 path, including permission
  qualification.
- `benchmarks/history.jsonl`: append-only machine-readable run history.
- `artifacts/environment.json`: non-PII local environment snapshot.

No power, energy, or measured GPU-bandwidth claim is made. The memory statement
is limited to the observed RGBA32Float intermediate allocation and the
structural no-RGB dataflow; it is not a peak-memory claim.
