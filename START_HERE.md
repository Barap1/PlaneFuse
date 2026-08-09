# PlaneFuse Codex Starter - Start Here

This repository is designed to be opened directly by Codex from:

`~/Documents/Projects/PlaneFuse`

The goal is to minimize manual project management. You should make a small number of setup decisions once, then let Codex work milestone by milestone with strict technical and safety gates.

## What you will personally do

Your manual responsibilities are intentionally small:

1. Put this folder at `~/Documents/Projects/PlaneFuse`.
2. Run the included preparation and preflight scripts.
3. Install or verify the small external toolchain listed below.
4. Configure Sol Advisor once using the exact model IDs shown by your Codex installation.
5. Start Codex in the PlaneFuse folder and paste the first prompt from `PROMPTS.md`.
6. Approve only major architecture pivots, public pushes, or system-level changes.
7. At milestone gates, read the short summary Codex gives you and tell it to continue or stop.

Everything else should be handled by Codex inside the repository.

---

# 1. Put the project in the correct folder

Create the parent folder if needed:

```bash
mkdir -p "$HOME/Documents/Projects"
```

The final project path must be:

```text
~/Documents/Projects/PlaneFuse
```

If you downloaded a ZIP containing a top-level `PlaneFuse` folder, move or extract that folder into `~/Documents/Projects/`.

Then open Terminal and run:

```bash
cd "$HOME/Documents/Projects/PlaneFuse"
pwd
```

The final line should end with:

```text
/Documents/Projects/PlaneFuse
```

---

# 2. Run the repository preparation script

From the project root:

```bash
chmod +x scripts/*.sh
./scripts/prepare_repo.sh
```

This script is intentionally conservative. It may:

- create missing project-local folders;
- initialize a local Git repository if none exists;
- rename the current branch to `main` when safe;
- make project scripts executable;
- create the first local Conventional Commit when Git identity is already configured.

It does not install system packages, push anything, change global Git settings, or modify files outside the PlaneFuse repository.

If Git asks for your identity, configure it yourself using your normal name/email and rerun the script.

---

# 3. Run the preflight check

```bash
./scripts/preflight.sh
```

The important requirements are:

- Apple Silicon (`arm64`);
- macOS;
- Xcode and command-line tools;
- Swift;
- Git;
- Codex;
- Homebrew or another intentional way to install XcodeBuildMCP;
- Bun for Sol Advisor;
- XcodeBuildMCP after installation.

Do not panic if XcodeBuildMCP or Bun is initially missing. Install them in the next steps.

---

# 4. Verify Xcode

Run:

```bash
xcodebuild -version
xcode-select -p
swift --version
```

If Xcode needs to finish installing components or accept a license, complete that once before using Codex.

PlaneFuse begins as a native macOS/Apple-Silicon project. We intentionally do not start with an iOS app because early performance research must run directly on real Apple Silicon without simulator timing noise or signing friction. A camera-facing demo can be added after the optimization works.

---

# 5. Install XcodeBuildMCP

Recommended Homebrew install:

```bash
brew tap getsentry/xcodebuildmcp
brew install xcodebuildmcp
```

Verify:

```bash
xcodebuildmcp --help
xcodebuildmcp-doctor
```

Register it with Codex:

```bash
codex mcp add XcodeBuildMCP -- xcodebuildmcp mcp
```

Install XcodeBuildMCP's optional Codex CLI skill so Codex knows the tool conventions without rediscovering flags:

```bash
xcodebuildmcp init --client codex
```

You do not need to run the interactive `xcodebuildmcp setup` wizard because this starter already includes a project-local `.xcodebuildmcp/config.yaml`. Use `xcodebuildmcp setup` later only if you intentionally want to regenerate/change that project configuration.

The repository already contains `.xcodebuildmcp/config.yaml`. Initially it exposes only the macOS, Swift-package, project-discovery, session-management, and doctor workflows. This keeps the MCP tool list useful but small. Do not enable simulator, device, debugging, UI automation, or Xcode IDE bridge workflows until a milestone actually requires them.

---

# 6. Install Bun if needed

Check first:

```bash
bun --version
```

If Bun is not installed, use Bun's official installer or your existing package-management preference. After installation, restart Terminal and verify `bun --version` again.

Sol Advisor currently uses Bun as its runtime dependency.

---

# 7. Install Sol Advisor

Verify your Codex installation supports plugins:

```bash
codex plugin --help
```

Then install Sol Advisor using its published marketplace flow:

```bash
codex plugin marketplace add DannyMac180/sol-advisor --ref main
codex plugin add sol-advisor@sol-advisor
```

Start a new Codex chat after installation.

---

# 8. Configure Sol Advisor once

Open Codex in this exact project folder:

```bash
cd "$HOME/Documents/Projects/PlaneFuse"
codex
```

Or open the same folder in the Codex desktop app.

Use this setup request:

```text
Use $sol-advisor:setup to configure Sol Advisor for this PlaneFuse repository.
Use Codex as the client and project scope.
The workspace is ~/Documents/Projects/PlaneFuse.
Ask one question at a time and stop after showing the complete adapter preview so I can inspect it before installation.
```

When Sol Advisor asks for model IDs, use Codex's current model picker or `/model` command and paste the exact IDs it shows. Do not guess model identifiers from this document.

Recommended cost-conscious role policy:

- Parent/orchestrator session: Terra, medium reasoning for ordinary milestone management.
- Routine implementer: Terra, medium if Sol Advisor supports that exact setting in your client; otherwise use the closest available Terra setting.
- High-complexity implementer: Terra, high.
- Advisor: Sol, high, requested read-only.
- Fail closed: yes. No silent fallback.
- Optional Luna app-task lane: leave disabled initially.

Sol should be used only at high-leverage review gates, not for routine file edits.

Inspect the adapter preview before accepting it. If the destinations are project-scoped and correct, enter the exact `INSTALL <token>` text Sol Advisor requests. Then restart/reload Codex so the roles are discovered.

---

# 9. Verify the complete environment

Back in Terminal:

```bash
cd "$HOME/Documents/Projects/PlaneFuse"
./scripts/preflight.sh
```

Then in Codex ask:

```text
Read the root AGENTS.md and report only: project path, current milestone, whether XcodeBuildMCP is visible, whether Sol Advisor is configured, and any blocking setup issue. Do not modify files and do not invoke an advisor.
```

If it reports no blocking issue, setup is complete.

---

# 10. Start the project

Open `PROMPTS.md` and paste `Prompt 0 - Bootstrap M0` into a fresh Codex session opened at the project root.

Do not simply say "build PlaneFuse." The project is intentionally broken into gates so Codex can work independently without wandering.

The expected rhythm is:

```text
milestone goal
  -> Codex implements a bounded change
  -> targeted correctness check
  -> targeted benchmark when relevant
  -> Conventional Commit
  -> update STATUS.md / EXPERIMENTS.md
  -> continue within the same milestone
  -> major gate -> Sol Advisor review
  -> human sees a short summary
```

---

# 11. How much attention should you give Codex?

Very little during routine work.

You should normally intervene only if Codex asks for one of these:

- permission to install or modify system-wide software;
- permission to push/publish code;
- a project architecture pivot;
- a model/license choice that materially changes the submission;
- access to a physical device/account/credential;
- a decision after a failed kill gate;
- final submission wording or video approval.

Codex is explicitly authorized by `AGENTS.md` to make normal local edits, build, test, benchmark, create project-local dependencies, and make local Git commits without asking you every time.

---

# 12. Git expectations

PlaneFuse must finish with at least 20 meaningful Conventional Commits. The target is 24-30 meaningful commits, not fake checkpoint commits.

Run anytime:

```bash
./scripts/check_git_history.sh
```

Before release:

```bash
./scripts/check_git_history.sh --release
```

See `GIT_POLICY.md` for the exact rules and a suggested commit map.

---

# 13. The product we are trying to create

PlaneFuse is not merely a benchmark.

The technical product is a reusable compiler/runtime technique that lets compatible pretrained RGB vision models consume native NV12/YUV camera planes without materializing a full RGB intermediate.

The showcase product is `PlaneFuse Live`: a fully local semantic-camera demo on Apple Silicon that lets a user point the camera at the world and perform local visual recognition/search while showing live, honest A/B performance evidence:

- optimized RGB pipeline;
- PlaneFuse native-plane pipeline;
- p50/p95 latency;
- memory/bandwidth evidence where measurable;
- output agreement;
- RGB intermediate allocations;
- sustained FPS;
- all inference on-device.

The demo exists to make the systems optimization understandable. The compiler/runtime is the reusable engineering contribution.

---

# 14. What to read if something is unclear

- `AGENTS.md` - rules Codex must follow automatically.
- `SPEC.md` - what PlaneFuse is and why it matters.
- `CODEX_WORKFLOW.md` - how Codex, Sol Advisor, XcodeBuildMCP, sessions, and model routing should work.
- `MILESTONES.md` - ordered project gates.
- `BENCHMARK_CONTRACT.md` - what counts as a legitimate result.
- `EXPERIMENT_PROTOCOL.md` - how optimization loops work.
- `GIT_POLICY.md` - commit/branch rules.
- `PROMPTS.md` - exact requests to paste into Codex.
- `HACKATHON_SCORECARD.md` - how the project maps to the Arm rubric.
- `DEMO_PLAN.md` - what the final experience should look like.
- `CLAIMS.md` - claims that are allowed in the final submission and the evidence behind them.
