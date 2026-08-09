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
| B2 handoff-to-result | 48.9133 ms | 1.3296 ms | 97.2818% |
| C0 handoff-to-result | 48.9898 ms | 1.2987 ms | 97.3490% |
| B2 input-to-result | 49.8516 ms | 2.2382 ms | 95.5103% |
| C0 input-to-result | 49.5161 ms | 2.1157 ms | 95.7273% |

The persistent view construction itself measured 0.0095 ms for B and 0.0012 ms
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
| 1 | 97.3033% | 97.3168% | 95.5677% | 95.7690% |
| 2 | 97.3502% | 97.3386% | 95.6623% | 95.8030% |
| 3 | 97.3546% | 97.3427% | 95.6634% | 95.8197% |

This evidence supports “buffer-backed multiarray view” and “no
element-by-element CPU copy in PlaneFuse.” It does not claim that Core ML
performs no internal copy.

The raw artifacts were generated from commit `3cd0313` and are indexed as
`EXPERIMENTAL` until the R2 hostile review accepts the lifetime and fairness
methodology.
