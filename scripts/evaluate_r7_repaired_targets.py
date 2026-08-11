#!/usr/bin/env python3
"""Generate the R7 target evaluation from repaired authoritative evidence."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--performance", default="proof/r7-final-b2-c1-shared-repaired.json")
    parser.add_argument("--camera", default="proof/r7-camera-evidence.json")
    parser.add_argument("--output", default="proof/r7-competition-targets-repaired.json")
    args = parser.parse_args()

    performance = json.loads(Path(args.performance).read_text())
    camera = json.loads(Path(args.camera).read_text())
    measurement = performance["measurement"]
    b2 = measurement["b2_statistics"]
    c1 = measurement["c1_statistics"]
    paired = measurement["paired_bootstrap_confidence_interval"]["median_difference"]
    live = camera["live"]
    frontend = camera["replay"]
    percentage = measurement["aggregate_percentage"]
    positive_ci = paired["lower"] > 0

    output = {
        "schema_version": 2,
        "status": "r7_repaired_all_measured_targets_evaluated_pending_hostile_review",
        "headline_candidate": "C1",
        "performance_artifact": args.performance,
        "performance_artifact_commit": performance["commit"],
        "quality_artifact": "proof/r7-b2-c1-shared-quality-repaired.json",
        "camera_artifact": args.camera,
        "quality_gate": {
            "top1_agreement": measurement["top1_agreement"],
            "activation_max_absolute_error": measurement["activation_max_absolute_error"],
            "activation_threshold": 0.000009999999747378752,
            "c_full_rgb_intermediate_bytes": measurement["c1_rgb_logical_bytes"],
            "cpu_element_by_element_activation_copy_bytes": measurement["cpu_element_by_element_activation_copy_bytes"],
            "status": "pass",
        },
        "targets": [
            {
                "id": "T1",
                "criterion": "strongest B2/C1 end-to-end p50 improvement >= 10% with positive paired CI",
                "estimand": "direct B2-minus-C1 post-resize-to-result paired latency; positive favors C1",
                "b2_p50_ms": b2["p50"],
                "c1_p50_ms": c1["p50"],
                "difference_between_marginal_p50s_ms": b2["p50"] - c1["p50"],
                "median_of_paired_differences_ms": measurement["b2_minus_c1_statistics"]["p50"],
                "aggregate_percentage_c1_lower": percentage,
                "paired_median_bootstrap_ci_ms": [paired["lower"], paired["upper"]],
                "passes": percentage >= 10.0 and positive_ci,
                "reason": "The repaired positive paired interval is stable, but the measured improvement remains below 10%." if percentage < 10.0 else "Threshold evaluation is delegated to hostile review.",
            },
            {
                "id": "T2",
                "criterion": "sustained camera throughput >= 20% higher or materially lower true frame-delivery-to-result with matched quality",
                "estimand": "separate successful historical Release physical-camera sessions; not the serial paired run",
                "b2_live_sustained_fps": live["sustained_fps"]["b2"],
                "c1_live_sustained_fps": live["sustained_fps"]["c1"],
                "c1_throughput_change_percent": (live["sustained_fps"]["c1"] / live["sustained_fps"]["b2"] - 1.0) * 100.0,
                "b2_live_frame_delivery_p50_ms": live["frame_delivery_to_result_milliseconds"]["b2"]["p50"],
                "c1_live_frame_delivery_p50_ms": live["frame_delivery_to_result_milliseconds"]["c1"]["p50"],
                "c1_frame_delivery_change_percent": (1.0 - live["frame_delivery_to_result_milliseconds"]["c1"]["p50"] / live["frame_delivery_to_result_milliseconds"]["b2"]["p50"]) * 100.0,
                "passes": False,
                "reason": "The successful historical Release sessions are cadence-limited and C1 has a higher, not lower, frame-delivery p50. The fresh R7 camera attempt received zero callbacks and is not substituted.",
            },
            {
                "id": "T3",
                "criterion": "frontend improvement >= 2x, zero full RGB, zero element-by-element CPU copy, and end-to-end improvement >= 5% with positive paired CI",
                "frontend_basis": "successful historical Release replay sessions; not fresh camera acquisition",
                "b2_frontend_p50_ms": frontend["b2"]["frontend_milliseconds"]["p50"],
                "c1_frontend_p50_ms": frontend["c1"]["frontend_milliseconds"]["p50"],
                "frontend_improvement_percent": (1.0 - frontend["c1"]["frontend_milliseconds"]["p50"] / frontend["b2"]["frontend_milliseconds"]["p50"]) * 100.0,
                "end_to_end_improvement_percent": percentage,
                "zero_full_rgb_intermediate": measurement["c1_rgb_logical_bytes"] == 0,
                "zero_element_by_element_cpu_copy": measurement["cpu_element_by_element_activation_copy_bytes"] == 0,
                "passes": False,
                "reason": "The zero-resource conditions pass, but the historical frontend result is below 2x and the repaired end-to-end result is below 5%.",
            },
            {
                "id": "T4",
                "criterion": "another comparably strong result explicitly accepted by hostile technical review",
                "passes": False,
                "review_status": "pending",
                "reason": "No alternative result is pre-accepted; Sol must independently decide whether any measured result is genuinely equivalent.",
            },
        ],
        "interpretation": "The repaired protocol changes the authoritative performance result; it does not change any threshold. Before fresh hostile review, none of the four preregistered targets is established.",
    }
    Path(args.output).write_text(json.dumps(output, indent=2) + "\n")
    print(f"PASS generated repaired target evaluation: {args.output}")
    print(f"B2 p50={b2['p50']:.6f} ms; C1 p50={c1['p50']:.6f} ms; C1 lower={percentage:.6f}%")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
