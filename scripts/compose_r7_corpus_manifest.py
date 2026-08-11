#!/usr/bin/env python3
"""Compose the output-blind R7 manifest without inspecting model results."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser(description="Compose the R7 corpus manifest from promoted provenance and procedural entries.")
    parser.add_argument("--base", default="proof/m5-validation-corpus.json")
    parser.add_argument("--promoted", default="artifacts/r7-corpus/r7-promoted-real-final2.json")
    parser.add_argument("--archive", default="proof/m5-validation-corpus-r6.2.json")
    parser.add_argument("--output", default="proof/m5-validation-corpus.json")
    args = parser.parse_args()

    base_path = Path(args.base)
    base = json.loads(base_path.read_text())
    promoted = json.loads(Path(args.promoted).read_text())["real_samples"]
    if len(promoted) != 32 or len({sample["id"] for sample in promoted}) != 32:
        raise SystemExit("refusing to compose: promoted real ledger is not exactly 32 unique samples")
    procedural = [sample for sample in base["samples"] if str(sample.get("id", "")).startswith("stress-")]
    if len(procedural) < 32:
        raise SystemExit("refusing to compose: base manifest has fewer than 32 procedural samples")
    archive_path = Path(args.archive)
    if not archive_path.exists():
        archive_path.write_text(json.dumps(base, indent=2, ensure_ascii=False) + "\n")
    output = dict(base)
    output["schema_version"] = 2
    output["samples"] = sorted(promoted, key=lambda sample: (sample["bucket"], sample["id"])) + procedural
    Path(args.output).write_text(json.dumps(output, indent=2, ensure_ascii=False) + "\n")
    print(f"composed R7 manifest: real={len(promoted)} procedural={len(procedural)} output={args.output} archive={archive_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
