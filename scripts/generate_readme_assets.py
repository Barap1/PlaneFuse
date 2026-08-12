#!/usr/bin/env python3
"""Generate README graphs and system diagrams from committed evidence."""

from __future__ import annotations

import html
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
FINAL = ROOT / "proof/r7.5-source-reuse-final-52db138-20260811T1605Z-confirm.json"
PROFILE = ROOT / "proof/r7-final-shared-path-profile-repaired-conditions.json"
ASSETS = ROOT / "docs/assets"
DIAGRAMS = ROOT / "docs/diagrams"


def read(path: Path) -> dict:
    return json.loads(path.read_text())


def svg_header(width: int, height: int, title: str, description: str) -> str:
    source = html.escape(str(FINAL.relative_to(ROOT)))
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}" role="img" aria-labelledby="title desc">
<title id="title">{html.escape(title)}</title><desc id="desc">{html.escape(description)}</desc>
<!-- Generated from {source}; do not edit benchmark values by hand. -->
<style>text {{ font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }} .mono {{ font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }}</style>
'''


def latency_svg(final: dict) -> str:
    stats = final["aggregate"]["statistics"]
    values = [("B2", stats["B2"]["p50"], "#7c9cf5"), ("C1", stats["C1"]["p50"], "#9ba9b2"), ("C1-SR", stats["C1-SR"]["p50"], "#64e6c4")]
    max_value = max(value for _, value, _ in values) * 1.18
    base_y, chart_h = 250, 160
    parts = [svg_header(760, 330, "Matched Release p50 latency", "Bar chart from the authoritative R7.5 confirmation artifact. MobileNetV2 NV12 benchmark.")]
    parts += ['<rect width="760" height="330" rx="16" fill="#101920"/>', '<text x="36" y="42" fill="#f2f7f5" font-size="20" font-weight="700">Matched Release p50 latency</text>', '<text x="36" y="68" fill="#91a0aa" font-size="13">MobileNetV2 / NV12 · milliseconds · lower is better</text>']
    for i, (name, value, color) in enumerate(values):
        x = 110 + i * 190
        height = value / max_value * chart_h
        y = base_y - height
        parts.append(f'<rect x="{x}" y="{y:.2f}" width="92" height="{height:.2f}" rx="8" fill="{color}"/>')
        parts.append(f'<text x="{x + 46}" y="{y - 12:.2f}" fill="#f2f7f5" font-size="15" text-anchor="middle" class="mono">{value:.6f}</text>')
        parts.append(f'<text x="{x + 46}" y="{base_y + 28}" fill="#c8d2d4" font-size="14" text-anchor="middle" font-weight="700">{name}</text>')
    parts += ['<text x="36" y="306" fill="#71818c" font-size="11">Source: proof/r7.5-source-reuse-final-52db138-20260811T1605Z-confirm.json</text>', '</svg>']
    return "".join(parts)


def memory_svg(profile: dict) -> str:
    resources = profile["resources"]
    b2 = resources["b2_rgb_metal_allocated_bytes"]
    c1 = resources["c1_rgb_metal_allocated_bytes"]
    parts = [svg_header(760, 270, "Full RGB intermediate allocation", "Structural resource comparison from the authoritative profiler summary. This is not total memory.")]
    parts += ['<rect width="760" height="270" rx="16" fill="#101920"/>', '<text x="36" y="42" fill="#f2f7f5" font-size="20" font-weight="700">Full RGB intermediate allocation</text>', '<text x="36" y="68" fill="#91a0aa" font-size="13">Metal resource boundary · not total memory</text>']
    bar_y = [112, 174]
    for y, name, value, color in [(bar_y[0], "B2", b2, "#7c9cf5"), (bar_y[1], "C1-SR", c1, "#64e6c4")]:
        width = 520 if value else 0
        parts.append(f'<text x="36" y="{y + 17}" fill="#c8d2d4" font-size="14" font-weight="700">{name}</text>')
        parts.append(f'<rect x="120" y="{y}" width="520" height="26" rx="7" fill="#1c2a33"/>')
        if width: parts.append(f'<rect x="120" y="{y}" width="{width}" height="26" rx="7" fill="{color}"/>')
        label = f"{value:,} B" if value else "0 B"
        parts.append(f'<text x="660" y="{y + 18}" fill="#f2f7f5" font-size="14" class="mono">{label}</text>')
    parts += ['<text x="36" y="244" fill="#71818c" font-size="11">Source: proof/r7-final-shared-path-profile-repaired-conditions.json</text>', '</svg>']
    return "".join(parts)


def architecture_svg() -> str:
    parts = [svg_header(1100, 620, "PlaneFuse system architecture", "Comparison of the materialized RGB baseline and the PlaneFuse source-reuse stem before the shared MobileNetV2 tail.")]
    parts += ['<rect width="1100" height="620" rx="20" fill="#0f171d"/>', '<text x="48" y="54" fill="#f2f7f5" font-size="26" font-weight="700">One camera input, two representation schedules</text>', '<text x="48" y="82" fill="#93a3ad" font-size="14">The learned tail and output boundary stay matched.</text>']
    parts.append('<rect x="48" y="112" width="1004" height="70" rx="12" fill="#1a2730" stroke="#52636d"/><text x="550" y="141" text-anchor="middle" fill="#dbe5e1" font-size="16" font-weight="700">CAMERA INPUT</text><text x="550" y="166" text-anchor="middle" fill="#64e6c4" font-size="14" class="mono">NV12 Y + UV planes</text>')
    lanes = [(220, "B2 · MATERIALIZED RGB", "#7c9cf5", ["YUV decode", "Float32 RGB tensor\n606,208 B Metal", "pretrained RGB stem"]), (640, "C1-SR · SOURCE REUSE", "#64e6c4", ["source tile staging", "9×9 Y + 5×5 UV", "transformed stem\nreuse across channels"])]
    for x, title, color, nodes in lanes:
        parts.append(f'<text x="{x + 120}" y="218" text-anchor="middle" fill="{color}" font-size="14" font-weight="700">{title}</text>')
        for i, node in enumerate(nodes):
            y = 244 + i * 62
            parts.append(f'<rect x="{x}" y="{y}" width="240" height="42" rx="9" fill="#182730" stroke="{color}" stroke-opacity="0.65"/>')
            lines = node.split("\\n")
            for j, line in enumerate(lines): parts.append(f'<text x="{x + 120}" y="{y + 18 + j * 14}" text-anchor="middle" fill="#dbe5e1" font-size="12">{html.escape(line)}</text>')
            if i < len(nodes) - 1: parts.append(f'<path d="M{x + 120} {y + 42} L{x + 120} {y + 62}" stroke="{color}" stroke-width="2" marker-end="url(#{"arrowBlue" if color == "#7c9cf5" else "arrowGreen"})"/>')
        parts.append(f'<path d="M{x + 120} 430 L{x + 120} 462" stroke="{color}" stroke-width="2" marker-end="url(#{"arrowBlue" if color == "#7c9cf5" else "arrowGreen"})"/>')
    parts.append('<rect x="280" y="462" width="540" height="62" rx="12" fill="#1a2730" stroke="#d4a45f" stroke-opacity="0.75"/><text x="550" y="489" text-anchor="middle" fill="#f0c27a" font-size="14" font-weight="700">SHARED MOBILE NET V2 TAIL</text><text x="550" y="510" text-anchor="middle" fill="#c9d5d1" font-size="12">persistent 48×112×112 Float32 activation → Core ML</text>')
    parts.append('<path d="M550 524 L550 552" stroke="#d4a45f" stroke-width="2" marker-end="url(#arrowGold)"/><text x="550" y="585" text-anchor="middle" fill="#dbe5e1" font-size="16" font-weight="700">same prediction boundary</text>')
    parts.append('<defs><marker id="arrowBlue" markerWidth="8" markerHeight="8" refX="5" refY="3" orient="auto"><path d="M0,0 L6,3 L0,6 Z" fill="#7c9cf5"/></marker><marker id="arrowGreen" markerWidth="8" markerHeight="8" refX="5" refY="3" orient="auto"><path d="M0,0 L6,3 L0,6 Z" fill="#64e6c4"/></marker><marker id="arrowGold" markerWidth="8" markerHeight="8" refX="5" refY="3" orient="auto"><path d="M0,0 L6,3 L0,6 Z" fill="#d4a45f"/></marker></defs></svg>')
    return "".join(parts)


def source_reuse_svg() -> str:
    parts = [svg_header(900, 310, "C1-SR source reuse schedule", "A source-reuse tile is staged once and reused across output channels.")]
    parts += ['<rect width="900" height="310" rx="18" fill="#0f171d"/>', '<text x="40" y="45" fill="#f2f7f5" font-size="22" font-weight="700">C1-SR source reuse schedule</text>']
    nodes = [(52, "NV12 source tile", "Y + UV", "#7c9cf5"), (238, "cooperative staging", "threadgroup memory", "#64e6c4"), (424, "tap reuse", "9×9 Y / 5×5 UV", "#64e6c4"), (610, "activation tile", "48 output channels", "#d4a45f")]
    for i, (x, title, subtitle, color) in enumerate(nodes):
        parts.append(f'<rect x="{x}" y="120" width="150" height="82" rx="12" fill="#192831" stroke="{color}" stroke-width="1.5"/><text x="{x + 75}" y="151" text-anchor="middle" fill="#f2f7f5" font-size="13" font-weight="700">{title}</text><text x="{x + 75}" y="174" text-anchor="middle" fill="#b9c8c8" font-size="11">{subtitle}</text>')
        if i < len(nodes) - 1: parts.append(f'<path d="M{x + 150} 161 L{x + 184} 161" stroke="{color}" stroke-width="2" marker-end="url(#{"greenArrow" if color == "#64e6c4" else "blueArrow"})"/>')
    parts.append('<text x="450" y="252" text-anchor="middle" fill="#a9b8bd" font-size="13">The full RGB tensor is absent from this path. The activation handoff remains matched.</text><defs><marker id="blueArrow" markerWidth="8" markerHeight="8" refX="5" refY="3" orient="auto"><path d="M0,0 L6,3 L0,6 Z" fill="#7c9cf5"/></marker><marker id="greenArrow" markerWidth="8" markerHeight="8" refX="5" refY="3" orient="auto"><path d="M0,0 L6,3 L0,6 Z" fill="#64e6c4"/></marker></defs></svg>')
    return "".join(parts)


def main() -> int:
    final = read(FINAL)
    profile = read(PROFILE)
    ASSETS.mkdir(parents=True, exist_ok=True)
    DIAGRAMS.mkdir(parents=True, exist_ok=True)
    (ASSETS / "latency-comparison.svg").write_text(latency_svg(final))
    (ASSETS / "rgb-intermediate.svg").write_text(memory_svg(profile))
    (DIAGRAMS / "planefuse-architecture.svg").write_text(architecture_svg())
    (DIAGRAMS / "source-reuse.svg").write_text(source_reuse_svg())
    print("PASS readme assets: generated latency, representation, architecture, and source-reuse visuals")
    print(f"source: {FINAL.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
