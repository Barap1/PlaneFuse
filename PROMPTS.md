# Copy/paste prompts for Codex

Use these from a Codex session opened at `~/Documents/Projects/PlaneFuse`.

## Setup verification prompt

```text
Read the root AGENTS.md. Inspect STATUS.md and the local environment only enough to answer this request. Report: current project path, current milestone, Git branch and commit count, whether XcodeBuildMCP is available, whether Sol Advisor appears configured, and any blocking setup issue. Do not modify files, do not install anything, do not invoke an advisor, and keep the answer concise.
```

## Prompt 0 - Bootstrap M0

```text
Execute M0 only from MILESTONES.md.

Follow root AGENTS.md. First read STATUS.md, the M0 section of MILESTONES.md, CODEX_WORKFLOW.md, GIT_POLICY.md, and only the portions of SPEC.md/BENCHMARK_CONTRACT.md needed to establish the harness contracts.

Create the smallest reproducible native Apple-Silicon project/harness that lets future work build, run targeted tests, verify correctness, and benchmark with compact output. Establish a ./pf interface or equivalent matching the M0 contract. Verbose logs must go to artifacts/logs. Machine-readable benchmark results must have a stable location/schema.

Do not implement the PlaneFuse native-plane optimization yet. Do not choose a real model yet. Do not build UI. Do not install system-wide software.

Work autonomously within M0. Make meaningful local Conventional Commits after stable coherent units, following GIT_POLICY.md. Keep main working. Update STATUS.md when the gate changes.

Stop only when M0 passes or when a real blocker requires human input. Report a concise milestone summary with commit hashes/messages.
```

## Prompt 1 - M1 mathematical proof with Sol Advisor

```text
Execute M1 only.

Use $sol-advisor:orchestration because this milestone commits us to the mathematical/reference design. The parent session remains responsible for checking the actual diff and tests before acceptance.

Goal: prove a tightly scoped NV12/YUV -> RGB/normalization -> first-linear-operation reference path can be represented by an equivalent native-plane formulation under explicitly supported semantics. Build deterministic fixtures and compare intermediate activations. Do not write the production Metal optimization yet.

Follow BENCHMARK_CONTRACT.md correctness rules. If color range, matrix, interpolation, clamping, or precision semantics prevent exact folding, preserve correctness and document the boundary instead of forcing a prettier formula.

Make meaningful Conventional Commits as stable units pass. Update DECISIONS.md only for durable choices and STATUS.md at the gate. Stop at M1 PASS/FAIL and report the evidence.
```

## Prompt 2 - M2 optimized RGB baseline

```text
Execute M2 only.

Build Pipeline B: a fair optimized Apple-Silicon RGB/Metal input path for the exact supported source semantics established in M1. The purpose is to create the strongest reasonable baseline that still materializes the RGB/model-input representation.

Do not implement Pipeline C yet. Do not weaken the baseline to make PlaneFuse look better.

Use XcodeBuildMCP structured operations where appropriate and the ./pf harness for deterministic checks. Add only the profiling/instrumentation required to understand frontend cost. Run targeted correctness first, then quick/confirm benchmarks as justified.

Make local Conventional Commits for stable coherent units. Freeze a machine-readable baseline result tied to the commit/system metadata when M2 passes. Update STATUS.md.
```

## Prompt 3 - M3 first PlaneFuse native stem

```text
Execute M3 only and use $sol-advisor:orchestration for the major implementation/review gate.

Implement Pipeline C for the same supported semantics as Pipeline B. The native path must read the Y and UV planes directly and produce the first model activation/equivalent without materializing a full RGB intermediate.

Correctness comes first. Add activation parity checks before optimizing aggressively. Then run the smallest meaningful quick benchmark against Pipeline B.

Do not build the final demo or select extra models. Keep scope to a working, verifiable native-plane stem.

The parent must inspect the diff and evidence after Sol Advisor returns. Make meaningful Conventional Commits. Stop at M3 PASS/FAIL and summarize parity, structural proof of no full RGB intermediate, first benchmark, and commits.
```

## Prompt 4 - Bounded performance round

```text
Run one bounded performance experiment round against the current best verified PlaneFuse implementation.

Read the relevant recent entries in EXPERIMENTS.md, benchmarks/best.json, STATUS.md, and current profiler evidence. Run at most THREE evidence-driven experiments.

For each experiment:
1. state the observed bottleneck and one hypothesis;
2. make the smallest change that tests it;
3. run targeted correctness;
4. run ./pf bench quick;
5. reject/restore clear regressions;
6. confirm only apparent meaningful wins;
7. commit accepted wins using Conventional Commits;
8. append a concise EXPERIMENTS.md entry.

Do not repeatedly rerun inconclusive benchmarks until noise produces a win. After three non-improving credible experiments, declare a plateau and stop. Return only the accepted result(s), rejected hypotheses worth remembering, and whether a Sol architecture review is now justified.
```

## Prompt 5 - Plateau / kill-gate Sol review

```text
Use $sol-advisor:orchestration for a read-mostly architecture/performance review. Do not immediately implement a new direction.

We have reached a PlaneFuse performance plateau or M4 kill gate. Review the current Pipeline B/C architecture, profiler evidence, benchmarks, correctness data, and recent EXPERIMENTS.md failures.

Act as a skeptical Apple-Silicon inference/performance engineer. Identify the actual dominant costs, determine whether our measurement boundary is honest, and propose at most THREE materially different technical hypotheses ranked by expected impact and implementation risk.

Explicitly answer:
- Is the core PlaneFuse thesis still technically promising?
- Is the optimized RGB baseline fair?
- Are we moving cost outside the measured region?
- Which single experiment has the highest information value next?
- Should we continue, narrow the claim, or request a project pivot?

Do not change project direction without human approval. The parent should summarize the recommendation and stop for a decision if a major pivot is proposed.
```

## Prompt 6 - M5 real model integration

```text
Execute M5 only.

First evaluate a very small set of real pretrained vision-model candidates based on license, stem compatibility, on-device speed, correctness testability, and value for PlaneFuse Live. Prefer MobileCLIP for semantic-camera impact only if it is actually a good technical/licensing fit; do not force it.

Choose one model and record the decision. Integrate the same model for Pipeline B and C, create a fixed validation corpus, verify task/output agreement, and measure frontend plus end-to-end performance.

Do not build the polished demo yet. This milestone is a real-model proof.

Use Sol Advisor only if integration requires a major architecture commitment or becomes genuinely difficult. Commit stable units conventionally and stop at the M5 gate.
```

## Prompt 7 - M6 novel source-grid optimization

```text
Execute M6 as a bounded research/optimization milestone.

The goal is to test whether we can improve beyond straightforward fusion by exploiting actual NV12/4:2:0 source geometry: phase-aware chroma sampling, interpolation folding, transformed projection coefficients, source-grid-specific layouts, or other evidence-backed approaches.

Start from profiler evidence. Run at most three experiments before plateau review. Preserve the exact supported image semantics and task quality. Do not introduce a quality tradeoff unless it is explicitly approved and separately reported.

Accept only confirmed wins. Commit accepted improvements conventionally. Record failures in EXPERIMENTS.md. Stop at the M6 gate.
```

## Prompt 8 - M7/M8 reusability and CLI

```text
Complete M7, then M8, without expanding the optimization scope.

Turn the proven technique into reusable developer tooling. Generalize only enough to support at least a second compatible configuration/stem if practical. Implement a clean inspect/compile/verify/bench workflow with clear unsupported-case errors and reproducible sample commands.

This is conventional software-engineering work: use targeted tests, keep interfaces simple, avoid speculative framework abstraction, and make multiple meaningful Conventional Commits as coherent features land.

Stop when another developer could follow README instructions to reproduce a supported optimization and verify its output.
```

## Prompt 9 - M9 PlaneFuse Live

```text
Execute M9 only.

Build PlaneFuse Live as a compelling local Mobile-AI demonstration of the already-proven optimization. The demo must perform a useful real vision task fully on-device. Prefer semantic camera/zero-shot recognition if supported by the chosen model; otherwise use the most meaningful real-time task the model honestly supports.

The interface should make Pipeline B vs C understandable immediately and show only real runtime measurements or clearly labeled stored benchmark results. Include output agreement and a truthful indication that the C path has no full RGB intermediate.

Do not change benchmark methodology to improve the demo. Do not add cloud inference. Keep visual polish focused on the three-minute judging video.

Use XcodeBuildMCP for build/run/inspection workflows as appropriate. Commit stable UI/demo units conventionally.
```

## Prompt 10 - M10 hostile technical audit

```text
Use $sol-advisor:orchestration for a final hostile technical audit. The advisor should act like a skeptical Arm/Apple performance engineer attempting to disprove the submission.

Audit:
- fairness of Pipeline B vs C;
- correctness/parity evidence;
- benchmark methodology and statistical stability;
- whether the optimization is genuinely Arm/Apple-Silicon relevant;
- whether any claimed memory/bandwidth/power result is inferred rather than measured;
- whether novelty language overstates prior art;
- whether a judge can reproduce the result;
- whether the live demo accurately reflects the measured implementation.

Return blocking, major, and minor findings. The parent should fix blocking/major findings with targeted validation and Conventional Commits. Do not alter historical raw benchmark files.
```

## Prompt 11 - Final hackathon rubric audit

```text
Use $sol-advisor:orchestration for one final rubric audit after technical findings are resolved.

Evaluate PlaneFuse against the published Arm challenge criteria:
- Technological Implementation /40
- User/Developer Experience /15
- Potential Impact /20
- WOW /25

Be conservative. Give evidence for every score, identify the single highest-leverage remaining improvement, and flag any mandatory submission requirement that is missing.

Then have the parent update HACKATHON_SCORECARD.md, CLAIMS.md, README/submission materials only where evidence supports the change. Do not invent improvements or scores.
```
