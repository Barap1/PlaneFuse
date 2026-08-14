#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
OUT_DIR="${PF_REPRODUCTION_DIR:-$ROOT/artifacts/reproduction/$RUN_ID}"
mkdir -p "$OUT_DIR"
LOG_FILE="$OUT_DIR/run.log"
exec > >(tee "$LOG_FILE") 2>&1

echo "PlaneFuse quick reproduction"
echo "output: $OUT_DIR"
echo "source_commit: $(git -C "$ROOT" rev-parse HEAD)"
echo "source_tree: $(git -C "$ROOT" status --short | tr '\n' ' ' || true)"

"$ROOT/pf" doctor
"$ROOT/pf" build
"$ROOT/pf" test quick
"$ROOT/pf" verify
PF_BENCHMARK_OUTPUT="$OUT_DIR/quick-benchmark.json" "$ROOT/pf" bench quick
"$ROOT/pf" evidence --check

echo "PASS pf reproduce quick"
echo "benchmark: $OUT_DIR/quick-benchmark.json"
echo "log: $LOG_FILE"
