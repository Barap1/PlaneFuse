#!/usr/bin/env python3
"""Fail-closed structural checker for the repaired R7 target evaluation."""

from __future__ import annotations

import json
from pathlib import Path


def main() -> int:
    target = json.loads(Path("proof/r7-competition-targets-repaired.json").read_text())
    performance = json.loads(Path(target["performance_artifact"]).read_text())
    if target["status"] != "r7_repaired_all_measured_targets_evaluated_pending_hostile_review":
        raise SystemExit("FAIL repaired target evaluation status")
    if target["performance_artifact_commit"] != performance["commit"]:
        raise SystemExit("FAIL repaired target evaluation commit provenance")
    if [item["id"] for item in target["targets"]] != ["T1", "T2", "T3", "T4"]:
        raise SystemExit("FAIL repaired target evaluation target order")
    t1 = next(item for item in target["targets"] if item["id"] == "T1")
    expected = performance["measurement"]["aggregate_percentage"]
    if abs(t1["aggregate_percentage_c1_lower"] - expected) > 1e-12:
        raise SystemExit("FAIL repaired target evaluation percentage provenance")
    if t1["passes"] or any(item["passes"] for item in target["targets"]):
        raise SystemExit("FAIL repaired target evaluation unexpectedly passes a target")
    if "below 10%" not in t1["reason"]:
        raise SystemExit("FAIL repaired target evaluation threshold reasoning")
    print("PASS repaired target evaluation: T1-T4 preserved with no threshold reinterpretation")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
