#!/usr/bin/env python3
"""Deterministic, output-blind R7 real-image acquisition and import tool.

Only candidate metadata, file bytes, format, provenance, license, and hash are
used for promotion.  Model outputs and benchmark data are deliberately absent
from this program's inputs and code paths.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import struct
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import zlib
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable

UA = "PlaneFuse-R7-Corpus/1.0 (+https://github.com/Barap1/PlaneFuse; reproducible research acquisition)"
BUCKETS = ("animals", "plants_flowers", "food_drink", "vehicles", "architecture_streets", "landscapes_nature", "household_tools_electronics", "miscellaneous_objects_textures")
QUERIES = {
    "animals": ('incategory:"CC-Zero" animal', 'incategory:"Public domain" animal'),
    "plants_flowers": ('incategory:"CC-Zero" flower', 'incategory:"Public domain" plant'),
    "food_drink": ('incategory:"CC-Zero" food', 'incategory:"Public domain" drink'),
    "vehicles": ('incategory:"CC-Zero" vehicle', 'incategory:"Public domain" bicycle'),
    "architecture_streets": ('incategory:"CC-Zero" building', 'incategory:"Public domain" street'),
    "landscapes_nature": ('incategory:"CC-Zero" landscape', 'incategory:"Public domain" nature'),
    "household_tools_electronics": ('incategory:"CC-Zero" tool', 'incategory:"Public domain" household'),
    "miscellaneous_objects_textures": ('incategory:"CC-Zero" object', 'incategory:"CC-Zero" texture'),
}
PROVIDERS = ("wikimedia", "stocksnap", "met")
MAX_BYTES = 12 * 1024 * 1024
NON_PHOTOGRAPHIC_TERMS = (".svg", ".webm", ".tif", ".pdf", "diagram", "painting", "carpet", "rug_", "relief", "figurine", "statue", "sculpture", "drawing", "map_", "poster", "manuscript", "_met_")


def canonical(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def digest_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def request(url: str, *, retries: int, backoff: float, cache_path: Path | None = None) -> bytes:
    if cache_path and cache_path.is_file():
        return cache_path.read_bytes()
    last: Exception | None = None
    for attempt in range(retries + 1):
        req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "application/json,text/html,image/*,*/*;q=0.1"})
        try:
            with urllib.request.urlopen(req, timeout=30) as response:
                data = response.read(MAX_BYTES + 1)
                if len(data) > MAX_BYTES:
                    raise ValueError("response exceeds bounded size")
                if cache_path:
                    cache_path.parent.mkdir(parents=True, exist_ok=True)
                    cache_path.write_bytes(data)
                return data
        except urllib.error.HTTPError as exc:
            last = exc
            if exc.code not in (429, 503) or attempt == retries:
                raise
            retry_after = exc.headers.get("Retry-After")
            try:
                delay = min(60.0, max(0.5, float(retry_after))) if retry_after else min(60.0, backoff * (2 ** attempt))
            except ValueError:
                delay = min(60.0, backoff * (2 ** attempt))
            time.sleep(delay)
        except (urllib.error.URLError, TimeoutError, ValueError) as exc:
            last = exc
            if attempt == retries:
                raise
            time.sleep(min(60.0, backoff * (2 ** attempt)))
    raise RuntimeError(f"request failed: {last}")


def cache_file(cache: Path, key: str) -> Path:
    return cache / (hashlib.sha256(key.encode()).hexdigest() + ".bin")


def clean_png(data: bytes) -> bytes:
    if not data.startswith(b"\x89PNG\r\n\x1a\n"):
        return data
    output = bytearray(data[:8]); pos = 8
    keep = {b"IHDR", b"PLTE", b"IDAT", b"IEND", b"tRNS"}
    while pos + 12 <= len(data):
        length = struct.unpack(">I", data[pos:pos + 4])[0]
        end = pos + 12 + length
        if end > len(data):
            raise ValueError("truncated PNG")
        chunk = data[pos + 4:pos + 8]
        payload = data[pos + 8:pos + 8 + length]
        if chunk in keep:
            output.extend(struct.pack(">I", length) + chunk + payload + struct.pack(">I", zlib.crc32(chunk + payload) & 0xFFFFFFFF))
        pos = end
        if chunk == b"IEND":
            break
    return bytes(output)


def clean_jpeg(data: bytes) -> bytes:
    if not data.startswith(b"\xff\xd8"):
        return data
    output = bytearray(data[:2]); pos = 2
    while pos + 1 < len(data):
        if data[pos:pos + 2] == b"\xff\xda":
            eoi = data.find(b"\xff\xd9", pos)
            if eoi < 0:
                raise ValueError("JPEG scan has no EOI")
            output.extend(data[pos:eoi + 2])
            return bytes(output)
        if data[pos] != 0xFF:
            raise ValueError("invalid JPEG marker boundary")
        start = pos; pos += 1
        while pos < len(data) and data[pos] == 0xFF: pos += 1
        marker = data[pos]; pos += 1
        if marker in (0xD8, 0xD9):
            output.extend(data[start:pos]); continue
        if pos + 2 > len(data): raise ValueError("truncated JPEG segment")
        length = struct.unpack(">H", data[pos:pos + 2])[0]
        if length < 2 or pos + length > len(data): raise ValueError("truncated JPEG segment")
        # APP1/APP13 (EXIF/IPTC) and COM are unnecessary metadata/PII.
        if marker not in (0xE1, 0xED, 0xFE): output.extend(data[start:pos + length])
        pos += length
    raise ValueError("JPEG has no scan")


def image_format(data: bytes) -> str | None:
    if data.startswith(b"\x89PNG\r\n\x1a\n"): return "png"
    if data.startswith(b"\xff\xd8"): return "jpeg"
    return None


def evidence_license(candidate: dict[str, Any]) -> bool:
    license_id = str(candidate.get("license_id", "")).lower()
    evidence = str(candidate.get("license_evidence_text", "")).lower()
    provider = str(candidate.get("provider", "")).lower()
    if provider == "wikimedia": return "cc0" in license_id or "public domain" in license_id
    if provider == "stocksnap": return "cc0" in (license_id + " " + evidence)
    if provider == "met": return bool(candidate.get("open_access")) and ("cc0" in license_id or "public domain" in license_id)
    return False


def provider_plan() -> list[dict[str, str]]:
    return [{"provider": provider, "bucket": bucket, "query": query}
            for bucket in BUCKETS for provider in PROVIDERS for query in QUERIES[bucket]]


def wikimedia_candidates(query: str, *, cache: Path, retries: int, backoff: float) -> list[dict[str, Any]]:
    params = {"action": "query", "generator": "search", "gsrsearch": query, "gsrnamespace": "6", "gsrlimit": "10", "prop": "imageinfo|info", "iiprop": "url|size|mime|extmetadata", "inprop": "url", "iiurlwidth": "1600", "format": "json", "formatversion": "2", "maxlag": "5"}
    url = "https://commons.wikimedia.org/w/api.php?" + urllib.parse.urlencode(params)
    raw = request(url, retries=retries, backoff=backoff, cache_path=cache_file(cache, url))
    payload = json.loads(raw)
    result = []
    for page in sorted(payload.get("query", {}).get("pages", []), key=lambda x: str(x.get("pageid", ""))):
        info = (page.get("imageinfo") or [{}])[0]; meta = info.get("extmetadata", {})
        def text(key: str) -> str: return str((meta.get(key) or {}).get("value", "")).strip()
        result.append({"provider": "wikimedia", "stable_id": f"wikimedia-{page.get('pageid')}", "title": page.get("title", ""), "landing_url": page.get("canonicalurl") or page.get("fullurl"), "download_url": info.get("thumburl") or info.get("url"), "creator": text("Artist") or text("Credit"), "license_id": text("LicenseShortName") or text("UsageTerms"), "license_evidence_url": page.get("canonicalurl") or page.get("fullurl"), "license_evidence_text": text("UsageTerms") + " " + text("License"), "source_host": "commons.wikimedia.org", "width": info.get("thumbwidth") or info.get("width"), "height": info.get("thumbheight") or info.get("height"), "mime": info.get("mime")})
    return result


def catalog_candidates(path: Path, provider: str, bucket: str, query: str) -> list[dict[str, Any]]:
    if not path.is_file(): return []
    raw = json.loads(path.read_text())
    records = raw.get("candidates", raw) if isinstance(raw, dict) else raw
    return [dict(record, provider=record.get("provider", provider), bucket=bucket, query=query) for record in records if isinstance(record, dict) and record.get("provider", provider) == provider and record.get("bucket", bucket) == bucket and record.get("query", query) == query]


def log_event(stream, event: dict[str, Any]) -> None:
    stream.write(canonical(event) + "\n"); stream.flush()


def import_candidates(args: argparse.Namespace) -> int:
    work = Path(args.work_dir); work.mkdir(parents=True, exist_ok=True)
    output = Path(args.output_dir); output.mkdir(parents=True, exist_ok=True)
    candidates: list[dict[str, Any]] = []
    if args.candidate_file:
        loaded = json.loads(Path(args.candidate_file).read_text())
        candidates = loaded.get("candidates", loaded) if isinstance(loaded, dict) else loaded
    log_path = Path(args.log); log_path.parent.mkdir(parents=True, exist_ok=True)
    existing_records = []
    if args.manifest_in:
        existing_payload = json.loads(Path(args.manifest_in).read_text())
        existing_records = list(existing_payload.get("real_samples", []))
    existing_hashes: set[str] = {str(record.get("committed_sha256")) for record in existing_records if record.get("committed_sha256")}
    promoted: list[dict[str, Any]] = []; used_ids: set[str] = {str(record.get("id")) for record in existing_records if record.get("id")}
    slot_counts = json.loads(args.slot_counts) if args.slot_counts else {bucket: 4 for bucket in BUCKETS}
    with log_path.open("a", encoding="utf-8") as log:
        for candidate in sorted(candidates, key=lambda c: (BUCKETS.index(c.get("bucket")) if c.get("bucket") in BUCKETS else 999, PROVIDERS.index(c.get("provider")) if c.get("provider") in PROVIDERS else 999, QUERIES.get(c.get("bucket"), ()).index(c.get("query")) if c.get("query") in QUERIES.get(c.get("bucket"), ()) else 999, str(c.get("stable_id", "")))):
            ident = str(candidate.get("stable_id", "")); bucket = candidate.get("bucket")
            reason = None
            if bucket not in BUCKETS: reason = "invalid_bucket"
            elif len([x for x in promoted if x["bucket"] == bucket]) >= int(slot_counts.get(bucket, 0)): reason = "bucket_slots_full"
            elif ident in used_ids: reason = "duplicate_stable_id"
            elif not evidence_license(candidate): reason = "license_not_verified"
            elif not all(candidate.get(k) for k in ("landing_url", "license_evidence_url", "source_host", "provider")): reason = "incomplete_provenance"
            elif candidate.get("width") and candidate.get("height") and (int(candidate["width"]) > 4096 or int(candidate["height"]) > 4096): reason = "source_dimensions_exceed_4096px"
            elif any(term in (str(candidate.get("title", "")) + " " + str(candidate.get("download_url", ""))).lower() for term in NON_PHOTOGRAPHIC_TERMS): reason = "non_photographic_or_unsupported_source"
            if reason:
                log_event(log, {"event": "rejected", "stable_id": ident, "bucket": bucket, "reason": reason}); continue
            try:
                source = Path(candidate["local_path"]).read_bytes() if candidate.get("local_path") else request(candidate["download_url"], retries=args.retries, backoff=args.backoff, cache_path=cache_file(work / "downloads", candidate["download_url"]))
                if len(source) > MAX_BYTES: raise ValueError("file_too_large")
                fmt = image_format(source)
                if fmt not in ("png", "jpeg"): raise ValueError("unsupported_file_format")
                source_hash = digest_bytes(source)
                derivative = clean_png(source) if fmt == "png" else clean_jpeg(source)
                committed_hash = digest_bytes(derivative)
                if committed_hash in existing_hashes: raise ValueError("duplicate_local_hash")
                filename = f"{args.filename_prefix}real-{bucket}-{len([x for x in promoted if x['bucket'] == bucket]):02d}.{ 'jpg' if fmt == 'jpeg' else 'png'}"
                path = output / filename; path.write_bytes(derivative)
            except Exception as exc:
                log_event(log, {"event": "rejected", "stable_id": ident, "bucket": bucket, "reason": str(exc)}); continue
            used_ids.add(ident); existing_hashes.add(committed_hash)
            promoted.append({"id": ident, "kind": "real", "bucket": bucket, "relative_path": str(path), "landing_url": candidate["landing_url"], "source_url": candidate["landing_url"], "creator": candidate.get("creator", ""), "attribution": candidate.get("creator", ""), "license_id": candidate["license_id"], "license": candidate["license_id"], "license_evidence_url": candidate["license_evidence_url"], "source_host": candidate["source_host"], "provider": candidate["provider"], "downloaded_sha256": source_hash, "committed_sha256": committed_hash, "sha256": committed_hash, "deterministic_transform": "downloaded deterministic provider thumbnail (max 1600px where supplied), then stripped PNG ancillary metadata or JPEG EXIF/IPTC/COM segments; preserve pixels"})
            log_event(log, {"event": "promoted", "stable_id": ident, "bucket": bucket, "committed_sha256": committed_hash})
    if args.manifest_out:
        Path(args.manifest_out).write_text(json.dumps({"schema_version": 2, "real_samples": existing_records + promoted}, indent=2, sort_keys=True) + "\n")
    print(f"Import complete: promoted={len(promoted)} log={log_path} (no model/output fields inspected)")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Output-blind R7 real-corpus acquisition/import. Providers are serial, deterministic, cached, and fail closed.")
    parser.add_argument("--mode", choices=("dry-run", "acquire", "import"), default="dry-run", help="dry-run prints the preregistered plan; acquire fetches metadata; import promotes verified candidates")
    parser.add_argument("--candidate-file", help="JSON catalog for deterministic StockSnap/Met or offline imports")
    parser.add_argument("--work-dir", default="artifacts/r7-corpus", help="cache and acquisition workspace")
    parser.add_argument("--output-dir", default="artifacts/r7-real", help="derivative output directory for --mode import")
    parser.add_argument("--manifest-out", help="write promoted real-sample records; never edits the existing manifest")
    parser.add_argument("--manifest-in", help="existing promoted-real manifest to extend without reselecting its records")
    parser.add_argument("--filename-prefix", default="", help="prefix for imported derivative filenames")
    parser.add_argument("--slot-counts", help="JSON object of remaining output slots by bucket; default is four per bucket")
    parser.add_argument("--metadata-out", help="write the acquired deterministic candidate catalog")
    parser.add_argument("--log", default="artifacts/logs/r7-corpus-acquisition.jsonl", help="append-only machine-readable rejection/promote log")
    parser.add_argument("--providers", nargs="+", choices=PROVIDERS, default=list(PROVIDERS), help="provider order; default is Wikimedia, StockSnap, The Met")
    parser.add_argument("--retries", type=int, default=3, help="bounded retries for 429/503/network errors")
    parser.add_argument("--backoff", type=float, default=1.0, help="initial bounded exponential backoff seconds")
    args = parser.parse_args()
    if args.mode == "dry-run":
        print("Output-blind R7 plan: 8 buckets x 4 slots; provider/query order is deterministic.")
        print("Provider order: " + ", ".join(args.providers) + "; metadata cache: " + str(Path(args.work_dir) / "metadata"))
        for item in provider_plan():
            if item["provider"] in args.providers: print(f"{item['bucket']}\t{item['provider']}\t{item['query']}")
        return 0
    if args.mode == "import": return import_candidates(args)
    cache = Path(args.work_dir) / "metadata"
    candidates: list[dict[str, Any]] = []
    failures: list[dict[str, Any]] = []
    catalog = Path(args.candidate_file) if args.candidate_file else Path("__missing_catalog__")
    for item in provider_plan():
        if item["provider"] not in args.providers:
            continue
        try:
            if item["provider"] == "wikimedia":
                found = wikimedia_candidates(item["query"], cache=cache, retries=args.retries, backoff=args.backoff)
            else:
                # StockSnap and The Met are deliberately catalog-driven: the
                # catalog must contain originating license evidence and keeps
                # search/ranking deterministic without scraping a changing UI.
                found = catalog_candidates(catalog, item["provider"], item["bucket"], item["query"])
            for candidate in found:
                candidate["bucket"] = item["bucket"]
                candidate["query"] = item["query"]
            candidates.extend(found)
        except Exception as exc:
            failures.append({"event": "metadata_rejected", "provider": item["provider"], "bucket": item["bucket"], "query": item["query"], "reason": type(exc).__name__ + ": " + str(exc)})
    out = Path(args.metadata_out or (Path(args.work_dir) / "candidates.json"))
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps({"schema_version": 1, "output_blind": True, "candidates": candidates, "rejections": failures}, indent=2, sort_keys=True) + "\n")
    print(f"Acquisition complete: candidates={len(candidates)} metadata_rejections={len(failures)} catalog={out} cache={cache}")
    return 0


if __name__ == "__main__": sys.exit(main())
