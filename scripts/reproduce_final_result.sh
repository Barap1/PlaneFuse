#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
RUN_ID="${PF_REPRODUCTION_RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"
OUT_DIR="${PF_REPRODUCTION_DIR:-$ROOT/artifacts/reproduction/$RUN_ID}"
mkdir -p "$OUT_DIR"
LOG_FILE="$OUT_DIR/run.log"
exec > >(tee "$LOG_FILE") 2>&1

echo "PlaneFuse full final-result reproduction"
echo "output: $OUT_DIR"
echo "source_commit: $(git -C "$ROOT" rev-parse HEAD)"
echo "reviewed_result: proof/r7.5-source-reuse-final-52db138-20260811T1605Z-confirm.json"
echo "note: this run writes only under artifacts/reproduction and never overwrites proof/"

"$ROOT/pf" doctor
"$ROOT/pf" setup mobilenetv2
"$ROOT/pf" build
"$ROOT/pf" verify
"$ROOT/pf" verify lineage

PF_R75_BATCH_DIR="$OUT_DIR/r7.5-batches" \
PF_R75_FINAL_OUTPUT="$OUT_DIR/r7.5-final.json" \
PF_R75_RUN_ID="$RUN_ID" \
  "$ROOT/scripts/run_r75_source_reuse.sh"

"$ROOT/pf" evidence --check

echo "PASS pf reproduce final"
echo "aggregate: $OUT_DIR/r7.5-final.json"
echo "batches: $OUT_DIR/r7.5-batches"
echo "log: $LOG_FILE"
