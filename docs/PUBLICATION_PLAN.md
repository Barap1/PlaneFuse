# Public-release plan

The current worktree is sanitized, but existing private history previously
contained profiler metadata. No history rewrite, force-push, visibility change,
or external publication has been performed.

## Option A — sanitize the existing private history

Benefits: preserves the meaningful R0–R9 engineering narrative, review links,
and commit-level provenance while removing known private profiler metadata.

Risks: rewriting changes every descendant commit ID, can miss an unexpected
historical blob, and requires coordinated replacement of the remote default
branch. Keep the current private remote as a backup.

Human-controlled actions:

1. Make a protected backup of the private repository and record its refs.
2. Build a reviewed allowlist from the final tree; remove profiler nicknames,
   UUIDs, PIDs, process inventories, and other machine identifiers from every
   historical blob.
3. Run the privacy checker against every rewritten ref, inspect the diff, and
   create a sanitized release branch/tag.
4. Only after review, replace the public/default branch through the hosting
   provider's normal flow.

Example tooling is intentionally left as a reviewed human operation:

```bash
git clone --mirror <private-repository-url> planefuse-private.git
cd planefuse-private.git
# Run the chosen reviewed git-filter-repo/filter-branch rewrite here.
git fsck --full
# Verify every rewritten ref and export the final tree before any force-push.
```

Verify current-tree privacy and scan historical blobs for `/Users/`, UUID and
serial patterns, PIDs, private emails, secrets, and the known profiler metadata.
Then verify a fresh clone of the rewritten public `main`.

## Option B — publish a clean sanitized release history

Benefits: simplest privacy boundary and lowest risk of exposing old profiler
metadata; the public repository contains only the final verified tree and a
short release history.

Risks: loses the original public commit narrative; preserve the private
repository separately as research provenance.

Human-controlled actions:

1. Keep the current private repository unchanged as the archive.
2. Export the final verified tree, excluding ignored assets, user files, and
   untracked profiler traces.
3. Initialize a private staging repository, commit the sanitized tree with a
   small Conventional Commit history, and run every release check from a fresh
   clone.
4. Rename its default branch to `main`, verify from an incognito/fresh clone,
   then change visibility only after approval.

Example staging commands:

```bash
git archive --format=tar --prefix=PlaneFuse/ HEAD | tar -xf - -C /path/to/staging
cd /path/to/staging/PlaneFuse
git init -b main
git add . && git commit -m "chore(release): publish sanitized PlaneFuse tree"
```

Verify the staging repository with `./scripts/release_validate.sh`, the privacy
checker, `git ls-files`, and an independent fresh clone. Do not copy `.git`,
`.build`, `.pf-cache`, `.venv`, `models`, logs, user files, or profiler traces.

## Recommendation

Option B is safest if preserving public commit history is not a judging
requirement. Option A is reasonable only if a human wants the full research
narrative and will review every rewritten historical blob. Either option should
make the final sanitized tree the public default `main`; this checkout must not
perform that external action.
