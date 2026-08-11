#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COMMIT="$(git -C "$ROOT" rev-parse HEAD)"
RUN_ID="${PF_R7_RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"
OUT_DIR="${PF_R7_BATCH_DIR:-$ROOT/proof/r7-repaired-batches/$COMMIT}"
FINAL_OUTPUT="${PF_R7_FINAL_OUTPUT:-$ROOT/proof/r7-final-b2-c1-shared-repaired.json}"

if [ -e "$OUT_DIR" ]; then
  echo "FAIL R7 repaired benchmark: output directory already exists: $OUT_DIR" >&2
  exit 2
fi
mkdir -p "$OUT_DIR"

# Even offsets keep the explicit alternating order phase from flipping the
# source/order parity relationship: every repeated sample appears in both
# execution orders across the five batches.
offsets=(0 12 24 36 48)
for batch_index in 0 1 2 3 4; do
  output="$OUT_DIR/batch-$(printf '%02d' "$batch_index").json"
  PF_R7_BATCH_INDEX="$batch_index" \
  PF_R7_SOURCE_OFFSET="${offsets[$batch_index]}" \
  PF_R7_ORDER_PHASE="$((batch_index % 2))" \
  PF_R7_EXECUTION_ID="r7-${COMMIT}-run-${RUN_ID}-batch-${batch_index}" \
  PF_AC_POWER_STATE="$(pmset -g batt | sed -n "s/.*'\\([^']*\\)'.*/\\1/p" | head -n 1)" \
  PF_LOW_POWER_MODE="$(pmset -g custom | awk '$1 == "lowpowermode" { print $2; exit }')" \
  PF_BENCHMARK_OUTPUT="$output" \
  "$ROOT/pf" bench mobilenetv2 shared-batch
done

python3 -B "$ROOT/scripts/aggregate_r7_shared_batches.py" \
  --input-dir "$OUT_DIR" \
  --output "$FINAL_OUTPUT" \
  --expected-commit "$COMMIT" \
  --run-id "$RUN_ID"

echo "PASS R7 repaired shared benchmark: $FINAL_OUTPUT"
