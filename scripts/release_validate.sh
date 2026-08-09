#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "$ROOT"

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "FAIL release validation: tracked changes must be committed before clean-clone validation"
  exit 1
fi

branch="$(git branch --show-current)"
commit="$(git rev-parse HEAD)"
clone_root="$(mktemp -d /private/tmp/planefuse-r0-clone.XXXXXX)"
clone="$clone_root/PlaneFuse"
started="$(date +%s)"
status=0
trap 'rm -rf "$clone_root"' EXIT

git clone --quiet --no-local --branch "$branch" "$ROOT" "$clone"
(
  cd "$clone"
  ./pf setup mobilenetv2
  python3 scripts/check_benchmark_index.py
  ./scripts/check_git_history.sh --release
  ./scripts/check_project_docs.sh
  ./pf inspect mobilenetv2
  ./pf verify
  ./pf verify lineage
  ./pf build
  ./pf test quick
  ./pf bench quick
  ./pf live --sample
) >"$clone_root/run.log" 2>&1 || status=$?
finished="$(date +%s)"
elapsed=$((finished - started))

python3 - "$ROOT/proof/r0-clean-clone.json" "$branch" "$commit" "$status" "$elapsed" <<'PY'
import json
import platform
import subprocess
import sys
from pathlib import Path

output, branch, commit, status, elapsed = sys.argv[1:]
def command(*args):
    return subprocess.run(args, check=False, capture_output=True, text=True).stdout.strip().splitlines()[0]

report = {
    "schema_version": 1,
    "status": "PASS" if status == "0" else "FAIL",
    "branch": branch,
    "commit": commit,
    "elapsed_seconds": int(elapsed),
    "commands": [
        "./pf setup mobilenetv2",
        "python3 scripts/check_benchmark_index.py",
        "./scripts/check_git_history.sh --release",
        "./scripts/check_project_docs.sh",
        "./pf inspect mobilenetv2",
        "./pf verify",
        "./pf verify lineage",
        "./pf build",
        "./pf test quick",
        "./pf bench quick",
        "./pf live --sample",
    ],
    "tool_versions": {
        "architecture": platform.machine(),
        "os": platform.platform(),
        "swift": command("swift", "--version"),
        "xcode": command("xcodebuild", "-version"),
        "coremltools": "9.0 (pinned in requirements-lock.txt)",
    },
    "notes": "Fresh local clone from the Phase 2 branch; model weights and derived assets were recreated by setup. Camera authorization is intentionally not part of this non-interactive clean-clone check.",
}
Path(output).write_text(json.dumps(report, indent=2) + "\n")
if status != "0":
    raise SystemExit(int(status))
print(json.dumps(report, sort_keys=True))
PY

if [ "$status" -ne 0 ]; then
  echo "FAIL release validate: clean clone failed (proof/r0-clean-clone.json)"
  exit "$status"
fi
echo "PASS release validate: clean clone reproduced setup, build, tests, quick benchmark, lineage, and sample demo"
