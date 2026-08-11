#!/usr/bin/env python3
"""Reject machine-identifying metadata in current-tree profiler exports."""

from __future__ import annotations

import argparse
import re
from pathlib import Path


PATTERNS = (
    re.compile(r"Aarav", re.IGNORECASE),
    re.compile(r"uuid\s*=", re.IGNORECASE),
    re.compile(r"\bpid\s*=", re.IGNORECASE),
    re.compile(r"(?:/Users/|/Applications/|/System/).*(?:path|process)", re.IGNORECASE),
    re.compile(r"<process\b[^>]*(?:pid|path)=", re.IGNORECASE),
)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("paths", nargs="*", type=Path, default=[Path("proof/profiler")])
    args = parser.parse_args()
    checked = 0
    for root in args.paths:
        candidates = [root] if root.is_file() else list(root.rglob("*"))
        for path in candidates:
            if not path.is_file() or any(part.endswith(".trace") for part in path.parts):
                continue
            try:
                text = path.read_text(errors="replace")
            except OSError:
                continue
            checked += 1
            for pattern in PATTERNS:
                if pattern.search(text):
                    raise SystemExit(f"FAIL R7 profiler privacy: {path} matches {pattern.pattern!r}")
    print(f"PASS R7 profiler privacy: checked {checked} current-tree export files")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
