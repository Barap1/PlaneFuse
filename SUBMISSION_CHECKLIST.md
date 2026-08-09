# Final submission checklist

Do not use this until M10, but keep requirements visible.

## PlaneFuse Phase 2 hardening snapshot

The following are local evidence only and are not external submission approval:

- [x] Real Apple MobileNetV2/ImageNet B/C proof and two accepted 100-iteration confirmations.
- [x] Current-state confirmation and machine-readable final matrix committed.
- [x] M1–M11 technical evidence index and claims ledger synchronized.
- [x] Arm64/local Metal + Core ML path and reproducible CLI workflow.
- [x] Camera adapter captures native NV12 and refuses to fabricate metrics when permission/assets are unavailable.
- [x] R0 one-frame physical-camera smoke on a permitted device.
- [ ] R6 continuous 300-frame camera run/video capture.
- [x] R0 expanded 32-input corpus, direct source-image lineage, and artifact classification.
- [x] R0 clean-clone validation artifact.
- [ ] Public repository approval and push.
- [ ] External hackathon submission.

## Repository

- [ ] Public GitHub repository approved by user.
- [ ] MIT license visible.
- [ ] No secrets/personal machine identifiers.
- [ ] Source required to build/run is present.
- [ ] Third-party model/code licenses documented.
- [ ] Clean-clone build instructions tested.
- [ ] >=20 meaningful Conventional Commits.
- [ ] `./scripts/check_git_history.sh --release` passes.

## Technical proof

- [ ] Pipeline A definition.
- [ ] Optimized Pipeline B definition.
- [ ] PlaneFuse Pipeline C definition.
- [ ] Same-work benchmark conditions.
- [ ] Raw final result files committed.
- [ ] Correctness/parity report.
- [ ] Allocation/no-RGB evidence.
- [ ] Bandwidth evidence only if actually measured.
- [ ] Power/energy claim only if actually measured.
- [ ] System metadata without PII.
- [ ] Profiler screenshots/captures.

## Developer experience

- [ ] 5-minute-or-less quickstart for supported example.
- [ ] inspect/compile/verify/bench workflow documented.
- [ ] clear unsupported-format/model behavior.
- [ ] expected output shown.

## Devpost write-up

- [ ] Project overview and purpose.
- [ ] Why it is interesting/should win.
- [ ] Functionality/output.
- [ ] Step-by-step build/run/validate on Arm device.
- [ ] Explicit Mobile AI track alignment.
- [ ] Clear before -> technical change -> after story.
- [ ] Reusable developer impact.
- [ ] Limitations stated precisely.

## Video

- [ ] Under 3 minutes; target 2:30-2:40.
- [ ] Shows project operating on intended Apple-Silicon device.
- [ ] First 15 seconds explain the value.
- [ ] Actual A/B result shown.
- [ ] Quality/parity shown.
- [ ] Native-plane architecture explained simply.
- [ ] No unlicensed music/assets/trademarks used improperly.
- [ ] Public upload approved by user.

## Claims

- [ ] Every quantitative claim in README/Devpost/video exists as VERIFIED/QUALIFIED in `CLAIMS.md`.
- [ ] No "world first" or novelty claim without real prior-art support.
- [ ] No generic Apple performance claim extrapolated from one device/model.
