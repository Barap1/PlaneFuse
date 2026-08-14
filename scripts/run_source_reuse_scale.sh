#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
RUN_ID="${PF_SOURCE_REUSE_SCALE_RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"
OUT_DIR="${PF_SOURCE_REUSE_SCALE_DIR:-$ROOT/proof/final/source-reuse-scaling-batches/$RUN_ID}"
FINAL_OUTPUT="${PF_SOURCE_REUSE_SCALE_OUTPUT:-$ROOT/proof/final/source-reuse-scaling.json}"
mkdir -p "$OUT_DIR"

for batch_index in 0 1 2; do
  PF_SOURCE_REUSE_SCALE_BATCH_INDEX="$batch_index" \
  PF_SOURCE_REUSE_SCALE_ORDER_PHASE="$((batch_index % 2))" \
  PF_SOURCE_REUSE_SCALE_OUTPUT="$OUT_DIR/batch-$(printf '%02d' "$batch_index").json" \
  PF_GIT_COMMIT="$(git -C "$ROOT" rev-parse HEAD)" \
    "$ROOT/pf" bench source-reuse-scale-batch
done

python3 -B "$ROOT/scripts/aggregate_source_reuse_scaling.py" \
  --input-dir "$OUT_DIR" \
  --output "$FINAL_OUTPUT" \
  --expected-commit "$(git -C "$ROOT" rev-parse HEAD)" \
  --run-id "$RUN_ID"

echo "PASS pf bench source-reuse-scale"
echo "raw: $OUT_DIR"
echo "aggregate: $FINAL_OUTPUT"
