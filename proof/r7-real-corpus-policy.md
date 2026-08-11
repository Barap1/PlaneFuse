# R7 real-corpus acquisition policy

This is the pre-registered, output-blind policy for the final R7 corpus. It is
an acquisition/import rule, not a benchmark result. The current repository
manifest is intentionally not modified by the tooling.

## Selection contract

The target is exactly eight semantic buckets with four real-image slots each:

`animals`, `plants_flowers`, `food_drink`, `vehicles`, `architecture_streets`,
`landscapes_nature`, `household_tools_electronics`, and
`miscellaneous_objects_textures`. Identifiable people are avoided where practical;
art/image/illustration queries are not a bucket and are not used to make art
dominant. The procedural half remains separate and is never used as a real-image
substitute.

For each bucket, the deterministic order is provider order
Wikimedia Commons, StockSnap, The Met open access, followed by the fixed query
list in `scripts/acquire_real_corpus.py`, then stable provider candidate ID.
The first candidate that passes the mechanical checks fills the next slot.
There is no random sampling, quality score, model score, label, activation,
probability, agreement, or benchmark result in selection or rejection logic.

## Sources and licenses

Wikimedia uses the Action API with `maxlag=5`, serial requests, a meaningful
PlaneFuse User-Agent, bounded retries for 429/503, and `Retry-After` handling.
Successful metadata and downloads are cached. Wikimedia candidates must carry
an authoritative page URL and an explicit CC0/public-domain license value.

StockSnap is accepted only when its originating page/license evidence is
available and explicitly identifies CC0; a search-result URL alone is not
evidence. The Met is a fallback for open-access objects only when the object
record is authoritative, open access is true, and its rights value is CC0 or
public domain. Provider adapters may use a deterministic, checked-in/offline
catalog so an unstable search page is never silently treated as provenance.

Every promoted record contains a stable ID, bucket, landing URL, creator when
available, license identifier, authoritative license-evidence URL, source host,
provider, downloaded SHA-256, committed local SHA-256, and deterministic
transform description.

## Mechanical import checks

Candidates must have supported PNG/JPEG bytes, a complete parseable image, a
bounded file size, dimensions no greater than 4096px, verified redistribution
rights, complete provenance, a unique stable ID, and a unique committed local
hash. The importer strips PNG ancillary metadata and JPEG EXIF/IPTC/COM
segments, preserving pixels; this moderate-resolution ceiling and transform are
recorded in provenance. Corrupt, unsupported, oversized, duplicate, or
incompletely documented candidates are rejected.

Every rejection is retained as a JSONL event with its candidate ID, bucket, and
machine-readable reason. Network access is serial and cached; backoff is
bounded, and the tool never busy-loops.

## Verification and fail-closed behavior

`check_r7_corpus.py` checks existence, format/corruption, declared and actual
hashes, duplicate local hashes, strict new-real provenance fields, exact bucket
slot counts, at least 32 real samples, at least 32 procedural samples, and
classification that prevents procedural samples from counting as real. Schema
v2 legacy entries remain readable so the current deficit is visible, but legacy
real entries do not satisfy the strict new-real provenance requirement.

No current corpus pass is claimed until the verifier prints PASS.
