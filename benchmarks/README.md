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
