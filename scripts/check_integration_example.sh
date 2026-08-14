#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
if ! "$ROOT/pf" build >/dev/null 2>&1; then
  echo "FAIL integration example: PlaneFuseCore build failed" >&2
  exit 1
fi
MODULE_DIR="$ROOT/.build/arm64-apple-macosx/debug/Modules"
swiftc -typecheck \
  -target arm64-apple-macosx13.0 \
  -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -I "$MODULE_DIR" \
  -F "$(xcrun --sdk macosx --show-sdk-platform-path)/Developer/Library/Frameworks" \
  "$ROOT/Examples/PlaneFuseIntegration/README.swift"
