#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
LOG_DIR="$ROOT/artifacts/logs"
MODEL_DIR="$ROOT/models"
DERIVED_DIR="$MODEL_DIR/derived"
VENV_DIR="$ROOT/.venv"
MODEL_URL="https://ml-assets.apple.com/coreml/models/Image/ImageClassification/MobileNetV2/MobileNetV2.mlmodel"
MODEL_SHA256="cb5a35f593582232140556bbfa4618e66b37b8ff2fc33ba17db909e1050fd144"
LOG_FILE="$LOG_DIR/pf-setup-mobilenetv2-$(date -u +%Y%m%dT%H%M%SZ).log"

mkdir -p "$LOG_DIR" "$MODEL_DIR" "$DERIVED_DIR"
exec > >(tee "$LOG_FILE") 2>&1

fail() {
  echo "FAIL setup mobilenetv2: $*"
  echo "log: $LOG_FILE"
  exit 1
}

if [ "$(uname -s)" != "Darwin" ] || [ "$(uname -m)" != "arm64" ]; then
  fail "Apple-Silicon macOS is required"
fi

if [ ! -x "$VENV_DIR/bin/python" ]; then
  python3 -m venv "$VENV_DIR"
fi

"$VENV_DIR/bin/python" -m pip install --disable-pip-version-check --requirement "$ROOT/requirements-lock.txt"
"$VENV_DIR/bin/python" - <<'PY'
import coremltools
assert coremltools.__version__ == "9.0", coremltools.__version__
print(f"coremltools: {coremltools.__version__}")
PY

MODEL_PATH="$MODEL_DIR/MobileNetV2.mlmodel"
if [ ! -f "$MODEL_PATH" ]; then
  curl --fail --location --retry 3 --output "$MODEL_PATH" "$MODEL_URL"
fi
actual_sha256="$(shasum -a 256 "$MODEL_PATH" | awk '{print $1}')"
if [ "$actual_sha256" != "$MODEL_SHA256" ]; then
  fail "source SHA-256 mismatch: expected $MODEL_SHA256, got $actual_sha256"
fi

VIRTUAL_ENV="$VENV_DIR" "$VENV_DIR/bin/python" "$ROOT/scripts/prepare_mobilenetv2.py" "$MODEL_PATH" "$DERIVED_DIR"

for model_and_target in \
  "MobileNetV2Stem:stem-array-compiled" \
  "MobileNetV2FullArray:full-array-compiled" \
  "MobileNetV2Tail:tail-compiled"; do
  model="${model_and_target%%:*}"
  target="${model_and_target##*:}"
  rm -rf "$DERIVED_DIR/$target"
  mkdir -p "$DERIVED_DIR/$target"
  xcrun coremlc compile "$DERIVED_DIR/$model.mlmodel" "$DERIVED_DIR/$target" --platform macOS --deployment-target 13.0
done

"$ROOT/.venv/bin/python" - "$DERIVED_DIR/manifest.json" "$MODEL_SHA256" <<'PY'
import json
import hashlib
import sys
from pathlib import Path

manifest = json.loads(Path(sys.argv[1]).read_text())
assert manifest["schema_version"] == 1
assert manifest["source_sha256"] == sys.argv[2]
assert manifest["stem"]["shape"] == [48, 112, 112]
assert manifest["tail"]["input"] == manifest["stem"]["output"]
assert manifest["tail"]["shape"] == manifest["stem"]["shape"]
for section in ("stem", "full_array", "tail"):
    path = Path(manifest[section]["path"])
    assert path.is_file(), path
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    assert digest == manifest[section]["sha256"], (path, digest, manifest[section]["sha256"])
for target in ("stem-array-compiled", "full-array-compiled", "tail-compiled"):
    compiled = Path("models/derived") / target
    assert any(path.name == "model" for path in compiled.rglob("model")), compiled
print("manifest: PASS")
PY

echo "PASS setup mobilenetv2"
echo "source: $MODEL_PATH ($MODEL_SHA256)"
echo "derived: $DERIVED_DIR"
echo "compiled: stem-array, full-array, tail"
echo "log: $LOG_FILE"
