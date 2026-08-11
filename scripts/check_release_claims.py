#!/usr/bin/env python3
"""Check that final-facing prose names the accepted R7.5 state."""

from __future__ import annotations

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
FINAL_SURFACES = (
    "README.md",
    "STATUS.md",
    "SUBMISSION_CHECKLIST.md",
    "DEVPOST_DRAFT_R9.md",
    "R9-DEMO-SCRIPT.md",
    "docs/JUDGE_EVIDENCE.md",
    "docs/ARCHITECTURE.md",
    "proof/evidence-index.md",
    "proof/r7-final-selection-matrix.md",
)
STALE = (
    "pending hostile review",
    "pending fresh hostile",
    "judge-facing UI remains unfinished",
    "R8/R9 active",
)


def main() -> int:
    for relative in FINAL_SURFACES:
        text = (ROOT / relative).read_text()
        lowered = text.lower()
        for phrase in STALE:
            if phrase.lower() in lowered:
                raise SystemExit(f"FAIL release claims: stale phrase {phrase!r} in {relative}")
    claims = (ROOT / "CLAIMS.md").read_text()
    c031 = claims.split("## C031", 1)[1].split("## ", 1)[0]
    if "VERIFIED TECHNICAL RESULT / T1 PASSED / SOL SHIP" not in c031:
        raise SystemExit("FAIL release claims: C031 is not marked accepted/T1/SOL SHIP")
    for required in ("1.737875", "1.633458", "1.532583", "11.8128%", "5.960464e-6"):
        if required not in (ROOT / "docs/JUDGE_EVIDENCE.md").read_text():
            raise SystemExit(f"FAIL release claims: judge evidence missing {required}")
    print("PASS release claims: final surfaces agree with accepted R7.5 state")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
