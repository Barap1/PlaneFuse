# Final submission checklist

This is an internal release checklist. A checked item means the repository has
evidence for it; it does not authorize external publication.

## Complete in the repository

- [x] Swift/Metal source, tests, `Package.swift`, and MIT license.
- [x] Reproducible `doctor`, `setup`, `inspect`, `compile`, `verify`, `bench`,
  `evidence`, and `live` command paths documented honestly.
- [x] Final R7.5 evidence, fixed 64-input corpus, profiler export, A/B/C matrix,
  and independent Sol SHIP review.
- [x] T1 passed; T2/T3 not met or established; T4 not invoked.
- [x] Claims ledger, final README, architecture guide, judge evidence page, and
  third-party notices are synchronized.
- [x] PlaneFuse Live app implementation with LIVE/STORED separation, precise
  timing boundaries, camera failure state, and Release launch path.
- [x] Negative results and limitations remain visible; no universal claim.
- [x] Current-tree privacy scan and publication plan.
- [x] Clean-clone release validation artifact and release-history checker.
- [x] Repository hygiene audit and comprehensive ignore rules.

## Automated gates to run at final code state

- [ ] `./scripts/release_validate.sh` on the final release candidate.
- [ ] `./pf doctor`, `./pf inspect mobilenetv2`, `./pf verify`,
  `./pf verify lineage`, `./pf bench quick`, and `./pf live --sample`.
- [ ] Full tests and all evidence checkers listed in `FINAL_RELEASE_HANDOFF.md`.
- [ ] Final clean-clone PASS bound to the final release commit.

## Human remaining

- [ ] Run `./pf live --app` and visually inspect final dashboard on the intended
  Apple-Silicon machine; grant camera permission if desired.
- [ ] Capture approved screenshots and a 2:30–2:45 video.
- [ ] Choose and execute the privacy-safe public-history strategy in
  [`docs/PUBLICATION_PLAN.md`](docs/PUBLICATION_PLAN.md).
- [ ] Make the sanitized final release branch/tree the GitHub default `main`.
- [ ] Change repository visibility only after fresh-clone/incognito verification.
- [ ] Upload the approved video and submit Devpost.

## Do not claim

- [ ] Do not claim continuous camera throughput from the comparison-loop FPS.
- [ ] Do not claim a current physical-camera result after a zero-callback run.
- [ ] Do not claim power, bandwidth, universal model coverage, or Apple-wide
  performance.
