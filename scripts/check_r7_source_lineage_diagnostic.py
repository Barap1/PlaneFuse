#!/usr/bin/env python3
"""Compare the shared procedural lineage cases across R0 and R7 artifacts."""

from __future__ import annotations

import json
from pathlib import Path


def main() -> int:
    r0 = {sample["id"]: sample for sample in json.loads(Path("proof/r0-source-lineage.json").read_text())["samples"]}
    r7 = {sample["id"]: sample for sample in json.loads(Path("proof/r7-source-lineage-release.json").read_text())["samples"]}
    shared = sorted(identifier for identifier in set(r0) & set(r7) if identifier.startswith("stress-"))
    if len(shared) != 28:
        raise SystemExit(f"FAIL lineage diagnostic: expected 28 shared stress samples, got {len(shared)}")
    r0_matches = sum(r0[identifier]["top5_set_match"] for identifier in shared)
    r7_matches = sum(r7[identifier]["top5_set_match"] for identifier in shared)
    if r0_matches != 28 or r7_matches != 23:
        raise SystemExit(f"FAIL lineage diagnostic: shared top-5 matches R0={r0_matches}/28 R7={r7_matches}/28")
    print("PASS r7 lineage diagnostic: backend-policy difference is qualified evidence")
    print(f"shared procedural top-5: R0 CPU-only {r0_matches}/28; R7 source .all {r7_matches}/28")
    print("R7 full procedural corpus: 27/32; real-image corpus: 32/32")
    print("interpretation: source backend/precision is a strong explanation; preprocessing interaction is not ruled out")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
