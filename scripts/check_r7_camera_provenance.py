#!/usr/bin/env python3
"""Check the historical-camera/current-acquisition qualification packet."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path


def main() -> int:
    evidence_path = Path("proof/r7-camera-evidence.json")
    evidence = json.loads(evidence_path.read_text())
    source_path = Path(evidence["source_artifact"])
    source = json.loads(source_path.read_text())
    attempt = json.loads(Path(evidence["current_attempt_artifact"]).read_text())
    replay = source["replay"]
    payload = source_path.with_name("r6.1-camera-replay.bin")
    manifest = source_path.with_name("r6.1-camera-replay.manifest.json")
    if replay["frameCount"] != 300 or len(replay["frameIDs"]) != 300:
        raise SystemExit("FAIL R7 camera provenance: historical replay is not 300 frames")
    if hashlib.sha256(payload.read_bytes()).hexdigest() != replay["payloadSHA256"]:
        raise SystemExit("FAIL R7 camera provenance: replay payload hash mismatch")
    if hashlib.sha256(manifest.read_bytes()).hexdigest() != replay["manifestSHA256"]:
        raise SystemExit("FAIL R7 camera provenance: replay manifest hash mismatch")
    paired = source["paired"]
    if paired["batchCount"] != 5 or paired["pairsPerBatch"] != 200 or len(paired["differences"]) != 1000:
        raise SystemExit("FAIL R7 camera provenance: historical paired protocol cardinality")
    if source["quality"]["top1Agreement"] != 1.0 or source["quality"]["cFullRGBIntermediateBytes"] != 0 or source["quality"]["cpuElementByElementPopulationBytes"] != 0:
        raise SystemExit("FAIL R7 camera provenance: historical quality/resource gate")
    if not (paired["bootstrap"]["medianDifference"]["lower"] < 0 < paired["bootstrap"]["medianDifference"]["upper"]):
        raise SystemExit("FAIL R7 camera provenance: historical camera CI no longer crosses zero")
    if attempt["status"] != "unavailable_before_first_callback" or attempt["callbacks_received"] != 0 or attempt["processed_frames"] != 0:
        raise SystemExit("FAIL R7 camera provenance: fresh acquisition failure record changed")
    print("PASS R7 camera provenance: historical 300-frame evidence and zero-callback current attempt are qualified")
    print(f"historical commit: {source['commit']}; replay: {replay['frameCount']} frames; paired: {len(paired['differences'])} samples")
    print("current camera: zero callbacks; no current performance values inferred")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
