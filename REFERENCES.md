# External references and source-of-truth links

Last refreshed: 2026-08-09.

These links are recorded so Codex does not repeatedly rediscover basic project constraints.

## Arm hackathon

Overview:
https://arm-ai-optimization-challenge.devpost.com/

Track details:
https://arm-ai-optimization-challenge.devpost.com/details/trackdetails

Rules:
https://arm-ai-optimization-challenge.devpost.com/rules

Updates / optimization guidance:
https://arm-ai-optimization-challenge.devpost.com/updates

Stable takeaways used by this repository:

- Mobile AI includes fully local inference on Arm client devices including laptops.
- Mobile constraints include responsiveness, memory, battery awareness, and offline use.
- Camera intelligence is explicitly listed as a Mobile AI workload.
- Clear optimization work and measurable improvements are central.
- Judging: Technical 40, UX/DX 15, Potential Impact 20, WOW 25.
- Public MIT or Apache-2.0 repository is required for submission.
- Demo video should be under 3 minutes; judges do not have to run the project.

## OpenAI Codex

OpenAI developers homepage / Codex use cases:
https://developers.openai.com/
https://developers.openai.com/codex/use-cases

OpenAI Codex repository AGENTS guidance:
https://github.com/openai/codex/blob/main/docs/agents_md.md
https://github.com/openai/codex/blob/main/AGENTS.md

Model guidance:
https://developers.openai.com/api/docs/guides/latest-model

Stable takeaways used here:

- repository AGENTS.md is the durable instruction surface;
- Codex is suitable for long-running engineering and scored improvement loops;
- keep project state in files rather than relying on chat memory;
- exact available model IDs/settings should be taken from the current Codex client, not hard-coded forever.

## XcodeBuildMCP

Installation:
https://www.xcodebuildmcp.com/docs/installation

MCP clients / Codex:
https://www.xcodebuildmcp.com/docs/clients

Configuration:
https://www.xcodebuildmcp.com/docs/configuration

Workflows:
https://www.xcodebuildmcp.com/docs/workflows

Stable takeaways used here:

- Homebrew install is supported/recommended and avoids Node solely for the MCP;
- Codex CLI can register XcodeBuildMCP as an MCP server;
- project config lives at `.xcodebuildmcp/config.yaml`;
- advertised workflows consume agent context, so enable only what is needed.

## Sol Advisor

Repository:
https://github.com/DannyMac180/sol-advisor

Stable takeaways used here:

- parent chat retains architecture/verification/acceptance ownership;
- implementer/advisor roles use exact model IDs selected during setup;
- setup previews project adapter files before installation;
- advisor can be requested read-only, subject to client enforcement;
- use project scope for PlaneFuse;
- plugin installation and adapter setup are separate steps.

## Apple technical documentation

Codex should prefer primary Apple documentation when implementing color conversion, Core Video, Metal, Core ML, or model runtime details. Do not copy color matrices or pixel-range constants from random blog posts when Apple/standards documentation is available.
