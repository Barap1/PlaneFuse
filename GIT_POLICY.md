# PlaneFuse Git and commit policy

## Goal

Use Git as reliable engineering history and rollback, not as a commit-count game.

Internal release requirement:

- at least 20 meaningful commits;
- every normal project commit uses Conventional Commits;
- target 24-30 meaningful commits by final submission;
- `main` should remain usable.

## Conventional Commit format

```text
<type>(<scope>): <imperative summary>
```

Allowed common types:

- `feat` - new product/runtime functionality;
- `fix` - bug fix;
- `perf` - performance improvement;
- `test` - tests/validation;
- `bench` - benchmark harness/results methodology artifact;
- `docs` - documentation/proof/submission docs;
- `refactor` - behavior-preserving structure change;
- `chore` - repo/tooling/maintenance;
- `build` - build system/dependency changes;
- `ci` - CI automation if added.

Recommended scopes:

`repo`, `tooling`, `harness`, `math`, `baseline`, `metal`, `yuv420`, `model`, `compiler`, `cli`, `demo`, `proof`, `readme`, `devpost`, `release`.

Examples:

```text
feat(metal): add native-plane Metal stem
perf(yuv420): reduce redundant chroma fetches
test(model): add output agreement corpus
bench(core): confirm native-plane frontend speedup
docs(readme): document reproducible benchmark workflow
```

Do not use:

```text
WIP
checkpoint
updates
stuff
fix things
try again
```

## When Codex should commit

Commit after a coherent stable unit, for example:

- a test fixture/reference implementation is complete;
- one feature compiles and relevant tests pass;
- a confirmed performance improvement is accepted;
- a benchmark baseline/evidence package is finalized;
- one developer-facing command works;
- a substantial documentation artifact is complete.

Do not commit after every file save.

## Performance experiments

Rejected uncommitted experiment:

- restore it;
- record the result in `EXPERIMENTS.md` if the lesson matters;
- no fake commit needed.

Accepted experiment:

- confirmation benchmark passes;
- commit it as `perf(...)`;
- tie benchmark result to the commit hash.

Risky large experiment:

- use `exp/<slug>` branch;
- keep `main` stable.

## Suggested natural commit map

The milestone plan already contains ~30 plausible commit units. A realistic final history may resemble:

1. chore(repo): initialize PlaneFuse project
2. chore(tooling): add reproducible project preflight
3. feat(harness): add compact pf command interface
4. test(harness): add smoke validation and result schema
5. test(math): add deterministic NV12 reference fixtures
6. feat(math): implement reference RGB preprocessing path
7. feat(math): implement native-plane stem transform
8. test(math): verify transformed activation parity
9. feat(baseline): add Metal NV12 to RGB preprocessing
10. perf(baseline): remove avoidable RGB preprocessing overhead
11. bench(baseline): capture optimized RGB reference results
12. feat(metal): add native-plane Metal stem
13. test(metal): add native stem parity validation
14. perf(metal): eliminate full RGB intermediate allocation
15. bench(metal): record first PlaneFuse comparison
16. perf(yuv420): exploit source chroma geometry in native stem
17. perf(metal): optimize native-plane memory access
18. bench(core): confirm native-plane performance advantage
19. feat(model): integrate first pretrained vision workload
20. test(model): add output agreement validation corpus
21. bench(model): record end-to-end model results
22. feat(compiler): generalize native stem configuration
23. feat(cli): add inspect compile verify and bench workflow
24. feat(demo): add PlaneFuse Live local camera experience
25. feat(demo): add verified A B performance dashboard
26. docs(proof): add final benchmark and profiler evidence
27. docs(readme): publish reproducible results and architecture
28. docs(devpost): prepare hackathon submission narrative
29. test(release): verify clean clone reproduction
30. chore(release): prepare hackathon release candidate

This is a map, not a mandate. Never split one trivial change into multiple commits merely to reach 20.

## Tags

Optional useful local tags after stable milestones:

```text
m1-math-proof
m2-rgb-baseline
m3-native-stem
m5-real-model
rc1
```

Do not publish tags without user approval.

## Push policy

Codex may commit locally.

Codex must ask before:

- `git push`;
- creating remote repositories;
- opening pull requests;
- making the project public.

## Release history check

Run:

```bash
./scripts/check_git_history.sh --release
```

The script checks count and commit-subject format. A passing script does not guarantee every commit is meaningful; Codex must also review the history qualitatively before release.
