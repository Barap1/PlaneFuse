#!/usr/bin/env python3
"""Create an R3 Float16-input copy of the unchanged derived MobileNetV2 tail."""

from __future__ import annotations

import argparse
from pathlib import Path

import coremltools as ct
from coremltools.proto import FeatureTypes_pb2


EXPECTED_SHAPE = [48, 112, 112]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    spec = ct.utils.load_spec(str(args.source))
    if len(spec.description.input) != 1:
        raise ValueError("Float16 tail preparation requires one input")
    input_description = spec.description.input[0]
    multi_array = input_description.type.multiArrayType
    if list(multi_array.shape) != EXPECTED_SHAPE or multi_array.dataType != FeatureTypes_pb2.ArrayFeatureType.FLOAT32:
        raise ValueError("expected the derived Float32 [48,112,112] tail input")
    # Float16 multi-array feature declarations require Core ML specification v7.
    spec.specificationVersion = max(spec.specificationVersion, 7)
    multi_array.dataType = FeatureTypes_pb2.ArrayFeatureType.FLOAT16
    args.output.parent.mkdir(parents=True, exist_ok=True)
    ct.utils.save_spec(spec, str(args.output))
    print(args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
