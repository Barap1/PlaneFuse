# Benchmark artifacts

This directory stores machine-readable benchmark evidence. The committed
`artifact-index.json` is authoritative for acceptance status.

Files:

- `best.json` - best verified result, never merely the latest run;
- `history.jsonl` - append-only compact run summaries once the harness exists;
- `results/` - immutable raw confirmation/final JSON artifacts;
- `artifact-index.json` - explicit ACCEPTED/SUPERSEDED/REJECTED/EXPERIMENTAL classification.

Rules are in `../BENCHMARK_CONTRACT.md` and the stricter Phase 2
`../BENCHMARK_CONTRACT_V2.md`. Superseded or rejected raw files remain for
scientific history but cannot support current claims.

Phase 2 R1 diagnostics are reproducible with `./pf profile mobilenetv2`; the
strongest conventional planar Float32 baseline is `./pf bench mobilenetv2 b2`.
See `../proof/r1-bottleneck-profile.md` for component boundaries and the
rejected RGBA16Float candidate.

The R2 bridge ablation is run with `./pf bridge mobilenetv2` and remains
experimental until its hostile review is recorded in `../proof/r2-shared-bridge.md`.
