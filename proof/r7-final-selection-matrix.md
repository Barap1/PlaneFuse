# R7 final A/B/C selection matrix

Status: historical R7 selection matrix. R7.5 supersedes it as the accepted
headline and passes T1 through independent SHIP review.

| Row | Path and bridge | Precision/intermediate | Evidence/result | Disposition | Matched final? |
|---|---|---|---|---|---|
| A | Original Core ML image input | Framework-managed image path | `proof/r7-final-pipeline-a-current.json`; p50 1.1483 ms | Contextual only; distinct boundary | No |
| B1 | NV12 → RGBA32Float RGB stem; historical boxed/current bridge | Float32; full RGBA image | `benchmarks/results/r1-mobilenetv2-components.json` | Superseded by compact B2 | No |
| B2 | NV12 → normalized CHW RGB stem; persistent shared activation | Float32; 602112 logical / 606208 allocated RGB bytes | `proof/r7-final-b2-c1-shared-repaired-conditions.json`; historical condition-complete p50 1.5952 ms | Strongest credible conventional B for historical R7; superseded as headline by R7.5 | Yes |
| C0 | NV12 → native stem; boxed MLMultiArray | Float32; no full RGB, boxed bridge | `benchmarks/results/r1-mobilenetv2-components.json`, `proof/r2-shared-bridge.md` | Superseded boxed ablation | No |
| C1 | NV12 → native-plane stem; persistent shared activation | Float32; no full RGB | `proof/r7-final-b2-c1-shared-repaired-conditions.json`; historical condition-complete p50 1.5614 ms | Strongest stable pre-R7.5 C; superseded as headline by C1-SR | Yes |
| C2 | Native stem + IOSurface/Float16 bridge | Float16 candidate | `proof/r3-float16-feasibility.json` | Rejected on quality threshold | No |
| C3 | Native stem + Metal 4 tail | Intended Float32 | `proof/r4-metal4-feasibility.json` | Infeasible on stable toolchain | No |
| C4 | Polyphase native-plane stem | Float32; no full RGB | `proof/r5-polyphase.json` and corrected confirmations | No stable e2e win; rejected/superseded | No |

R6.5 direct camera-space fusion remains a separately documented negative
extension in `proof/r6.5-camera-space.json`; it is not silently promoted into
this matrix.
