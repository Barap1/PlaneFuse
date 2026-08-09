# R1 bottleneck decomposition and baseline evidence

Status: VERIFIED diagnostic evidence; not a final competition headline.

Commands:

```bash
./pf profile mobilenetv2
./pf bench mobilenetv2 b2
```

Environment: arm64, Apple M5 Pro, macOS 26.6, Xcode 26.6, Swift 6.3.3. Both runs use five warmups, 20 measured iterations, and the same Core ML CPU-only tail. The component profile cycles through the 32-sample corpus and records 20 measured iterations; the B2 benchmark validates all 32 samples. The component profile isolates B's NV12 conversion and RGB stem into separate diagnostic submissions; the normal B/C benchmark remains the one-submission paired contract.

## Component p50 (milliseconds)

| Component | B1 RGBA32Float | C0 native-plane |
| --- | ---: | ---: |
| Input texture creation | 0.0600 | 0.0600 |
| RGB conversion | 0.3397 | — |
| Stem execution | 1.2315 | 0.7018 |
| GPU wait region | 1.6660 | 0.6923 |
| GPU execution duration | 1.0514 | 0.2420 |
| Activation buffer to Swift array | 0.0619 | 0.0434 |
| MLMultiArray allocation | 0.0020 | 0.0017 |
| Element population/boxing | 48.5663 | 48.4957 |
| Core ML tail prediction | 0.8362 | 0.8257 |
| Output extraction | 0.5732 | 0.5680 |
| Input-ready to result | 51.6957 | 50.6009 |

The dominant measured region is the element-by-element MLMultiArray population/boxing, at roughly 48 ms p50 on both paths. This is the R2 bridge target; the profile does not claim zero-copy or absence of internal Core ML copies.

## B2 conventional baseline

B2 materializes normalized RGB as planar Float32 `[3, 224, 224]`, avoiding B1's unused alpha channel while retaining the same native NV12 input, Float32 stem activation, unchanged Core ML tail, and one-submission B/C comparison.

- B2 p50: 51.3243 ms
- C0 p50: 51.3800 ms
- C relative to B2: 0.1085% slower in this quick batch; this is an inconclusive near-tie, not a claimed optimization win.
- B2 frontend p50: 0.2600 ms; C frontend p50: 0.2208 ms
- B2 logical RGB payload: 602,112 bytes; measured allocation: 606,208 bytes
- B2/C top-1 agreement: 1.0 over 32 samples
- maximum B2/C activation error: 9.2983e-6, below the unchanged 1e-5 GPU threshold
- independent source-derived stem parity: 4.0889e-5 B2 and 4.0412e-5 C, below the 1e-4 reference threshold

The first compact candidate, RGBA16Float, was rejected before acceptance because its maximum activation error was 0.01387036 against the unchanged 1e-5 GPU threshold. No quality threshold was changed to admit it.

## Accelerator trace

A separate `Metal System Trace` capture was run against the compiled `planefuse profile mobilenetv2` binary. `xctrace export --toc` verified a successful exit (`0`), the Metal System Trace template, and a 6.497-second capture on the local MacBook Pro. The committed `proof/r1-gpu-evidence.json` records the trace metadata, measured GPU durations, and resource allocation evidence; the raw trace was retained in the local temporary capture directory during this session.

Pipeline A remains the descriptive original Apple image-input path exercised by `./pf verify lineage`; it is not mixed into the B2/C0 performance pair.
