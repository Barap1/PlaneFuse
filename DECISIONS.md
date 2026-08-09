# PlaneFuse architectural decisions

Record only durable decisions that future Codex sessions should not repeatedly reconsider.

## D001 - Start on native macOS Apple Silicon

Status: accepted

Decision: Early mathematical, Metal, and benchmark work runs directly on the Apple-Silicon Mac. Do not begin with an iOS Simulator target.

Why: Real performance measurement should use the actual Arm hardware without simulator timing ambiguity, signing friction, or mobile UI work before the optimization is proven.

Revisit when: M8/M9 if an iOS version would materially strengthen the final demonstration and time permits.

## D002 - Fair benchmark requires optimized RGB baseline

Status: accepted

Decision: The core performance claim must compare PlaneFuse Pipeline C against optimized RGB Pipeline B, not only against a naive/ordinary Pipeline A.

Why: This avoids a strawman result and is central to technical credibility.

## D003 - No custom PlaneFuse Codex skill at bootstrap

Status: accepted

Decision: Use root AGENTS.md + repository documents + XcodeBuildMCP + Sol Advisor initially. Do not create a custom PlaneFuse skill during M0.

Why: The recurring optimization workflow is not yet proven. Encoding speculative behavior in another always-discoverable instruction surface would add context and maintenance overhead.

Revisit when: after M3/M4 if a stable reusable experiment/evidence workflow has emerged.

## D004 - Local commits are autonomous; remote publishing is not

Status: accepted

Decision: Codex may make local Conventional Commits without asking. It must ask before pushing or publishing.

Why: Frequent local commits improve rollback and experiment traceability while keeping external actions under human control.

## D005 - SwiftPM macOS package is the M0 foundation

Status: accepted

Decision: Start with a native macOS Swift Package Manager library plus executable CLI, keeping the early reference math and benchmark harness independent of an app target.

Why: It gives deterministic build/test/CLI behavior on real Apple Silicon and avoids simulator, signing, and UI complexity before the optimization is proven. A macOS app target can be added at M9 without changing the core library boundary.

Evidence: M0 gate passed with `./pf build`, `./pf test quick`, `./pf doctor`, `./pf verify`, and `./pf bench quick`.

Revisit when: M9 if the live camera shell requires an Xcode app target.

---

New decision template:

## Dxxx - Title

Status: proposed / accepted / superseded

Decision:

Why:

Evidence:

Revisit when:
