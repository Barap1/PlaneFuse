# PlaneFuse 10-minute quick start

Read `START_HERE.md` if any command fails. This page is only the shortest successful path.

## 1. Place the folder

Final path:

```text
~/Documents/Projects/PlaneFuse
```

Then:

```bash
cd "$HOME/Documents/Projects/PlaneFuse"
chmod +x scripts/*.sh
./scripts/prepare_repo.sh
./scripts/preflight.sh
```

## 2. Verify/install the two external helpers

XcodeBuildMCP:

```bash
brew tap getsentry/xcodebuildmcp
brew install xcodebuildmcp
codex mcp add XcodeBuildMCP -- xcodebuildmcp mcp
xcodebuildmcp init --client codex
```

Bun (needed by Sol Advisor):

```bash
bun --version
```

If missing, install Bun from its official installer, restart Terminal, and verify it.

Sol Advisor:

```bash
codex plugin marketplace add DannyMac180/sol-advisor --ref main
codex plugin add sol-advisor@sol-advisor
```

## 3. Configure Sol Advisor in a new Codex chat

Open Codex at the project root and paste:

```text
Use $sol-advisor:setup to configure Sol Advisor for this PlaneFuse repository.
Use Codex as the client and project scope.
The workspace is ~/Documents/Projects/PlaneFuse.
Ask one question at a time and stop after showing the complete adapter preview so I can inspect it before installation.
```

Copy exact model IDs from your current Codex `/model` picker.

Suggested policy:

- parent: Terra / medium;
- routine implementer: Terra / medium if supported;
- high-complexity implementer: Terra / high;
- advisor: Sol / high, read-only requested;
- fail closed;
- Luna app-task lane disabled initially.

Inspect the preview, then enter the exact `INSTALL <token>` Sol Advisor requests. Restart Codex.

## 4. Final environment check

```bash
cd "$HOME/Documents/Projects/PlaneFuse"
./scripts/preflight.sh
```

## 5. Start building

Open a fresh Codex session in the PlaneFuse folder, use a cost-balanced parent model (normally Terra/medium), then paste `Prompt 0 - Bootstrap M0` from `PROMPTS.md`.

After that, Codex should work milestone-by-milestone. You should normally only be asked for major pivots, public pushes, system-wide installs, credentials, or final release decisions.
