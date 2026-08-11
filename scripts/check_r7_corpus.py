#!/usr/bin/env python3
"""Fail-closed structural verifier for the R7 validation corpus.

This verifier intentionally does not load or inspect model outputs.  It checks
only corpus files, manifest metadata, hashes, and the pre-registered buckets.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import struct
import sys
import zlib
from collections import Counter
from pathlib import Path
from typing import Any


BUCKETS = (
    "animals",
    "plants_flowers",
    "food_drink",
    "vehicles",
    "architecture_streets",
    "landscapes_nature",
    "household_tools_electronics",
    "miscellaneous_objects_textures",
)
REAL_REQUIRED = (
    "id", "kind", "bucket", "landing_url", "creator", "license_id",
    "license_evidence_url", "source_host", "provider", "downloaded_sha256",
    "committed_sha256", "deterministic_transform",
)
HEX64 = set("0123456789abcdef")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def image_info(path: Path) -> tuple[str | None, int | None, int | None, str | None]:
    """Return (format, width, height, error), using only standard-library parsing."""
    try:
        data = path.read_bytes()
    except OSError as exc:
        return None, None, None, f"read error: {exc}"
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        if len(data) < 33 or data[12:16] != b"IHDR":
            return "png", None, None, "truncated PNG IHDR"
        width, height = struct.unpack(">II", data[16:24])
        pos = 8
        saw_end = False
        while pos + 12 <= len(data):
            length = struct.unpack(">I", data[pos:pos + 4])[0]
            end = pos + 12 + length
            if end > len(data):
                return "png", width, height, "truncated PNG chunk"
            chunk = data[pos + 4:pos + 8]
            payload = data[pos + 8:pos + 8 + length]
            expected = struct.unpack(">I", data[pos + 8 + length:end])[0]
            if zlib.crc32(chunk + payload) & 0xFFFFFFFF != expected:
                return "png", width, height, f"PNG CRC failure in {chunk!r}"
            pos = end
            if chunk == b"IEND":
                saw_end = True
                break
        if not saw_end or pos != len(data):
            return "png", width, height, "PNG has no terminal IEND or trailing bytes"
        return "png", width, height, None
    if data.startswith(b"\xff\xd8"):
        pos = 2
        width = height = None
        saw_eoi = False
        while pos < len(data):
            if data[pos] != 0xFF:
                return "jpeg", width, height, "invalid JPEG marker boundary"
            while pos < len(data) and data[pos] == 0xFF:
                pos += 1
            if pos >= len(data):
                break
            marker = data[pos]
            pos += 1
            if marker == 0xD9:
                saw_eoi = True
                break
            if marker in (0xD8,):
                continue
            if marker == 0xDA:  # entropy-coded scan: require an EOI, then stop.
                eoi = data.find(b"\xff\xd9", pos)
                if eoi < 0:
                    return "jpeg", width, height, "JPEG scan has no EOI"
                saw_eoi = eoi + 2 == len(data)
                if not saw_eoi:
                    return "jpeg", width, height, "JPEG trailing bytes after EOI"
                break
            if pos + 2 > len(data):
                return "jpeg", width, height, "truncated JPEG segment length"
            length = struct.unpack(">H", data[pos:pos + 2])[0]
            if length < 2 or pos + length > len(data):
                return "jpeg", width, height, "truncated JPEG segment"
            if 0xC0 <= marker <= 0xC3 or 0xC5 <= marker <= 0xC7 or 0xC9 <= marker <= 0xCB or 0xCD <= marker <= 0xCF:
                if length < 7:
                    return "jpeg", width, height, "truncated JPEG frame header"
                height, width = struct.unpack(">HH", data[pos + 3:pos + 7])
            pos += length
        if not saw_eoi or width is None or height is None:
            return "jpeg", width, height, "incomplete JPEG"
        return "jpeg", width, height, None
    return None, None, None, "unsupported image format (expected PNG or JPEG)"


def is_procedural(sample: dict[str, Any]) -> bool:
    if sample.get("kind") == "procedural":
        return True
    ident = str(sample.get("id", ""))
    license_text = str(sample.get("license", "")).lower()
    return ident.startswith(("stress-", "procedural-")) or "procedural" in license_text


def nonempty(sample: dict[str, Any], key: str) -> bool:
    value = sample.get(key)
    return isinstance(value, str) and bool(value.strip())


def valid_hash(value: Any) -> bool:
    return isinstance(value, str) and len(value) == 64 and set(value.lower()) <= HEX64


def verify(args: argparse.Namespace) -> int:
    manifest_path = Path(args.manifest)
    errors: list[str] = []
    try:
        manifest = json.loads(manifest_path.read_text())
    except (OSError, json.JSONDecodeError) as exc:
        print(f"FAIL R7 corpus: cannot read manifest: {exc}")
        return 1
    samples = manifest.get("samples")
    if not isinstance(samples, list):
        print("FAIL R7 corpus: manifest.samples is not a list")
        return 1
    root = Path(args.root).resolve()
    real: list[dict[str, Any]] = []
    procedural: list[dict[str, Any]] = []
    seen_ids: set[str] = set()
    seen_hashes: dict[str, str] = {}
    buckets: Counter[str] = Counter()
    for index, sample in enumerate(samples):
        if not isinstance(sample, dict):
            errors.append(f"sample[{index}]: not an object")
            continue
        ident = str(sample.get("id", f"sample[{index}]"))
        if ident in seen_ids:
            errors.append(f"{ident}: duplicate id")
        seen_ids.add(ident)
        if is_procedural(sample):
            procedural.append(sample)
        else:
            real.append(sample)
            bucket = sample.get("bucket")
            if isinstance(bucket, str) and bucket in BUCKETS:
                buckets[bucket] += 1
            elif bucket:
                errors.append(f"{ident}: unknown bucket {bucket!r}")
            missing = [key for key in REAL_REQUIRED if not nonempty(sample, key)]
            if missing:
                errors.append(f"{ident}: missing strict real fields: {', '.join(missing)}")
            for key in ("downloaded_sha256", "committed_sha256"):
                if key in sample and not valid_hash(sample[key]):
                    errors.append(f"{ident}: invalid {key}")
        relative = sample.get("relative_path")
        if not isinstance(relative, str) or not relative:
            errors.append(f"{ident}: missing relative_path")
            continue
        file_path = (root / relative).resolve()
        if root not in file_path.parents and file_path != root:
            errors.append(f"{ident}: relative_path escapes repository")
            continue
        if not file_path.is_file():
            errors.append(f"{ident}: missing file {relative}")
            continue
        fmt, width, height, image_error = image_info(file_path)
        if image_error:
            errors.append(f"{ident}: {image_error}")
        if width is not None and height is not None and (width > 4096 or height > 4096):
            errors.append(f"{ident}: image exceeds 4096px moderate-resolution ceiling")
        actual = sha256(file_path)
        declared = sample.get("sha256")
        if declared and declared != actual:
            errors.append(f"{ident}: sha256 mismatch (declared {declared}, actual {actual})")
        if actual in seen_hashes:
            errors.append(f"{ident}: duplicate local hash with {seen_hashes[actual]}")
        seen_hashes[actual] = ident
        if not is_procedural(sample) and sample.get("committed_sha256") and sample["committed_sha256"] != actual:
            errors.append(f"{ident}: committed_sha256 mismatch (actual {actual})")
    deficits = []
    if len(real) < 32:
        deficits.append(f"real inputs {len(real)}/32 (deficit {32 - len(real)})")
    if len(procedural) < 32:
        deficits.append(f"procedural inputs {len(procedural)}/32 (deficit {32 - len(procedural)})")
    for bucket in BUCKETS:
        if buckets[bucket] < 4:
            deficits.append(f"bucket {bucket} {buckets[bucket]}/4 (deficit {4 - buckets[bucket]})")
        elif buckets[bucket] > 4:
            errors.append(f"bucket {bucket}: {buckets[bucket]}/4 exceeds exact slot count")
    print(f"R7 corpus report: real={len(real)}/32 procedural={len(procedural)}/32 files={len(samples)}")
    print("Bucket counts: " + ", ".join(f"{bucket}={buckets[bucket]}/4" for bucket in BUCKETS))
    if deficits:
        print("Deficits: " + "; ".join(deficits))
    if errors:
        print(f"Checks: FAIL ({len(errors)} issue(s))")
        for error in errors[: args.max_errors]:
            print(f"- {error}")
        if len(errors) > args.max_errors:
            print(f"- ... {len(errors) - args.max_errors} more")
        return 1
    if deficits:
        print("Checks: FAIL closed (requirements not met; no claim of corpus pass)")
        return 1
    print("Checks: PASS (32 real + 32 procedural, strict provenance, hashes, and buckets)")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Fail-closed, output-blind R7 corpus verifier.")
    parser.add_argument("--manifest", default="proof/m5-validation-corpus.json")
    parser.add_argument("--root", default=".", help="repository root containing relative_path files")
    parser.add_argument("--max-errors", type=int, default=24)
    return verify(parser.parse_args())


if __name__ == "__main__":
    sys.exit(main())
