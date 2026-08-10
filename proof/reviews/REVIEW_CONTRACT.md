# PlaneFuse independent review contract

This contract governs major read-only Sol Advisor reviews for milestone,
architecture, benchmark-method, hostile technical, and final rubric gates.
It is a findings contract, not a request for private reasoning. Reviewers must
persist conclusions and actionable evidence only.

## Required verdict

Every review begins with exactly one line:

```text
VERDICT: SHIP
```

The allowed values are `SHIP`, `FIX-FIRST`, and `RETHINK`.

- `SHIP` means no unresolved material finding blocks the requested gate.
- `FIX-FIRST` means the current work can proceed only after the listed valid
  findings are fixed and re-reviewed.
- `RETHINK` means the settled architecture, benchmark design, or claim strategy
  is not defensible without a materially different approach or human decision.

`FIX-FIRST` and `RETHINK` are invalid without at least one actionable finding.

## Required review metadata

Persist these fields in the review artifact:

```text
Review ID:
Review type:
Reviewer role: sol_advisor_advisor
Repository:
Head commit reviewed:
Comparison/base commit:
Date UTC:
Scope files:
```

The reviewer must inspect the actual current worktree and relevant raw evidence,
not only milestone prose.

## Required finding schema

Every finding uses this complete record:

```text
Finding ID: F-###
Severity: critical | high | medium | low
Category: correctness | fairness | reproducibility | claim | safety | scope
Evidence: exact file path plus line, JSON field, command, or code symbol
Risk: why this threatens correctness, fairness, reproducibility, or the claim
Required fix: concrete change needed before the gate can pass
Closure evidence: exact test, artifact, review, or command that proves closure
```

Do not report a vague concern without an evidence location, a concrete fix, and
a closure test. If no findings exist, write `Findings: none` after the verdict.

## Parent response and acceptance

The parent agent owns acceptance. For every `FIX-FIRST` or `RETHINK` finding,
the parent must persist a response containing:

```text
Finding ID:
Disposition: valid | invalid-with-evidence | deferred-with-approval
Parent verification:
Change/evidence:
Targeted validation:
Re-review requested:
```

The parent must not mark the milestone accepted from a worker/advisor claim
alone. A re-review must return `VERDICT: SHIP`, or the repository remains at the
hard stop. Advisor/tool failure is recorded as a separate blocked-review
artifact and is never converted into `SHIP`.

## Persistence

Use one immutable Markdown artifact per invocation:

```text
proof/reviews/<review-id>.md
```

Review-response artifacts reference the finding IDs they close. Do not overwrite
an earlier review; preserve the sequence of verdicts and responses.
