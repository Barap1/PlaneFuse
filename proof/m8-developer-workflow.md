# M8 developer workflow proof

Status: accepted

The supported example can be inspected and validated without editing Swift:

```bash
./pf inspect mobilenetv2
./pf inspect fixture
./pf compile mobilenetv2
./pf verify mobilenetv2
./pf bench mobilenetv2 confirm
```

`inspect` emits stable JSON describing the compatibility contract. `compile`
is deliberately preparation-only and reports the local source/derived assets
required by the real compiler preparation script. `verify mobilenetv2` checks
the complete asset set and delegates to the established real-corpus M5
benchmark; missing assets produce a nonzero result with a JSON list rather
than a fabricated pass. `bench` remains the measured A/B/C path.

The current implementation is intentionally narrow. Unsupported geometry,
padding, normalization, or missing model lineage is rejected by the shared
`NativePlaneStemSpec` validator. A future compiler backend can consume this
same inspection result without changing the correctness contract.
