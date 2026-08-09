# R5 polyphase 4:2:0 compiler evidence

Status: VERIFIED NEGATIVE RESULT

The R5 Experiment A compiler targets the declared nearest-sited NV12 contract. It
keeps nine full-resolution luma taps and each tap's source offset/validity guard,
and aggregates the repeated chroma contributions into four phase-specific UV
coefficients. The Double reference, compiled per-tap form, and polyphase form were
compared over three procedural 4:2:0 cases covering a uniform phase case, varied
chroma values, and luma/chroma edge extremes. The targeted test passed at 1e-9
Double tolerance.

The Metal candidate was measured only with the accepted Float32 buffer-backed
Core ML bridge and unchanged tail. End-to-end is the measured stem wall time plus
the matched shared-buffer tail prediction; paired differences are preserved in
each raw JSON artifact. GPU p50 is from `MTLCommandBuffer.gpuStartTime` and
`gpuEndTime`.

| Run | Native frontend p50 (ms) | Polyphase frontend p50 (ms) | Native e2e p50 (ms) | Polyphase e2e p50 (ms) | Polyphase e2e delta | Native/Polyphase GPU p50 (ms) | Max activation error |
|---|---:|---:|---:|---:|---:|---:|---:|
| Quick, 20 pairs | 0.7500 | 0.7734 | 2.0395 | 2.0797 | -1.97% | 0.2397 / 0.2338 | 3.3379e-6 |
| Confirm 1, 200 pairs | 0.7767 | 0.7667 | 2.0829 | 2.0683 | +0.70% | 0.2397 / 0.2335 | 6.1989e-6 |
| Confirm 2, 200 pairs | 0.7512 | 0.7529 | 2.0444 | 2.0517 | -0.36% | 0.2400 / 0.2338 | 6.1989e-6 |
| Confirm 3, 200 pairs | 0.7698 | 0.7713 | 2.0782 | 2.0851 | -0.33% | 0.2400 / 0.2336 | 6.1989e-6 |

The generated operator metadata is 9 Y read instructions, 9 UV read instructions,
and 27 weighted multiplications for the native representation versus 9 Y, 4 UV,
and 17 weighted multiplications for polyphase, with 4 unique chroma coordinates.
This is compiler/operator evidence only. GPU p50 is lower for polyphase, but the
three application-boundary confirmation batches are mixed and do not establish a
runtime latency win. R5 therefore closes as a rigorous documented negative result
for the current MobileNetV2 workload, while retaining the exact transformation as
an experimental compiler path for future workloads or execution boundaries.

Evidence:

- `benchmarks/results/r5-polyphase-quick.json`
- `benchmarks/results/r5-polyphase-confirm-1.json`
- `benchmarks/results/r5-polyphase-confirm-2.json`
- `benchmarks/results/r5-polyphase-confirm-3.json`
- `Tests/PlaneFuseCoreTests/NativePlaneCompilerTests.swift`
- `Sources/PlaneFuseCore/NativePlaneConv3x3.swift`
- `RESEARCH_FRONTIER.md`
