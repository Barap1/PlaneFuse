# Repository release audit

Audit basis: `phase2/continuum` at the final release-hardening commit. The
repository remains private and this audit does not publish or change GitHub.

## What ships

- Swift Package Manager source, Metal shaders, tests, `Package.swift`, and `pf`.
- Reproducible setup, verification, benchmark, evidence, and release scripts.
- MIT license, model/image notices, architecture docs, claims ledger, and
  judge-facing submission drafts.
- The fixed 64-input corpus, provenance manifest, compact accepted R7/R7.5
  evidence, sanitized profiler exports, and independent reviews needed to
  verify the final claim.

## Useful evidence and historical material

`proof/` contains accepted final artifacts plus clearly retained historical and
negative results. `benchmarks/artifact-index.json` classifies benchmark JSON as
`ACCEPTED`, `SUPERSEDED`, `REJECTED`, or `EXPERIMENTAL`; only accepted files
support current claims. Historical camera replays remain because their claims
link to them. Large raw profiler traces are not committed; compact sanitized
event exports and capture instructions are the public verification boundary.

## Generated and reproducible

`.build/`, `.pf-cache/`, `.swiftpm/`, `.venv/`, `models/`, generated Core ML
products, benchmark scratch output, local logs, profiler trace bundles, camera
captures, and IDE state are ignored. `./pf setup mobilenetv2` recreates model
assets locally; `./pf evidence` regenerates the judge page from authoritative
JSON.

## Local files intentionally not shipped

Two pre-existing user files, `artifacts/PlanetFuseInitial.md` and `codex-md.py`,
are preserved locally and are not part of the release candidate. Untracked
profiler trace bundles are also preserved locally and ignored. No broad cleanup
command is used.

## Publication-sensitive history

The current tree is privacy-scanned and contains sanitized profiler exports, but
private Git history previously contained profiler metadata. Do not publish this
history until a human chooses a history-sanitization strategy. See
[`PUBLICATION_PLAN.md`](PUBLICATION_PLAN.md) and
[`proof/profiler/RELEASE-PRIVACY-BLOCKER.md`](../proof/profiler/RELEASE-PRIVACY-BLOCKER.md).
