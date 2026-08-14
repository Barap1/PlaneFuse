#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COMMIT="$(git -C "$ROOT" rev-parse HEAD)"
RUN_ID="${PF_R75_RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"
OUT_DIR="${PF_R75_BATCH_DIR:-$ROOT/proof/r7.5-source-reuse-batches/$COMMIT}"
FINAL_OUTPUT="${PF_R75_FINAL_OUTPUT:-$ROOT/proof/r7.5-source-reuse-final-$COMMIT.json}"

if [ -e "$OUT_DIR" ]; then
  echo "FAIL R7.5 source reuse: output directory already exists: $OUT_DIR" >&2
  exit 2
fi
mkdir -p "$OUT_DIR"

ac_power_state="${PF_AC_POWER_STATE:-$(pmset -g batt | sed -n "s/.*'\\([^']*\\)'.*/\\1/p" | head -n 1)}"
custom_power="$(pmset -g custom 2>/dev/null || true)"
low_power_mode="${PF_LOW_POWER_MODE:-$(printf '%s\\n' "$custom_power" | sed -n 's/^[[:space:]]*lowpowermode[[:space:]]*//p' | head -n 1)}"
if [[ -z "$low_power_mode" ]] && ! printf '%s\\n' "$custom_power" | grep -qi 'lowpowermode'; then
  # Desktop Macs and some current macOS configurations omit this key because
  # the user-facing Low Power Mode control is unavailable. Treating an absent
  # control as disabled is explicit and reproducible; callers can override it
  # with PF_LOW_POWER_MODE when the host exposes a value through another tool.
  low_power_mode="0"
  echo "INFO: pmset did not expose lowpowermode; recording Low Power Mode as disabled (0)"
fi
if [[ "$ac_power_state" != "AC Power" && "$ac_power_state" != "Battery Power" ]] || [[ "$low_power_mode" != "0" && "$low_power_mode" != "1" ]]; then
  echo "FAIL R7.5 source reuse: could not capture AC power/Low Power Mode state" >&2
  exit 1
fi

offsets=(0 12 24 36 48)
for batch_index in 0 1 2 3 4; do
  output="$OUT_DIR/batch-$(printf '%02d' "$batch_index").json"
  PF_R75_BATCH_INDEX="$batch_index" \
  PF_R75_SOURCE_OFFSET="${offsets[$batch_index]}" \
  PF_R75_ORDER_PHASE="$((batch_index % 2))" \
  PF_R75_EXECUTION_ID="r7.5-${COMMIT}-run-${RUN_ID}-batch-${batch_index}" \
  PF_AC_POWER_STATE="$ac_power_state" \
  PF_LOW_POWER_MODE="$low_power_mode" \
  PF_BENCHMARK_OUTPUT="$output" \
  "$ROOT/pf" bench mobilenetv2 r75-batch
done

python3 -B "$ROOT/scripts/aggregate_r75_source_reuse.py" \
  --input-dir "$OUT_DIR" \
  --output "$FINAL_OUTPUT" \
  --expected-commit "$COMMIT" \
  --run-id "$RUN_ID"

echo "PASS R7.5 source reuse: $FINAL_OUTPUT"
