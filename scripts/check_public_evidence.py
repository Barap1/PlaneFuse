#!/usr/bin/env python3
"""Check that the public evidence landing path is complete and truthful."""

from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def fail(message: str) -> None:
    raise SystemExit(f"FAIL public evidence: {message}")


def main() -> int:
    required = [
        "docs/RESULTS_AND_EVIDENCE.md",
        "docs/REPRODUCIBILITY.md",
        "docs/PROOF_ARTIFACTS.md",
        "docs/ARCHITECTURE.md",
        "docs/TECHNICAL_DETAILS.md",
        "docs/assets/latency-comparison.svg",
        "docs/assets/rgb-intermediate.svg",
        "docs/assets/source-reuse-scaling.svg",
        "docs/diagrams/planefuse-architecture.svg",
        "proof/r7.5-source-reuse-final-52db138-20260811T1605Z-confirm.json",
        "proof/r7.5-competition-targets.json",
        "proof/r7-b2-c1-shared-quality-conditions.json",
        "proof/r7-final-shared-path-profile-repaired-conditions.json",
        "proof/m5-validation-corpus.json",
        "proof/r7.5-independent-review.md",
        "proof/final/reproducibility.json",
        "proof/final/source-reuse-scaling.json",
        "Examples/PlaneFuseIntegration/README.md",
    ]
    for relative in required:
        if not (ROOT / relative).is_file():
            fail(f"missing {relative}")

    final = json.loads((ROOT / required[8]).read_text())
    if final.get("status") != "r7_5_source_reuse_final":
        fail("authoritative R7.5 artifact has unexpected status")
    if final["aggregate"]["statistics"]["C1-SR"]["p50"] >= final["aggregate"]["statistics"]["B2"]["p50"]:
        fail("C1-SR is not below B2 in the authoritative artifact")

    text = (ROOT / "README.md").read_text().lower()
    for forbidden in ("judge context", "winning result", "hackathon evidence"):
        if forbidden in text:
            fail(f"public README contains forbidden label: {forbidden}")
    print("PASS public evidence: landing page, graphs, diagrams, and proof records are present")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
