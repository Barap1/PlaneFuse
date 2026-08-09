#!/bin/bash
set -euo pipefail

required=(
  AGENTS.md
  SPEC.md
  CODEX_WORKFLOW.md
  MILESTONES.md
  BENCHMARK_CONTRACT.md
  EXPERIMENT_PROTOCOL.md
  GIT_POLICY.md
  STATUS.md
  DECISIONS.md
  EXPERIMENTS.md
  CLAIMS.md
  HACKATHON_SCORECARD.md
  DEMO_PLAN.md
  PROMPTS.md
  REFERENCES.md
  SUBMISSION_CHECKLIST.md
)

missing=0
for f in "${required[@]}"; do
  if [ ! -s "$f" ]; then
    echo "MISSING/EMPTY: $f"
    missing=$((missing+1))
  fi
done

if [ "$missing" -gt 0 ]; then
  echo "FAIL: $missing required project document(s) missing or empty."
  exit 1
fi

echo "PASS: required project documents are present."
