# PlaneFuse performance experiment protocol

## Purpose

Optimization research becomes wasteful when an agent keeps making random low-confidence tweaks. This protocol limits each round and forces evidence-driven iteration.

## One experiment

Before changing code, record mentally or in `EXPERIMENTS.md`:

- Observation: what evidence suggests a bottleneck?
- Hypothesis: why should this specific change improve it?
- Change: smallest implementation that tests the hypothesis.
- Correctness check: what must still pass?
- Benchmark: which tier is sufficient?
- Stop condition: what result would reject the hypothesis?

## Default round

A normal optimization round contains at most 3 credible experiments.

For each:

1. Start from the current best verified commit or a clean experiment branch.
2. Implement one main idea.
3. Run targeted correctness.
4. Run quick benchmark.
5. If clearly worse: reject and restore.
6. If inconclusive: record as inconclusive; do not repeatedly rerun until luck produces a win.
7. If clearly better: run confirmation.
8. If confirmed: commit with `perf(...)` or another appropriate Conventional Commit and update `benchmarks/best.json`.
9. Append a concise entry to `EXPERIMENTS.md`.

## Plateau rule

Declare a plateau when 3 consecutive well-motivated experiments fail to produce a meaningful confirmed improvement.

At a plateau:

- stop random tuning;
- capture the latest profiler/benchmark evidence;
- summarize what has been tried;
- invoke the Sol Advisor plateau prompt in `PROMPTS.md`;
- ask for materially different hypotheses, not more parameter fiddling.

## Experiment branches

Use `exp/<short-slug>` when a change is risky or likely to touch many lines.

Examples:

- `exp/phase-aware-chroma`
- `exp/threadgroup-tiling`
- `exp/direct-tail-tensor`

If rejected before commit, restore/delete the branch.

If accepted, merge/rebase in a clean way that preserves a meaningful Conventional Commit on main. Do not keep dozens of dead branches as project state.

## Failure record format

Keep `EXPERIMENTS.md` compact:

```text
### E07 - phase-aware UV fetch
Commit/base: abc1234
Evidence: UV reconstruction accounted for X% of measured frontend region.
Hypothesis: ...
Change: ...
Correctness: PASS/FAIL ...
Quick: ...
Confirm: ... / not run
Outcome: ACCEPT / REJECT / INCONCLUSIVE
Lesson: one sentence that prevents repeating the same mistake.
```

## Do not optimize vanity metrics

An isolated kernel speedup is useful only if:

- it is in the real critical path; or
- it produces a structural result important to the hackathon story.

Always check whether frontend improvements survive into end-to-end inference.
