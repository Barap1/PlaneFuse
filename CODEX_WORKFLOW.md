# Codex workflow for PlaneFuse

This document explains how to use Codex in practice without wasting the user's Plus allowance or giving the agent uncontrolled project autonomy.

## 1. How Codex should receive project context

Codex supports repository instruction files such as `AGENTS.md`. Keep stable operating rules there because Codex can discover them automatically from the project tree.

Do not stuff every architectural detail into `AGENTS.md`. Large instruction files consume context and can become harder to maintain. This repository separates:

- behavior/rules -> `AGENTS.md`;
- product/technical target -> `SPEC.md`;
- current work -> `STATUS.md` + `MILESTONES.md`;
- measurement truth -> `BENCHMARK_CONTRACT.md`;
- experimental history -> `EXPERIMENTS.md`;
- durable choices -> `DECISIONS.md`.

A fresh session should not reread every historical log. The current prompt plus root instructions should direct Codex to only the relevant source-of-truth files.

## 2. The parent-session role

The main Codex session is the engineering lead.

It owns:

- interpreting the current milestone;
- decomposing the local task;
- deciding which files to inspect;
- implementing routine changes;
- selecting targeted tests;
- checking actual diffs/results;
- making local Conventional Commits;
- updating compact project state;
- deciding when a Sol Advisor gate is required.

The parent does not automatically get to change the project thesis or lower correctness gates.

## 3. Sol Advisor's role

Sol Advisor is a structured review/orchestration layer for expensive decisions.

Use it for:

- M1 mathematical design review;
- M3 first native-plane architecture/implementation review;
- M4 plateau/kill-gate review if needed;
- M5/M6 major runtime/model integration when technically risky;
- final hostile technical-judge audit;
- final rubric audit.

Do not use it for:

- formatting;
- renames;
- trivial compiler errors;
- small unit tests;
- ordinary README edits;
- every performance experiment.

The parent must inspect the actual working tree and verification evidence before accepting a worker/advisor claim.

## 4. XcodeBuildMCP's role

XcodeBuildMCP gives Codex structured Apple-development operations. Structured outputs are preferable to repeatedly feeding raw Xcode logs into model context.

Initially enabled workflows are intentionally lean:

- doctor;
- project-discovery;
- session-management;
- swift-package;
- macos.

Only enable more when needed:

- debugging -> difficult LLDB investigation;
- xcode-ide -> if Xcode 26.3+ bridge functionality materially helps;
- simulator/device/ui-automation -> later iOS or UI demo work.

For deterministic benchmark scripts, raw command-line Apple tooling can still be appropriate.

## 5. Session strategy

Use one Codex session for a coherent milestone or sub-milestone until context becomes noisy.

Start a fresh session when:

- a milestone finishes;
- an architecture review should be independent;
- the session has accumulated large logs/repeated failed approaches;
- moving from research to productization;
- beginning final judge review.

Do not start a new session after every small build failure because that forces repeated repo orientation.

At the beginning of a fresh milestone session, use the relevant prompt from `PROMPTS.md`.

## 6. Model routing

The exact models available in Codex can change. Always use the exact IDs shown by the user's current Codex model picker or `/model` command when configuring agents.

Cost-conscious policy:

### Normal parent engineering

Use a strong cost-balanced model, normally Terra with medium reasoning when available.

Tasks:

- normal Swift implementation;
- harness work;
- targeted debugging;
- documentation;
- integration where the architecture is already known.

### Difficult implementation

Escalate to Terra/high when:

- a Metal kernel is behaving unexpectedly;
- numerical correctness is difficult;
- concurrency/lifetime issues appear;
- model graph/runtime integration is complex;
- a normal pass failed for a reason that requires deeper reasoning.

### Sol/high

Reserve for:

- architecture commitments;
- novel mathematical review;
- unexplained performance plateau;
- hostile final audit;
- final scoring/positioning audit.

The expensive model should receive a narrow evidence packet, not the entire noisy chat history.

## 7. What a good task request looks like

Bad:

```text
Build PlaneFuse and make it fast.
```

Good:

```text
Execute M2 only. Build a fair optimized RGB Metal baseline using the current supported NV12 semantics. Do not implement PlaneFuse C yet. Produce correctness tests, a compact quick benchmark, and commit each stable coherent unit using Conventional Commits. Stop when the M2 gate in MILESTONES.md passes or when evidence shows the gate cannot be met.
```

A bounded goal gives Codex freedom inside a meaningful box.

## 8. Iteration loop

Once the `./pf` harness exists, ordinary performance work should look like:

```text
1. Read current best metrics.
2. Inspect profiler/benchmark evidence.
3. State one hypothesis.
4. Implement the smallest change.
5. Run targeted parity test.
6. Run ./pf bench quick.
7. If candidate is clearly better, run confirmation.
8. Accept and commit, or reject/restore.
9. Append a compact EXPERIMENTS.md entry.
10. Stop after 3 non-improving credible experiments.
```

The model should not debate measurements in prose when scripts can compare them deterministically.

## 9. Token-saving rules

- Prefer machine-readable benchmark JSON over pasted tables/logs.
- Store verbose Xcode output under `artifacts/logs/`.
- Print only failure summaries to chat.
- Do not ask Sol to reread the entire repository for each review; provide current milestone, relevant diff, metrics, and failure evidence.
- Do not run every test after every edit.
- Do not reread Devpost rules repeatedly; `HACKATHON_SCORECARD.md` contains the stable requirements and `REFERENCES.md` records the source.
- Do not create agent swarms for independent work that is actually sequential.
- Do not add a general orchestration framework unless a concrete bottleneck appears.

## 10. Git as durable memory

Codex should commit frequently enough that:

- every milestone can be bisected;
- a performance regression can be traced;
- accepted experiments have stable commits;
- the final history shows genuine engineering progress.

At least 20 meaningful Conventional Commits are required by our internal release gate; target 24-30.

Git is not a substitute for benchmark state. Performance truth belongs in benchmark artifacts tied to commit hashes.

## 11. How Codex should report to the user

Routine report:

```text
Changed: <one short sentence>
Validated: <targeted checks>
Commit: <hash> <conventional message>
Result: <key metric only if relevant>
Next: <one action>
```

Milestone report:

```text
Milestone: Mx PASS/FAIL
Best verified result: ...
Parity/quality: ...
Strongest evidence: ...
Failed approaches worth remembering: ...
Commits added: ...
Next gate: ...
Human decision required: yes/no
```

Avoid long play-by-play narration unless the user asks.

## 12. Environment changes

Codex may create project-local dependencies on its own.

For new system-level software, Codex should:

1. explain why existing tools cannot do the job;
2. name the package and install source;
3. wait for approval;
4. record the approved dependency in `DECISIONS.md` or setup docs.

This keeps the project autonomous without letting an agent silently alter the Mac.

## 13. When to create a custom PlaneFuse skill

Do not create one during M0 just because skills exist.

After M3/M4, if a stable recurring workflow has emerged, a small project skill may be valuable. Examples:

- standardized performance-experiment loop;
- benchmark-evidence packaging;
- final claim validation.

A skill should encode a proven workflow, not speculative architecture.
