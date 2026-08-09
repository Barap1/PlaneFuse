#!/bin/bash
set -u

fail=0
warn=0

pass() { printf 'PASS  %s\n' "$1"; }
warning() { printf 'WARN  %s\n' "$1"; warn=$((warn+1)); }
failure() { printf 'FAIL  %s\n' "$1"; fail=$((fail+1)); }

check_cmd() {
  name="$1"
  if command -v "$name" >/dev/null 2>&1; then
    pass "$name: $(command -v "$name")"
  else
    failure "$name not found"
  fi
}

echo "PlaneFuse preflight"
echo "Project: $(pwd -P)"
echo

if [ "$(uname -s)" = "Darwin" ]; then pass "macOS detected"; else failure "macOS required"; fi
if [ "$(uname -m)" = "arm64" ]; then pass "Apple Silicon arm64 detected"; else failure "arm64 Apple Silicon required"; fi

check_cmd git
check_cmd swift
check_cmd xcodebuild
check_cmd xcrun
check_cmd codex

if command -v brew >/dev/null 2>&1; then pass "Homebrew available"; else warning "Homebrew not found; another intentional install path may be used"; fi
if command -v bun >/dev/null 2>&1; then pass "Bun $(bun --version 2>/dev/null)"; else warning "Bun missing; required for Sol Advisor"; fi
if command -v xcodebuildmcp >/dev/null 2>&1; then pass "XcodeBuildMCP available"; else warning "XcodeBuildMCP missing"; fi

if command -v xcodebuild >/dev/null 2>&1; then
  version="$(xcodebuild -version 2>/dev/null | tr '\n' ' ' || true)"
  [ -n "$version" ] && pass "$version"
fi

if command -v codex >/dev/null 2>&1; then
  codex_version="$(codex --version 2>/dev/null | head -n 1 || true)"
  [ -n "$codex_version" ] && pass "$codex_version"
  if codex plugin --help >/dev/null 2>&1; then pass "Codex plugin command available"; else warning "Codex plugin command unavailable; Sol Advisor install path may require Codex update"; fi
  if codex mcp --help >/dev/null 2>&1; then pass "Codex MCP command available"; else failure "Codex MCP command unavailable"; fi
fi

if [ -f .xcodebuildmcp/config.yaml ]; then pass ".xcodebuildmcp/config.yaml present"; else failure "missing .xcodebuildmcp/config.yaml"; fi
if [ -f AGENTS.md ]; then pass "AGENTS.md present"; else failure "missing AGENTS.md"; fi
if [ -f SPEC.md ]; then pass "SPEC.md present"; else failure "missing SPEC.md"; fi

if [ -d .git ]; then
  count="$(git rev-list --count HEAD 2>/dev/null || echo 0)"
  pass "Git repository present ($count commits)"
else
  failure "Git repository not initialized"
fi

echo
if [ "$fail" -gt 0 ]; then
  echo "RESULT: FAIL ($fail blocking issue(s), $warn warning(s))"
  exit 1
fi

echo "RESULT: PASS WITH $warn WARNING(S)"
exit 0
