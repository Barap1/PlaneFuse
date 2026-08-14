#!/usr/bin/env python3
"""Create the checked-in SVG for the controlled source-reuse scaling result."""
import json
from pathlib import Path


def main():
    artifact = json.loads(Path("proof/final/source-reuse-scaling.json").read_text())
    rows = artifact["widths"]
    width, height = 860, 520
    left, top, right, bottom = 86, 40, 34, 86
    plot_w, plot_h = width - left - right, height - top - bottom
    max_value = max(row["c1"]["wall"]["p50_ms"] for row in rows)
    max_value = max(max_value, max(row["c1_source_reuse"]["wall"]["p50_ms"] for row in rows)) * 1.18
    min_value = 0

    def x(index):
        return left + index * plot_w / (len(rows) - 1)

    def y(value):
        return top + (max_value - value) / (max_value - min_value) * plot_h

    def points(key):
        return " ".join(f"{x(i):.1f},{y(row[key]['wall']['p50_ms']):.1f}" for i, row in enumerate(rows))

    ticks = [0.0, 0.05, 0.10, 0.15, 0.20, 0.25]
    ticks = [tick for tick in ticks if tick <= max_value]
    svg = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
        '<title>Stem-only source-reuse scaling</title>',
        '<desc>Wall-clock p50 for the original C1 stem and C1-SR source reuse across active output-channel widths.</desc>',
        '<rect width="100%" height="100%" fill="#0d151b"/>',
        '<text x="86" y="26" fill="#f4f7f5" font-family="-apple-system,BlinkMacSystemFont,Helvetica,sans-serif" font-size="19" font-weight="700">How source reuse scales</text>',
        '<text x="86" y="48" fill="#9aaab3" font-family="-apple-system,BlinkMacSystemFont,Helvetica,sans-serif" font-size="12">Stem-only controlled microbenchmark · Release · 224×224 NV12 · wall p50</text>',
    ]
    for tick in ticks:
        yy = y(tick)
        svg.append(f'<line x1="{left}" y1="{yy:.1f}" x2="{width-right}" y2="{yy:.1f}" stroke="#26343d" stroke-width="1"/>')
        svg.append(f'<text x="{left-12}" y="{yy+4:.1f}" text-anchor="end" fill="#9aaab3" font-family="SFMono-Regular,Menlo,monospace" font-size="11">{tick:.2f}</text>')
    svg.append(f'<line x1="{left}" y1="{top}" x2="{left}" y2="{height-bottom}" stroke="#71808a"/>')
    svg.append(f'<line x1="{left}" y1="{height-bottom}" x2="{width-right}" y2="{height-bottom}" stroke="#71808a"/>')
    for index, row in enumerate(rows):
        xx = x(index)
        svg.append(f'<line x1="{xx:.1f}" y1="{height-bottom}" x2="{xx:.1f}" y2="{height-bottom+5}" stroke="#71808a"/>')
        svg.append(f'<text x="{xx:.1f}" y="{height-bottom+22}" text-anchor="middle" fill="#d5dfe2" font-family="SFMono-Regular,Menlo,monospace" font-size="12">{row["active_output_channels"]}</text>')
    svg.append(f'<polyline points="{points("c1")}" fill="none" stroke="#f0b46a" stroke-width="3"/>')
    svg.append(f'<polyline points="{points("c1_source_reuse")}" fill="none" stroke="#64e6c4" stroke-width="3"/>')
    for key, color in [("c1", "#f0b46a"), ("c1_source_reuse", "#64e6c4")]:
        for index, row in enumerate(rows):
            svg.append(f'<circle cx="{x(index):.1f}" cy="{y(row[key]["wall"]["p50_ms"]):.1f}" r="4" fill="{color}"/>')
    svg.extend([
        '<text x="24" y="240" transform="rotate(-90 24 240)" text-anchor="middle" fill="#d5dfe2" font-family="-apple-system,BlinkMacSystemFont,Helvetica,sans-serif" font-size="12">stem/frontend p50 (ms)</text>',
        f'<text x="{(left + width-right)/2:.1f}" y="{height-30}" text-anchor="middle" fill="#d5dfe2" font-family="-apple-system,BlinkMacSystemFont,Helvetica,sans-serif" font-size="12">active output channels</text>',
        '<rect x="600" y="66" width="14" height="4" fill="#f0b46a"/><text x="622" y="71" fill="#d5dfe2" font-family="-apple-system,BlinkMacSystemFont,Helvetica,sans-serif" font-size="12">C1</text>',
        '<rect x="660" y="66" width="14" height="4" fill="#64e6c4"/><text x="682" y="71" fill="#d5dfe2" font-family="-apple-system,BlinkMacSystemFont,Helvetica,sans-serif" font-size="12">C1-SR</text>',
        '<text x="86" y="505" fill="#71808a" font-family="-apple-system,BlinkMacSystemFont,Helvetica,sans-serif" font-size="10">Partial widths isolate the source-reuse mechanism; they are not complete alternate neural networks.</text>',
        '</svg>',
    ])
    Path("docs/assets/source-reuse-scaling.svg").write_text("\n".join(svg) + "\n")
    print("PASS source-reuse scaling graph: docs/assets/source-reuse-scaling.svg")


if __name__ == "__main__":
    main()
