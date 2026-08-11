#!/usr/bin/env python3
"""Fail closed if profiler-only timing leaks into production B2/C1 methods."""

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def method(source: str, signature: str, next_signature: str) -> str:
    start = source.index(signature)
    end = source.index(next_signature, start)
    return source[start:end]


def fail(message: str) -> None:
    raise SystemExit(f"FAIL R7 production instrumentation: {message}")


def main() -> int:
    rgb = (ROOT / "Sources/PlaneFuseCore/MetalMobileNetV2RGBPipeline.swift").read_text()
    native = (ROOT / "Sources/PlaneFuseCore/MetalMobileNetV2NativeStem.swift").read_text()
    b2 = method(rgb, "public func executeCHW(", "    /// Exact B2 shared-path submission")
    b2_profile = method(rgb, "public func executeCHWTimed(", "    public func encodeCHWConversion")
    c1 = method(native, "public func execute(", "    /// Returns CPU encoding")
    c1_profile = method(native, "public func executeTimed(", "    /// Encodes only Pipeline C")

    if "executeCHWTimed" in b2 or "ProcessInfo" in b2 or "gpuStartTime" in b2:
        fail("production B2 executeCHW contains profiler instrumentation")
    if "encodeCHWConversion" not in b2 or "encodeCHWStem" not in b2 or "waitUntilCompleted" not in b2:
        fail("production B2 no longer encodes and waits for both accepted helpers")
    if "ProcessInfo" not in b2_profile or "gpuStartTime" not in b2_profile:
        fail("B2 profiler path has no timing instrumentation")
    if "encodeCHWConversion" not in b2_profile or "encodeCHWStem" not in b2_profile:
        fail("B2 profiler path does not use the accepted encoding helpers")
    if "executeTimed" in c1 or "ProcessInfo" in c1 or "gpuStartTime" in c1:
        fail("production C1 execute contains profiler instrumentation")
    if "encode(input" not in c1 or "waitUntilCompleted" not in c1:
        fail("production C1 no longer encodes and waits for the accepted helper")
    if "ProcessInfo" not in c1_profile or "gpuStartTime" not in c1_profile:
        fail("C1 profiler path has no timing instrumentation")
    print("PASS R7 production instrumentation: B2/C1 production paths are uninstrumented; profiler paths share helpers")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
