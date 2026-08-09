#!/usr/bin/env python3
"""Derive reproducible MobileNetV2 stem and unchanged-tail Core ML artifacts.

The source model remains the authoritative pretrained asset. This tool only
changes the graph boundary: the first Conv+BatchNorm+ReLU6 layers become a
native-plane stem contract, while the tail keeps the original classifier graph.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import coremltools as ct
from coremltools.proto import FeatureTypes_pb2


STEM_LAYER_COUNT = 6
STEM_OUTPUT = "planefuse_mobilenetv2_stem_features"
STEM_SHAPE = [48, 112, 112]
ARRAY_INPUT = "planefuse_mobilenetv2_normalized_rgb"
ARRAY_INPUT_SHAPE = [3, 224, 224]
# Core ML `same` for this 224x224, kernel-3, stride-2 convolution is SAME_UPPER:
# the one padding pixel is on the bottom/right, so source = 2 * output + tap.
STEM_PADDING_MODE = "same_bottom_right"
STEM_ASYMMETRY_MODE = "BOTTOM_RIGHT_HEAVY"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def portable_path(path: Path) -> str:
    """Store repository-relative paths so generated manifests work from clones."""
    resolved = path.resolve()
    try:
        return str(resolved.relative_to(Path.cwd().resolve()))
    except ValueError:
        return str(resolved)


def validate_source(spec) -> list:
    if spec.WhichOneof("Type") != "neuralNetworkClassifier":
        raise ValueError("MobileNetV2 source must be a neuralNetworkClassifier")
    if len(spec.description.input) != 1:
        raise ValueError("MobileNetV2 source must have exactly one input")
    image = spec.description.input[0].type.imageType
    if (image.width, image.height) != (224, 224):
        raise ValueError("expected a 224x224 MobileNetV2 input")
    layers = list(spec.neuralNetworkClassifier.layers)
    expected = ["convolution", "batchnorm", "activation", "activation", "unary", "activation"]
    actual = [layer.WhichOneof("layer") for layer in layers[:STEM_LAYER_COUNT]]
    if actual != expected:
        raise ValueError(f"unsupported MobileNetV2 stem layer sequence: {actual}")
    conv = layers[0].convolution
    if (conv.kernelChannels, conv.outputChannels) != (3, 48):
        raise ValueError("expected MobileNetV2 first convolution to be 3 -> 48 channels")
    if list(conv.kernelSize) != [3, 3] or list(conv.stride) != [2, 2] or not conv.HasField("same"):
        raise ValueError("expected a same-padded 3x3 stride-2 first convolution")
    asymmetry_field = conv.same.DESCRIPTOR.fields_by_name["asymmetryMode"]
    asymmetry_mode = asymmetry_field.enum_type.values_by_number[conv.same.asymmetryMode].name
    if asymmetry_mode != STEM_ASYMMETRY_MODE:
        raise ValueError(f"expected {STEM_ASYMMETRY_MODE} SAME padding, found {asymmetry_mode}")
    expected_output = (224 + 2 - 1) // 2
    if expected_output != STEM_SHAPE[1] or STEM_PADDING_MODE != "same_bottom_right":
        raise ValueError("unsupported MobileNetV2 SAME padding contract")
    if layers[1].batchnorm.channels != 48:
        raise ValueError("expected 48-channel first batch normalization")
    return layers


def make_stem(source: Path, output: Path) -> None:
    spec = ct.utils.load_spec(str(source))
    layers = validate_source(spec)
    classifier = spec.neuralNetworkClassifier
    stem = spec.neuralNetwork
    stem.layers.extend(layers[:STEM_LAYER_COUNT])
    stem.layers[-1].output[0] = STEM_OUTPUT
    stem.preprocessing.extend(classifier.preprocessing)
    spec.ClearField("neuralNetworkClassifier")
    del spec.description.output[:]
    output_description = spec.description.output.add()
    output_description.name = STEM_OUTPUT
    output_description.shortDescription = "MobileNetV2 Conv+BatchNorm+ReLU6 activation"
    output_description.type.multiArrayType.dataType = FeatureTypes_pb2.ArrayFeatureType.FLOAT32
    output_description.type.multiArrayType.shape[:] = STEM_SHAPE
    make_array_input(spec)
    ct.utils.save_spec(spec, str(output))


def make_tail(source: Path, output: Path) -> None:
    spec = ct.utils.load_spec(str(source))
    layers = validate_source(spec)
    classifier = spec.neuralNetworkClassifier
    tail_layers = layers[STEM_LAYER_COUNT:]
    del classifier.layers[:]
    classifier.layers.extend(tail_layers)
    classifier.layers[0].input[0] = STEM_OUTPUT
    classifier.preprocessing.clear()
    input_description = spec.description.input[0]
    input_description.name = STEM_OUTPUT
    input_description.type.ClearField("imageType")
    input_description.type.multiArrayType.dataType = FeatureTypes_pb2.ArrayFeatureType.FLOAT32
    input_description.type.multiArrayType.shape[:] = STEM_SHAPE
    ct.utils.save_spec(spec, str(output))


def make_array_input(spec) -> None:
    """Replace the source image input and its scaler with preprocessed CHW floats.

    The original model's image scaler is exactly `pixel / 127.5 - 1`.  Keeping
    the learned graph unchanged while accepting those values directly eliminates
    Core ML image decoding, orientation, and resize behavior from parity proof.
    """
    if spec.HasField("neuralNetworkClassifier"):
        network = spec.neuralNetworkClassifier
    elif spec.HasField("neuralNetwork"):
        network = spec.neuralNetwork
    else:
        raise ValueError("array-input conversion requires a neural-network model")
    network.preprocessing.clear()
    for layer in network.layers:
        layer.input[:] = [ARRAY_INPUT if name == "image" else name for name in layer.input]
    input_description = spec.description.input[0]
    input_description.name = ARRAY_INPUT
    input_description.type.ClearField("imageType")
    input_description.type.multiArrayType.dataType = FeatureTypes_pb2.ArrayFeatureType.FLOAT32
    input_description.type.multiArrayType.shape[:] = ARRAY_INPUT_SHAPE


def make_full_array(source: Path, output: Path) -> None:
    spec = ct.utils.load_spec(str(source))
    validate_source(spec)
    make_array_input(spec)
    ct.utils.save_spec(spec, str(output))


def export_coefficients(source: Path, output: Path) -> None:
    spec = ct.utils.load_spec(str(source))
    layers = validate_source(spec)
    convolution = layers[0].convolution
    batch_norm = layers[1].batchnorm
    values = {
        "convolutionWeights": list(convolution.weights.floatValue),
        "batchNormScale": list(batch_norm.gamma.floatValue),
        "batchNormBias": list(batch_norm.beta.floatValue),
        "batchNormMean": list(batch_norm.mean.floatValue),
        "batchNormVariance": list(batch_norm.variance.floatValue),
        "batchNormEpsilon": batch_norm.epsilon,
    }
    output.write_text(json.dumps(values, separators=(",", ":")) + "\n")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output_dir", type=Path)
    args = parser.parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)
    source = args.source.resolve()
    stem = args.output_dir / "MobileNetV2Stem.mlmodel"
    full_array = args.output_dir / "MobileNetV2FullArray.mlmodel"
    tail = args.output_dir / "MobileNetV2Tail.mlmodel"
    coefficients = args.output_dir / "MobileNetV2StemCoefficients.json"
    make_stem(source, stem)
    make_full_array(source, full_array)
    make_tail(source, tail)
    export_coefficients(source, coefficients)
    manifest = {
        "schema_version": 1,
        "source": portable_path(source),
        "source_sha256": sha256(source),
        "stem": {
            "path": portable_path(stem),
            "sha256": sha256(stem),
            "layer_count": STEM_LAYER_COUNT,
            "input": ARRAY_INPUT,
            "input_shape": ARRAY_INPUT_SHAPE,
            "output": STEM_OUTPUT,
            "shape": STEM_SHAPE,
            "padding_mode": STEM_PADDING_MODE,
            "asymmetry_mode": STEM_ASYMMETRY_MODE,
            "input_coordinate": "2 * output + tap",
            "operations": ["Conv2D 3x3 stride 2 SAME(bottom/right)", "BatchNorm", "ReLU6"],
            "coefficients": portable_path(coefficients),
        },
        "full_array": {
            "path": portable_path(full_array),
            "sha256": sha256(full_array),
            "input": ARRAY_INPUT,
            "input_shape": ARRAY_INPUT_SHAPE,
            "output": "classLabelProbs",
            "derived_from_source_classifier": True,
        },
        "tail": {
            "path": portable_path(tail),
            "sha256": sha256(tail),
            "input": STEM_OUTPUT,
            "shape": STEM_SHAPE,
            "output": "classLabelProbs",
            "source_layer_start": STEM_LAYER_COUNT,
            "preserves_source_classifier": True,
        },
    }
    if (manifest["stem"]["padding_mode"] != STEM_PADDING_MODE
            or manifest["stem"]["asymmetry_mode"] != STEM_ASYMMETRY_MODE
            or manifest["stem"]["input_coordinate"] != "2 * output + tap"
            or manifest["stem"]["input"] != manifest["full_array"]["input"]
            or manifest["stem"]["input_shape"] != manifest["full_array"]["input_shape"]
            or manifest["tail"]["input"] != manifest["stem"]["output"]
            or manifest["tail"]["shape"] != manifest["stem"]["shape"]):
        raise ValueError("invalid preparation manifest padding contract")
    (args.output_dir / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps(manifest, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
