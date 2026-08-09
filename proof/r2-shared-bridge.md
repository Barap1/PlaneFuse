# R2 persistent shared-buffer Core ML bridge

Status: EXPERIMENTAL pending hostile R2 review.

Command:

```bash
./pf bridge mobilenetv2
```

The benchmark is a matched B2/C0 ablation. B2 and C0 retain the existing
boxed `MLMultiArray` control. B2/C1 use one persistent
`BufferBackedMultiArray` view over each retained shared activation `MTLBuffer`.
GPU completion is awaited before prediction. Both bridge forms use the same
compiled Float32 Core ML tail and the same 20 measured iterations over the
32-sample corpus cycle.

## Quick result (p50)

| Pair | Boxed | Buffer-backed view | Reduction |
| --- | ---: | ---: | ---: |
| B2 handoff-to-result | 49.4640 ms | 1.3279 ms | 97.3155% |
| C0 handoff-to-result | 49.4789 ms | 1.3377 ms | 97.2964% |
| B2 input-to-result | 50.4438 ms | 2.2206 ms | 95.5979% |
| C0 input-to-result | 50.3103 ms | 2.1327 ms | 95.7609% |

The persistent view construction itself measured 0.0113 ms for B and 0.0015 ms
for C in this quick run and is reported separately rather than hidden in the
per-iteration candidate timing.

Quality and layout checks:

- boxed B/C top-1 agreement: 1.0;
- shared B/C top-1 agreement: 1.0;
- shared-versus-boxed top-1 agreement: 1.0;
- maximum shared B/C activation error: `4.7684e-6`, below the unchanged `1e-5` GPU threshold;
- exact view shape: `[48, 112, 112]`;
- exact contiguous strides: `[12544, 112, 1]`;
- measured B/C activation allocation: `2,408,448` bytes each;
- wrong-stride rejection and retained-storage tests pass.

## Confirmation

Three independent batches used 20 warmups and 200 measured iterations each.
All 600 paired differences are preserved in
`benchmarks/results/r2-mobilenetv2-shared-bridge-confirm.json`.

| Batch | B2 handoff reduction | C0 handoff reduction | B2 end-to-end reduction | C0 end-to-end reduction |
| ---: | ---: | ---: | ---: | ---: |
| 1 | 97.3257% | 97.3299% | 95.6399% | 95.7913% |
| 2 | 97.3387% | 97.3597% | 95.7030% | 95.8442% |
| 3 | 97.3423% | 97.3282% | 95.6786% | 95.8166% |

This evidence supports “buffer-backed multiarray view” and “no
element-by-element CPU copy in PlaneFuse.” It does not claim that Core ML
performs no internal copy.

The raw artifacts were generated from commit `9ea359d` and are indexed as
`EXPERIMENTAL` until the R2 hostile review accepts the lifetime and fairness
methodology.
