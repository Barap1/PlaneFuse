# PlaneFuse final release handoff

## Final release commit

Source/evidence release candidate: `855622fab1612979ea42f244e837425c7554d94e`.
The handoff file itself is a metadata-only follow-up. The final fresh-clone
PASS is recorded in `proof/r0-clean-clone.json` and is bound to validated
candidate `1905d48e3f3196d582d10805a3da92a0f78ab726`.

## Final result

Accepted R7.5 confirmation:

- B2 p50: `1.737875 ms`
- accepted C1 p50: `1.633458 ms`
- C1-SR p50: `1.532583 ms`
- C1-SR: `6.1755%` below C1 and `11.8128%` below B2
- paired B2 − C1-SR median 95% CI: `[0.180250, 0.198792] ms`
- activation max error: `5.960464e-6`
- top-1, top-5 set, and top-5 ranking agreement: `1.0`
- independent Sol hostile review: `SHIP`, no findings
- T1: passed; T2/T3: not met or not established; T4: not invoked

Performance research is frozen.

## Automated validation

PASS:

- `swift build -c release`
- `swift test -c release` — 56 tests, 0 failures
- `./scripts/release_validate.sh` — fresh clone PASS in 160 seconds
- benchmark index, 64-input corpus, repaired R7, R7.5, camera provenance, and
  A/B/C matrix checkers
- profiler event checker and current-tree profiler privacy checker
- public privacy checker — 316 tracked text files
- release claims checker and generated judge-evidence freshness checker
- `./pf doctor`
- `./pf inspect mobilenetv2`
- `./pf verify`
- `./pf verify lineage`
- `./pf bench quick` — run to a temporary output; no headline result updated
- `./pf live --sample` — parity PASS, top-1 agreement `1.0`

The lineage command regenerated its legacy 64-sample diagnostic locally; that
generated change was restored so the authoritative R0 lineage artifact remains
unchanged and separately qualified.

## Camera/app

`./pf live --app` now builds and launches in Release mode. A bounded local
startup smoke passed without camera inference. The final UI has exact runtime
interpolation, precise post-resize timing labels, comparison-loop FPS semantics,
adaptive layout, resize-aware preview hosting, explicit B2/C1-SR resource
boundaries, and a friendly no-camera state.

The fresh R7 camera attempt received zero callbacks; no current camera metric is
claimed. Human visual inspection and physical-camera capture remain open.

## GitHub status

- Current branch: `phase2/continuum`
- Current local head: `855622fab1612979ea42f244e837425c7554d94e`
- `main`: `5af6e0451c232eae68d2b2f6bb6ce38513b52f83`
- Relationship: `main` is an ancestor; `phase2/continuum` is 114 commits ahead
  and has no independent newer `main` work.
- Remote/publication: private; no push, visibility change, force-push, video
  upload, or Devpost submission performed.
- Current tracked text privacy scan: PASS. Historical private profiler metadata
  remains a publication blocker; see `docs/PUBLICATION_PLAN.md`.

## Files removed from Git tracking / newly ignored

No tracked files were removed. `.gitignore` now excludes build and SwiftPM
caches, local environments and model products, logs, camera captures, profiler
trace bundles, temporary exports, and prior untracked R7 batch scratch. The two
pre-existing user files `artifacts/PlanetFuseInitial.md` and `codex-md.py` were
preserved untouched and are not release content.

## Publication recommendation

Use Option B in `docs/PUBLICATION_PLAN.md`: keep this private repository as the
archive and create a clean sanitized public release history from the validated
tree. This avoids exposing historical profiler metadata and avoids a risky
history rewrite. Make that sanitized tree the public default `main` only after a
fresh clone and privacy scan pass. Do not change visibility or push from this
checkout without explicit human approval.

## Sol review status

The two requested final Sol reviews were not invoked because the Sol skill's
required native preflight failed: its compatibility check expects missing
companion files under `~/.codex/agents`, while the project-local adapter is
valid. No fallback reviewer was substituted and no claim of fresh final Sol
review is made. The project-local adapter configuration is ready; after a human
reloads/repairs the configured native lane, obtain the technical/publication and
hackathon-judge reviews before external submission.

## Human actions remaining

1. Run `./pf live --app` and visually inspect the final dashboard; grant camera
   permission only if you want to capture physical-camera output.
2. Capture approved screenshots and the 2:30–2:45 video using `R9-DEMO-SCRIPT.md`.
3. Choose and execute Option B (or explicitly reviewed Option A) from
   `docs/PUBLICATION_PLAN.md`.
4. Make the sanitized final release tree the GitHub default `main`.
5. Make the repository public only after incognito/fresh-clone verification.
6. Upload the approved video and submit Devpost.
