#!/usr/bin/env python3
"""Generate deterministic, repository-owned NV12 source-grid stress images."""

from __future__ import annotations

import binascii
import json
import struct
import sys
import zlib
from pathlib import Path

WIDTH = HEIGHT = 224
ROOT = Path(__file__).resolve().parents[1]
CORPUS_DIR = ROOT / "proof" / "m5-corpus"
MANIFEST_PATH = ROOT / "proof" / "m5-validation-corpus.json"


def png(path: Path, pixels: list[tuple[int, int, int]]) -> None:
    rows = bytearray()
    for y in range(HEIGHT):
        rows.append(0)
        for x in range(WIDTH):
            rows.extend(pixels[y * WIDTH + x])

    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", binascii.crc32(kind + data) & 0xFFFFFFFF)

    data = b"\x89PNG\r\n\x1a\n"
    data += chunk(b"IHDR", struct.pack(">IIBBBBB", WIDTH, HEIGHT, 8, 2, 0, 0, 0))
    data += chunk(b"IDAT", zlib.compress(bytes(rows), level=9))
    data += chunk(b"IEND", b"")
    path.write_bytes(data)


def generate(kind: int) -> list[tuple[int, int, int]]:
    pixels: list[tuple[int, int, int]] = []
    for y in range(HEIGHT):
        for x in range(WIDTH):
            if kind == 0:
                rgb = (0, 0, 0)
            elif kind == 1:
                rgb = (255, 255, 255)
            elif kind == 2:
                rgb = (128, 128, 128)
            elif kind in range(3, 8):
                rgb = ((255, 0, 0), (0, 255, 0), (0, 0, 255), (0, 255, 255), (255, 0, 255))[kind - 3]
            elif kind == 8:
                # Near-yellow rather than an exactly flat primary mix avoids a
                # classifier tie while retaining an extreme chroma contract.
                rgb = (255, 240, 32)
            elif kind == 9:
                v = (x * 255) // (WIDTH - 1)
                rgb = (v, v, v)
            elif kind == 10:
                v = (y * 255) // (HEIGHT - 1)
                rgb = (v, 255 - v, (v * 3) % 256)
            elif kind == 11:
                v = ((x + y) * 255) // (WIDTH + HEIGHT - 2)
                rgb = (v, v, 255 - v)
            elif kind in (12, 13, 14, 15):
                size = (2, 4, 8, 16)[kind - 12]
                v = 255 if ((x // size) + (y // size)) % 2 else 0
                rgb = (v, 255 - v, v)
            elif kind == 16:
                rgb = (255, 255, 255) if x == WIDTH - 1 else (0, 0, 0)
            elif kind == 17:
                rgb = (255, 255, 255) if y == HEIGHT - 1 else (0, 0, 0)
            elif kind == 18:
                rgb = (255, 0, 0) if x < 2 else (0, 0, 255)
            elif kind == 19:
                rgb = (0, 255, 0) if y < 2 else (255, 0, 255)
            elif kind == 20:
                phase = ((x % 4) // 2) + 2 * ((y % 4) // 2)
                rgb = ((255, 0, 0), (0, 255, 0), (0, 0, 255), (255, 255, 0))[phase]
            elif kind == 21:
                phase = (x + 2 * y) % 6
                rgb = ((255, 64, 64), (64, 255, 64), (64, 64, 255), (255, 255, 64), (255, 64, 255), (64, 255, 255))[phase]
            elif kind == 22:
                v = ((x * 17 + y * 31) ^ (x * y)) & 255
                rgb = (v, (v * 5) & 255, (255 - v))
            elif kind == 23:
                v = 255 if ((x + y) % 2) else 0
                rgb = (v, v, 255 - v)
            elif kind == 24:
                v = 255 if ((x // 3) % 2) else 0
                rgb = (v, 32, 255 - v)
            elif kind == 25:
                v = 255 if ((y // 3) % 2) else 0
                rgb = (32, v, 255 - v)
            elif kind == 26:
                v = (x * y) % 256
                rgb = (v, (x * 7) % 256, (y * 11) % 256)
            elif kind == 28:
                distance = ((x - 112) * (x - 112) + (y - 112) * (y - 112)) ** 0.5
                v = min(255, int(distance * 2.0))
                rgb = (v, 255 - v, (v * 3) % 256)
            elif kind == 29:
                phase = (x * 3 + y * 5) % 8
                rgb = ((phase * 31) % 256, ((7 - phase) * 37) % 256, (phase * 17) % 256)
            elif kind == 30:
                bar = (x * 8) // WIDTH
                rgb = ((255, 0, 0), (255, 255, 0), (0, 255, 0), (0, 255, 255), (0, 0, 255), (255, 0, 255), (255, 255, 255), (0, 0, 0))[bar]
            elif kind == 31:
                phase = ((x % 8) // 2) + 4 * ((y % 8) // 2)
                rgb = ((phase * 23) % 256, (phase * 47) % 256, (255 - phase * 19) % 256)
            else:
                distance = min(x, y, WIDTH - 1 - x, HEIGHT - 1 - y)
                v = min(255, distance * 16)
                rgb = (v, 255 - v, (v * 2) % 256)
            pixels.append(rgb)
    return pixels


def main() -> int:
    CORPUS_DIR.mkdir(parents=True, exist_ok=True)
    manifest = json.loads(MANIFEST_PATH.read_text())
    existing = [sample for sample in manifest["samples"] if not sample["id"].startswith("stress-")]
    for kind in range(32):
        sample_id = f"stress-{kind:02d}"
        path = CORPUS_DIR / f"{sample_id}.png"
        png(path, generate(kind))
        import hashlib
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        existing.append({
            "id": sample_id,
            "relative_path": str(path.relative_to(ROOT)),
            "sha256": digest,
            "source_url": "https://github.com/Barap1/PlaneFuse",
            "license": "CC0-1.0 / repository-generated procedural stress input",
            "attribution": "PlaneFuse deterministic stress-corpus generator",
        })
    manifest["samples"] = existing
    manifest["schema_version"] = 2
    MANIFEST_PATH.write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"generated {len(existing)} corpus inputs")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
