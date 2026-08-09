# PlaneFuse root instructions for Codex

These instructions apply to the entire PlaneFuse repository unless a future nested `AGENTS.md` explicitly narrows behavior for a subdirectory.

## 1. Mission

Build PlaneFuse into an unusually strong entry for the Arm Create: AI Optimization Challenge 2026, Mobile AI track.

PlaneFuse should become both:

1. a technically defensible Apple-Silicon optimization technique/tool; and
2. a compelling fully local camera-AI demonstration that makes the optimization obvious to a judge in seconds.

The current technical hypothesis is documented in `SPEC.md`. Do not silently replace the project with a different idea.

## 2. Required read order

At the start of a fresh Codex session:

1. Read this file automatically/in full.
2. Read `STATUS.md`.
3. Read the current milestone section in `MILESTONES.md`.
4. Read only the relevant sections of `SPEC.md` and `BENCHMARK_CONTRACT.md` for the task.
5. Read `DECISIONS.md` only when an architectural decision is relevant.
6. Read `EXPERIMENTS.md` only when doing performance work or avoiding repeated failed hypotheses.
7. Read `CLAIMS.md` only when producing benchmark claims, documentation, or submission materials.

Do not load every project document into context on every small task.

## 3. Autonomy boundaries

You MAY without asking:

- inspect all files inside this repository;
- create/modify/delete project files when needed for the current milestone;
- create project-local virtual environments, Swift packages, build folders, fixtures, and dependencies;
- run builds, tests, profilers, and benchmarks;
- use XcodeBuildMCP tools that are already configured;
- use ordinary local shell commands;
- create local Git branches for risky experiments;
- make local Git commits that follow `GIT_POLICY.md`;
- revert your own uncommitted or experiment-branch changes;
- update `STATUS.md`, `EXPERIMENTS.md`, `DECISIONS.md`, and benchmark state files;
- research official technical documentation when needed for a real blocker or high-leverage decision.

You MUST ask before:

- installing or removing system-wide software not already approved in the setup docs;
- changing global Git configuration;
- changing macOS security/privacy settings;
- changing code-signing identities or provisioning;
- publishing, pushing, creating a public GitHub repository, or opening a PR;
- uploading artifacts externally;
- spending money or creating paid cloud resources;
- entering credentials/secrets;
- making a major project pivot away from PlaneFuse;
- changing a benchmark correctness threshold in a way that makes an existing failure pass;
- changing the selected hackathon track.

You MUST NOT:

- invent benchmark results;
- claim bandwidth, power, memory, or quality improvements that were not measured;
- use a deliberately weak baseline to inflate a speedup;
- hide failed experiments or quality regressions;
- run destructive commands outside this repository;
- push secrets or local machine identifiers into Git;
- create meaningless commits merely to increase commit count.

## 4. Technical truth outranks the idea

PlaneFuse is a hypothesis. The current idea is valuable only if measurements support it.

The strongest comparison is always:

A. ordinary/reference pipeline;
B. properly optimized RGB/Metal pipeline;
C. PlaneFuse native-plane pipeline.

Pipeline C must meaningfully beat Pipeline B for the strongest performance claims.

If C cannot beat B after the defined M4 investigation budget, stop polishing. Produce a concise evidence-backed failure analysis and request a human-approved architecture review. Do not autonomously switch to an unrelated AI project.

## 5. Work in small, verified units

For each coding task:

1. Restate the local objective internally.
2. Inspect only files needed for the change.
3. Make the smallest coherent implementation.
4. Run the cheapest validation that can catch likely errors.
5. If the change affects performance, run `./pf bench quick` once the harness exists.
6. If the change appears better, run confirmation only when justified.
7. Commit a stable, meaningful unit using Conventional Commits.
8. Update project state only when the result changes what future work needs to know.

Avoid giant speculative rewrites.

## 6. Testing policy

Do not reflexively run the entire test/benchmark suite after every edit.

Use this hierarchy:

- documentation-only change -> no build unless links/generated output are affected;
- isolated pure Swift/math change -> relevant unit test;
- model transform change -> parity tests;
- Metal kernel change -> compile + relevant parity test + microbenchmark;
- integration change -> targeted integration test;
- performance candidate -> quick benchmark;
- apparent performance win -> confirmation benchmark;
- milestone/release -> full validation.

Never rerun an unchanged expensive check merely for reassurance.

## 7. Xcode and Apple tooling

Prefer XcodeBuildMCP structured tools over raw `xcodebuild`, `xcrun`, or simulator commands when a configured MCP operation cleanly supports the task.

Use raw shell/Xcode commands when:

- XcodeBuildMCP does not expose the needed operation;
- a deterministic benchmark script must invoke a specific command;
- a profiler/export workflow requires a direct Apple tool;
- the structured tool is broken and the workaround is documented.

Do not enable extra XcodeBuildMCP workflows until required. Tool catalogs consume context.

## 8. Sol Advisor policy

Sol Advisor is a milestone reviewer, not the default executor for every task.

Use Sol Advisor when requested by `MILESTONES.md` or when one of these occurs:

- mathematical/architecture commitment;
- first native-plane Metal implementation;
- performance plateau after a bounded experiment round;
- major model/runtime integration;
- final technical-judge audit;
- final full-rubric audit.

Do not invoke Sol Advisor for formatting, small bug fixes, routine tests, documentation cleanup, or ordinary refactors.

When Sol Advisor is used, the parent Codex session still owns acceptance. Worker/advisor reports are claims until the parent checks the actual diff and evidence.

## 9. Model/cost policy

Treat the user's Codex Plus allowance as scarce.

Default parent session: a cost-efficient strong model/reasoning combination selected by the user, normally Terra/medium when available.

Escalate only when evidence justifies it:

- Terra/high: difficult Metal, compiler, numerical, or integration debugging;
- Sol/high: architecture, plateau diagnosis, or skeptical final review.

Never spend Sol on routine implementation if Terra can do it reliably.

Do not repeatedly summarize large files into chat. Durable facts belong in repo files.

## 10. Context hygiene

Keep model-visible output small.

Build/test scripts should:

- write verbose logs under `artifacts/logs/`;
- print a compact PASS/FAIL summary;
- include the path to the full log;
- print only the most relevant error lines on failure.

Benchmark tools should print compact metrics and write complete machine-readable results under `benchmarks/results/`.

Read large logs only when needed to diagnose a failure.

## 11. Performance experiment discipline

Follow `EXPERIMENT_PROTOCOL.md`.

Default optimization round: at most 3 evidence-driven experiments.

An experiment must state:

- observed bottleneck/evidence;
- hypothesis;
- smallest proposed change;
- correctness check;
- benchmark to run;
- outcome.

After 3 non-improving credible experiments, declare a plateau instead of random micro-tuning.

## 12. Git policy

Follow `GIT_POLICY.md`.

Requirements:

- use Conventional Commits;
- target 24-30 meaningful commits by final submission;
- minimum release gate: 20 meaningful Conventional Commits;
- commit after each stable coherent unit, not after every file save;
- keep `main` working;
- use `exp/<slug>` branches for risky optimization experiments when useful;
- do not push without human approval.

Rejected uncommitted experiments should be restored, not committed merely to preserve activity.

## 13. Project-state files

Maintain these deliberately:

- `STATUS.md`: current milestone, current best result, blockers, next action.
- `DECISIONS.md`: durable architectural decisions and why.
- `EXPERIMENTS.md`: concise experiment record, including failures.
- `CLAIMS.md`: only claims we can defend with evidence.
- `benchmarks/best.json`: current best verified benchmark result.
- `benchmarks/history.jsonl`: append-only machine-readable benchmark history once harness exists.

Do not turn state files into chatty diaries.

## 14. Quality bar

The project should look like serious systems/ML engineering, not hackathon theater.

Before calling a milestone done, ask:

- Is the technical claim actually true?
- Is the baseline fair?
- Can another developer reproduce it?
- Does this exploit an Arm/Apple-Silicon property rather than just run on Arm?
- Is the improvement useful to a real camera/vision workload?
- Would a skeptical Arm engineer understand why it is faster?
- Is there an artifact proving the claim?

## 15. User-facing meaning

The final demo, if the technical gates pass, is `PlaneFuse Live`: local camera intelligence that uses a real vision workload and shows the optimization live.

Do not let the demo become a fake visualization. Metrics shown in the UI must come from real measured runtime state or clearly labeled benchmark results.

## 16. Completion reports

At a routine task boundary, report only:

- what changed;
- validation run;
- commit hash/message;
- whether the milestone gate changed;
- next highest-leverage action.

At a milestone boundary, additionally report:

- current best metrics;
- correctness status;
- important failed approaches;
- hackathon-score impact;
- whether human approval is needed.
- If using XcodeBuildMCP, use the installed XcodeBuildMCP skill before calling XcodeBuildMCP tools.

<!-- PLANEFUSE_PHASE2_RULES_START -->
## Active Phase 2 continuation rules

- For work after the original M11 snapshot, read `SPEC_V2_ADDENDUM.md`, `RESEARCH_FRONTIER.md`, `MILESTONES_V2.md`, and `BENCHMARK_CONTRACT_V2.md` before implementation.
- Treat `MILESTONES_V2.md` as the active continuation sequence. Preserve all previously accepted evidence; do not rewrite history to make a new result look better.
- R0 is mandatory. Do not begin frontier optimization until R0 passes and the repository is again internally truthful and clean-clone reproducible.
- The primary current-environment research order is: shared-buffer Core ML bridge, IOSurface-backed bridge, Metal 4 GPU-timeline feasibility, then polyphase 4:2:0 compilation. Profile first and keep only measured wins.
- Do not install Xcode beta, macOS beta, Core AI beta tooling, or other system-wide software without explicit human approval. Core AI is an optional research branch, not a release dependency.
- Compare every candidate against the strongest credible conventional baseline using the same tail, precision, input, bridge class, and measurement boundary wherever technically possible.
- The repository already exceeds its commit-count target. Aim for roughly 8-15 additional coherent Conventional Commits across Phase 2; do not fragment work to inflate history.
- Keep the existing private remote as a backup. Never make it public or submit externally without explicit human approval.
<!-- PLANEFUSE_PHASE2_RULES_END -->
