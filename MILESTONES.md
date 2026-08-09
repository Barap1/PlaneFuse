# PlaneFuse milestone plan

Each milestone has a hard gate. Codex may iterate within the milestone but must not silently skip ahead.

The suggested commits are a target map, not a requirement to force artificial commits. The final history must contain at least 20 meaningful Conventional Commits; target 24-30.

## M0 - Reproducible engineering harness

Goal: Create the smallest reliable project structure and `./pf` command surface before researching optimizations in code.

Deliverables:

- Swift/Xcode or Swift-package structure chosen deliberately;
- `./pf doctor`;
- `./pf build`;
- `./pf test quick`;
- `./pf verify` placeholder/contract;
- `./pf bench quick` placeholder/contract;
- compact logging to `artifacts/logs/`;
- machine-readable benchmark result location;
- unit-test plumbing;
- environment metadata capture;
- STATUS updated.

Do not implement the native-plane optimization yet.

Gate:

- clean build succeeds;
- a test can run;
- `./pf` commands return compact output;
- verbose output is stored in files;
- benchmark/result schema is established.

Likely commits:

1. `chore(repo): initialize PlaneFuse project`
2. `chore(tooling): add reproducible project preflight`
3. `feat(harness): add compact pf command interface`
4. `test(harness): add smoke validation and result schema`

## M1 - Mathematical/reference proof

Goal: Prove the source-domain transform concept in a deterministic reference implementation before writing performance-oriented Metal.

Deliverables:

- explicit supported YUV/NV12 semantics;
- reference YUV-to-RGB conversion;
- reference normalization;
- simple compatible first linear/conv operation;
- transformed/native-plane formulation;
- synthetic and fixture tests;
- intermediate activation parity report;
- Sol Advisor review of the mathematical design.

Gate:

- reference and transformed paths agree within the documented numerical tolerance;
- unsupported assumptions are explicit;
- no threshold was loosened merely to pass.

Likely commits:

5. `test(math): add deterministic NV12 reference fixtures`
6. `feat(math): implement reference RGB preprocessing path`
7. `feat(math): implement native-plane stem transform`
8. `test(math): verify transformed activation parity`

## M2 - Fair optimized RGB baseline

Goal: Build Pipeline B first so PlaneFuse cannot win against a strawman.

Deliverables:

- native NV12 input fixture/pixel-buffer path;
- efficient Metal YUV/RGB preprocessing path;
- supported resize/normalization semantics;
- normal model/stem input;
- microbenchmark and allocation evidence;
- frozen baseline artifact tied to commit/system metadata.

Gate:

- Pipeline B is correct;
- obvious avoidable implementation mistakes are removed;
- repeated benchmark is stable enough to compare against;
- baseline JSON is recorded.

Likely commits:

9. `feat(baseline): add Metal NV12 to RGB preprocessing`
10. `perf(baseline): remove avoidable RGB preprocessing overhead`
11. `bench(baseline): capture optimized RGB reference results`

## M3 - First working PlaneFuse native stem

Goal: Implement Pipeline C for the same semantics/workload.

Deliverables:

- Metal kernel reads Y and UV planes directly;
- generated/transformed stem logic;
- no full RGB intermediate in C;
- first activation or equivalent output produced;
- parity tests against B/reference;
- quick benchmark;
- Sol Advisor implementation review.

Gate:

- correctness passes;
- no full RGB intermediate exists in C;
- benchmark is real, repeatable enough for M4 investigation.

Likely commits:

12. `feat(metal): add native-plane Metal stem`
13. `test(metal): add native stem parity validation`
14. `perf(metal): eliminate full RGB intermediate allocation`
15. `bench(metal): record first PlaneFuse comparison`

## M4 - Performance proof / kill gate

Goal: Determine whether the idea is competition-worthy against optimized B.

Method:

- run up to 3 evidence-driven optimization experiments;
- profile first, do not randomly tune;
- confirm apparent wins;
- collect latency plus at least one structural proof (allocation or profiler evidence).

Strong go signal:

- >=10% end-to-end improvement over optimized B; OR
- >=2x frontend/stem speedup plus substantial memory/bandwidth benefit with credible end-to-end value.

These are targets, not guaranteed outcomes.

Gate outcomes:

PASS: result is meaningful -> proceed.

MARGINAL: result is real but not compelling -> Sol Advisor plateau review before proceeding.

FAIL: no meaningful advantage -> stop productization and request human-approved architecture adjustment.

Likely accepted commits if warranted:

16. `perf(yuv420): exploit source chroma geometry in native stem`
17. `perf(metal): optimize native-plane memory access`
18. `bench(core): confirm native-plane performance advantage`

Do not create these commits if the experiments are rejected.

## M5 - Real pretrained model integration

Goal: Apply the technique to a real, licensable, meaningful vision model.

Deliverables:

- model-selection note based on stem compatibility, license, and use case;
- model integration;
- model-tail handoff;
- validation corpus;
- output agreement report;
- full end-to-end A/B/C benchmark.

Preferred use case: real-time semantic camera / zero-shot visual recognition if a suitable model (for example MobileCLIP) is practical.

Gate:

- real model runs fully locally;
- C remains correct;
- C advantage survives end-to-end integration;
- benchmark includes optimized B.

Likely commits:

19. `feat(model): integrate first pretrained vision workload`
20. `test(model): add output agreement validation corpus`
21. `bench(model): record end-to-end model results`

## M6 - Novel 4:2:0/source-grid optimization round

Goal: Push beyond simple shader fusion and establish the deepest technical contribution practical within the deadline.

Candidate hypotheses:

- phase-aware chroma sampling;
- interpolation folding;
- transformed coefficients that avoid unnecessary reconstruction work;
- patch/stem layout specialized to native source geometry;
- better threadgroup/shared-memory arrangement;
- direct tensor handoff.

Run at most 3 evidence-driven experiments before plateau review.

Gate:

- at least one accepted technically meaningful improvement OR a clear evidence-backed conclusion that the simpler native stem is already near the practical optimum;
- correctness preserved;
- claim language remains precise.

Likely commits:

22. `perf(yuv420): add phase-aware native chroma projection`
23. `perf(metal): tune threadgroup and source-plane access`

## M7 - Reusability / second compatible target

Goal: Demonstrate PlaneFuse is a technique/tool, not one hand-coded demo.

Deliverables:

- model/stem inspection abstraction;
- second compatible stem/model OR a clearly parameterized synthetic/reference architecture if a second real model is not feasible;
- reusable compile/verify interface.

Gate:

- at least two distinct compatible configurations can be processed by common code;
- compatibility limits are explicit.

Likely commits:

24. `feat(compiler): generalize native stem configuration`
25. `feat(model): support a second compatible vision stem`

## M8 - Developer experience

Goal: Turn the research result into something another developer can understand and run.

Deliverables:

- `planefuse inspect` equivalent;
- `planefuse compile` equivalent;
- `planefuse verify` equivalent;
- `planefuse bench` equivalent;
- clear errors for unsupported models/formats;
- reproducible sample workflow.

Gate:

- a developer can reproduce the supported example from README instructions without manually editing source.

Likely commits:

26. `feat(cli): add inspect compile verify and bench workflow`
27. `docs(dx): add reproducible developer quickstart`

## M9 - PlaneFuse Live showcase

Goal: Build the compelling user-facing proof only after the optimization is real.

Deliverables:

- macOS camera or controlled camera-frame source;
- local vision inference;
- meaningful task (prefer semantic search/zero-shot classification);
- A/B switch or side-by-side comparison;
- honest runtime/benchmark metrics;
- parity indicator;
- `RGB intermediate: 0` indicator based on architecture/instrumentation;
- polished enough for a 3-minute video.

Gate:

- useful local camera experience works;
- demo clearly communicates the optimization in <=15 seconds;
- UI does not display fabricated/live-looking metrics from static placeholders.

Likely commits:

28. `feat(demo): add PlaneFuse Live local camera experience`
29. `feat(demo): add verified A B performance dashboard`

## M10 - Evidence and submission package

Goal: Make judging easy even if judges never clone the repository.

Deliverables:

- final benchmark matrix;
- system-info artifact;
- profiler/allocation proof;
- architecture diagram;
- parity/quality report;
- clean README before/after table;
- Devpost draft;
- under-3-minute demo script;
- clean-clone reproduction run;
- final Sol hostile technical audit;
- final Sol rubric audit.

Gate:

- every public quantitative claim exists in `CLAIMS.md` with evidence;
- repository is public-ready under MIT;
- release history has >=20 meaningful Conventional Commits;
- clean clone reproduces required build/validation steps;
- final video/story matches actual project behavior.

Likely commits:

30. `docs(proof): add final benchmark and profiler evidence`
31. `docs(readme): publish reproducible results and architecture`
32. `docs(devpost): prepare hackathon submission narrative`
33. `test(release): verify clean clone reproduction`
34. `chore(release): prepare hackathon release candidate`

The project does not need all 34 commits. Some units may combine naturally. It must have at least 20 meaningful Conventional Commits and should normally finish in the 24-30 range.
