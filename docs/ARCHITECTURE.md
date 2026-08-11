# PlaneFuse architecture

```text
camera / fixed NV12 corpus
          │
          ▼
   224×224 NV12 boundary
          │
    ┌─────┴─────────────────────┐
    │                           │
    ▼                           ▼
B2 · materialized RGB       C1-SR · source reuse
NV12 → RGB Float32 buffer   NV12 Y/UV source tiles
→ RGB stem                  → transformed stem
    │                           │
    └──────────┬────────────────┘
               ▼
 persistent 48×112×112 Float32 activation
               │
               ▼
 unchanged Core ML MobileNetV2 tail (.all)
               │
               ▼
 top-3 labels, confidence, parity, measured boundary metrics
```

The compiler/runtime decision is selective. B2's RGB representation has a materialization cost but can provide reuse. C1-SR removes that boundary only after preserving the exact source mapping and proving the alternative schedule. R6.5 is the counterexample: direct camera-space fusion removed an intermediate but lost enough reuse to be slower.

The live dashboard uses the same two production paths and labels the timing boundary precisely. It displays measured runtime state only after a real callback. Stored benchmark figures are a separate, visibly labeled panel.
