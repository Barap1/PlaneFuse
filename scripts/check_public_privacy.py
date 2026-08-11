#!/usr/bin/env python3
"""Fail closed on concrete personal or secret metadata in tracked text files."""

from __future__ import annotations

import re
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BINARY_SUFFIXES = {".bin", ".jpg", ".jpeg", ".png", ".trace", ".zip", ".tar", ".gz"}
PATTERNS = (
    re.compile(r"/Users/[A-Za-z0-9._-]+"),
    re.compile(r"/private/var/[A-Za-z0-9._/-]+"),
    re.compile(r"hardware[_ -]?uuid\s*[:=]\s*[0-9a-f-]{8,}", re.I),
    re.compile(r"\b(?:serial|device[_ -]?(?:id|uuid)|pid)\s*[:=]\s*[^\s,;]+", re.I),
    re.compile(r"\b(?:sk|ghp|github_pat|xox[baprs])[-_][A-Za-z0-9_-]{12,}"),
    re.compile(r"\bAKIA[0-9A-Z]{16}\b"),
)


def tracked_files() -> list[Path]:
    output = subprocess.check_output(["git", "-C", str(ROOT), "ls-files", "-z"])
    return [ROOT / raw for raw in output.decode().split("\0") if raw]


def main() -> int:
    checked = 0
    for path in tracked_files():
        try:
            data = path.read_bytes()
        except OSError:
            continue
        if path.suffix.lower() in BINARY_SUFFIXES or b"\0" in data:
            continue
        text = data.decode("utf-8", errors="replace")
        checked += 1
        for pattern in PATTERNS:
            match = pattern.search(text)
            if match:
                relative = path.relative_to(ROOT)
                raise SystemExit(f"FAIL public privacy: {relative} matches {pattern.pattern!r}: {match.group(0)!r}")
    print(f"PASS public privacy: checked {checked} tracked text files")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
