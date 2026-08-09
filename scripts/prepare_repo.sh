#!/bin/bash
set -euo pipefail

EXPECTED="$HOME/Documents/Projects/PlaneFuse"
CURRENT="$(pwd -P)"

if [ "$CURRENT" != "$EXPECTED" ]; then
  echo "ERROR: Run this script from: $EXPECTED"
  echo "Current directory: $CURRENT"
  exit 1
fi

mkdir -p artifacts/logs benchmarks/results proof docs
: > artifacts/logs/.gitkeep
chmod +x scripts/*.sh

echo "Repository path: $CURRENT"
echo "Architecture: $(uname -m)"

if [ "$(uname -m)" != "arm64" ]; then
  echo "ERROR: PlaneFuse must be developed/benchmarked on Apple Silicon (arm64)."
  exit 1
fi

if [ ! -d .git ]; then
  git init
  git branch -M main
  echo "Initialized local Git repository."
else
  echo "Git repository already initialized."
fi

if git rev-parse --verify HEAD >/dev/null 2>&1; then
  echo "Existing commits detected; no bootstrap commit created."
else
  if git config user.name >/dev/null 2>&1 && git config user.email >/dev/null 2>&1; then
    git add .
    git commit -m "chore(repo): initialize PlaneFuse project"
    echo "Created initial Conventional Commit."
  else
    echo "Git identity is not configured. Configure your normal Git user.name/user.email and rerun this script to create the first commit."
  fi
fi

echo
echo "Preparation complete. Next run: ./scripts/preflight.sh"
