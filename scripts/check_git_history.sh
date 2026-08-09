#!/bin/bash
set -euo pipefail

release=0
if [ "${1:-}" = "--release" ]; then release=1; fi

if [ ! -d .git ]; then
  echo "FAIL: not a Git repository"
  exit 1
fi

count="$(git rev-list --count HEAD 2>/dev/null || echo 0)"
echo "Commit count: $count"

bad=0
while IFS= read -r subject; do
  [ -z "$subject" ] && continue
  if ! printf '%s\n' "$subject" | grep -Eq '^(feat|fix|perf|test|bench|docs|refactor|chore|build|ci)(\([a-z0-9._-]+\))?!?: .+'; then
    echo "Non-conventional subject: $subject"
    bad=$((bad+1))
  fi
done < <(git log --format='%s')

if [ "$bad" -gt 0 ]; then
  echo "FAIL: $bad commit subject(s) do not match the project Conventional Commit policy."
  exit 1
fi

echo "PASS: all commit subjects match project Conventional Commit format."

if [ "$release" -eq 1 ] && [ "$count" -lt 20 ]; then
  echo "FAIL: release gate requires at least 20 meaningful commits."
  exit 1
fi

if [ "$count" -lt 20 ]; then
  echo "INFO: release target not reached yet (minimum 20 meaningful commits)."
else
  echo "PASS: commit-count release threshold reached."
fi
