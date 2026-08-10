#!/usr/bin/env python3
"""Fail-closed structural verifier for the R6.1 camera benchmark artifact."""

import hashlib
import json
import math
import sys
from pathlib import Path


def nearest_rank(values, percentile):
    ordered = sorted(values)
    return ordered[math.ceil(percentile * len(ordered)) - 1]


def require(condition, message):
    if not condition:
        raise SystemExit(f"FAIL r6 camera artifact: {message}")


def main():
    artifact_path = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("benchmarks/results/r6-camera.json")
    artifact = json.loads(artifact_path.read_text())
    require(artifact["schemaVersion"] == "r6.1-camera-benchmark-v1", "schema version")
    require(artifact["buildConfiguration"] == "release", "artifact is not Release")
    require(artifact["computeUnitsPolicy"] == "all", "matched compute-unit policy is not all")
    require(artifact["statisticsAlgorithmVersion"] == "r6.1-hierarchical-block-bootstrap-v1", "statistics version")

    replay = artifact["replay"]
    require(replay["frameCount"] >= 300, "replay has fewer than 300 frames")
    require(replay["frameIDs"] == list(range(replay["frameCount"])), "replay frame IDs are not deterministic")
    require(len(replay["callbackSequences"]) == replay["frameCount"], "replay callback sequence count")
    payload_path = artifact_path.with_name("r6-camera-replay.bin")
    manifest_path = artifact_path.with_name("r6-camera-replay.manifest.json")
    require(payload_path.exists() and manifest_path.exists(), "replay payload or manifest missing")
    payload_hash = hashlib.sha256(payload_path.read_bytes()).hexdigest()
    require(payload_hash == replay["payloadSHA256"], "replay payload hash mismatch")
    manifest_hash = hashlib.sha256(manifest_path.read_bytes()).hexdigest()
    require(manifest_hash == replay["manifestSHA256"], "replay manifest hash mismatch")

    for key in ("b2Replay", "c1Replay"):
        candidate = artifact[key]
        require(candidate["source"] == "deterministic_replay", f"{key} is not replay-backed")
        require(candidate["processedFrames"] >= 300, f"{key} has fewer than 300 frames")
        require(candidate["replayPayloadSHA256"] == replay["payloadSHA256"], f"{key} replay hash mismatch")
    for key in ("b2Live", "c1Live"):
        candidate = artifact[key]
        require(candidate["source"] == "physical_camera_live", f"{key} is not physical-camera evidence")
        require(candidate["processedFrames"] >= 300, f"{key} has fewer than 300 frames")
        require("frameDeliveryToResult" in candidate, f"{key} lacks live delivery timing")

    paired = artifact["paired"]
    require(paired["batchCount"] == 5 and paired["pairsPerBatch"] == 200, "paired protocol cardinality")
    require(len(paired["differences"]) == 1000, "paired difference count")
    require(len(paired["rawPairRecords"]) == 1000, "raw paired record count")
    require(len(paired["batchDifferences"]) == 5, "batch record count")
    require(all(len(batch["differences"]) == 200 for batch in paired["batchDifferences"]), "batch pair count")
    b_values = [record["b2PostResizeInputToResultMilliseconds"] for record in paired["rawPairRecords"]]
    c_values = [record["c1PostResizeInputToResultMilliseconds"] for record in paired["rawPairRecords"]]
    differences = [record["differenceMilliseconds"] for record in paired["rawPairRecords"]]
    require(all(abs(a - b) < 1e-9 for a, b in zip(differences, paired["differences"])), "raw paired differences mismatch")
    require(all(abs((a - b) - d) < 1e-9 for a, b, d in zip(b_values, c_values, differences)), "B-C sign mismatch")
    expected_percentage = (nearest_rank(b_values, 0.5) - nearest_rank(c_values, 0.5)) / nearest_rank(b_values, 0.5) * 100
    require(abs(expected_percentage - paired["aggregatePercentage"]) < 1e-9, "aggregate percentage mismatch")
    require(paired["firstOrderPairs"] > 0 and paired["secondOrderPairs"] > 0, "paired order was not alternated")
    require(artifact["quality"]["cFullRGBIntermediateBytes"] == 0, "C RGB intermediate is nonzero")
    require(artifact["quality"]["cpuElementByElementPopulationBytes"] == 0, "CPU element population is nonzero")
    print(f"PASS r6 camera artifact: {artifact_path} ({len(paired['differences'])} paired samples, replay {payload_hash[:12]}…)")


if __name__ == "__main__":
    main()
