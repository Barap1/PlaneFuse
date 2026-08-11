#!/usr/bin/env python3
"""Fail-closed checker for the complete repaired R7 A/B/C selection matrix."""

from __future__ import annotations

import json
from pathlib import Path


REQUIRED = {"A", "B1", "B2", "C0", "C1", "C2", "C3", "C4"}
FIELDS = {
    "implementation_status", "input_boundary", "precision", "materialized_intermediates",
    "bridge_class", "tail_configuration", "authoritative_evidence", "result",
    "disposition", "eligible_for_final_matched_comparison", "reason",
}


def main() -> int:
    path = Path("proof/r7-final-selection-matrix.json")
    data = json.loads(path.read_text())
    rows = data.get("rows", [])
    ids = {row.get("id") for row in rows}
    if ids != REQUIRED or len(rows) != len(REQUIRED):
        raise SystemExit(f"FAIL R7 matrix: expected exactly {sorted(REQUIRED)}, got {sorted(ids)}")
    for row in rows:
        missing = FIELDS - set(row)
        if missing:
            raise SystemExit(f"FAIL R7 matrix: {row['id']} missing {sorted(missing)}")
        if not row["authoritative_evidence"] or not row["disposition"] or not row["reason"]:
            raise SystemExit(f"FAIL R7 matrix: {row['id']} has incomplete evidence/disposition")
    if data.get("strongest_credible_matched_b") != "B2" or data.get("strongest_accepted_stable_c") != "C1":
        raise SystemExit("FAIL R7 matrix: strongest B/C selection is not B2/C1")
    by_id = {row["id"]: row for row in rows}
    if by_id["A"]["eligible_for_final_matched_comparison"] or by_id["B1"]["eligible_for_final_matched_comparison"] or by_id["C0"]["eligible_for_final_matched_comparison"]:
        raise SystemExit("FAIL R7 matrix: contextual/superseded A/B1/C0 marked eligible")
    if by_id["C2"]["disposition"] != "rejected-quality":
        raise SystemExit("FAIL R7 matrix: C2 quality rejection missing")
    if by_id["C3"]["disposition"] != "infeasible":
        raise SystemExit("FAIL R7 matrix: C3 infeasibility missing")
    if by_id["C4"]["disposition"] != "rejected-no-stable-e2e-win":
        raise SystemExit("FAIL R7 matrix: C4 disposition missing")
    extension = data.get("camera_space_extension", {})
    if extension.get("disposition") != "separate-negative-extension":
        raise SystemExit("FAIL R7 matrix: R6.5 extension is not separately qualified")
    print(f"PASS R7 matrix: {len(rows)} rows; strongest matched B={data['strongest_credible_matched_b']} C={data['strongest_accepted_stable_c']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
