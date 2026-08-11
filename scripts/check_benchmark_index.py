#!/usr/bin/env python3
"""Ensure every committed raw benchmark has an explicit acceptance status."""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    index = json.loads((root / "benchmarks/artifact-index.json").read_text())
    # The workspace may contain ignored local benchmark scratch files. The
    # release index is authoritative for committed evidence, so compare it to
    # Git-tracked result JSON rather than allowing ignored scratch to make a
    # clean clone appear inconsistent.
    tracked = subprocess.run(
        ["git", "-C", str(root), "ls-files", "--", "benchmarks/results/*.json"],
        check=True, capture_output=True, text=True
    ).stdout.splitlines()
    actual = {Path(path).name for path in tracked}
    indexed = set(index["artifacts"])
    if actual != indexed:
        print(f"FAIL benchmark index mismatch: missing={sorted(actual-indexed)}, stale={sorted(indexed-actual)}")
        return 1
    statuses = set(index["allowed_statuses"])
    if any(status not in statuses for status in index["artifacts"].values()):
        print("FAIL benchmark index contains an unknown acceptance status")
        return 1
    print(f"PASS benchmark index: {len(actual)} artifacts classified")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
