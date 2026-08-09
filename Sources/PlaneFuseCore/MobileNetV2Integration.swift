import CoreML
import CryptoKit
import Foundation

/// Immutable description of the selected M5 workload. Weight files are deliberately
/// not committed; the manifest records where they came from and what a local setup
/// must supply before an end-to-end result can be considered evidence.
public struct MobileNetV2AssetManifest: Codable, Equatable {
    public let modelIdentifier: String
    public let sourceURL: URL
    public let sourceModelFile: String
    public let sourceSHA256: String?
    public let tailModelDirectory: String
    public let tailInputName: String
    public let tailOutputName: String
    public let activationShape: [Int]
    public let paddingMode: Conv3x3Stride2PaddingMode
    public let validationCorpusManifest: String
    public let derivedManifest: String

    /// Core ML neural-network multi-array inputs omit the batch dimension.
    public static let expectedActivationShape = [48, 112, 112]

    public static let inspected = MobileNetV2AssetManifest(
        modelIdentifier: "Apple MobileNetV2 ImageNet",
        sourceURL: URL(string: "https://developer.apple.com/machine-learning/models/?q=MobileNetV2")!,
        sourceModelFile: "MobileNetV2.mlmodel",
        sourceSHA256: "cb5a35f593582232140556bbfa4618e66b37b8ff2fc33ba17db909e1050fd144",
        tailModelDirectory: "models/derived/tail-compiled/MobileNetV2Tail.mlmodelc",
        tailInputName: "planefuse_mobilenetv2_stem_features",
        tailOutputName: "classLabelProbs",
        activationShape: expectedActivationShape,
        paddingMode: .sameBottomRight,
        validationCorpusManifest: "proof/m5-validation-corpus.json",
        derivedManifest: "models/derived/manifest.json"
    )

    public func validate(at root: URL) throws {
        guard modelIdentifier == "Apple MobileNetV2 ImageNet", activationShape == Self.expectedActivationShape,
              paddingMode == .sameBottomRight else {
            throw MobileNetV2IntegrationError.unsupportedManifest
        }
        guard !tailInputName.isEmpty, !tailOutputName.isEmpty else { throw MobileNetV2IntegrationError.unsupportedManifest }
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent(validationCorpusManifest).path) else {
            throw MobileNetV2IntegrationError.validationCorpusMissing(root.appendingPathComponent(validationCorpusManifest))
        }
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent(derivedManifest).path) else {
            throw MobileNetV2IntegrationError.derivedManifestMissing(root.appendingPathComponent(derivedManifest))
        }
    }
}

public enum MobileNetV2IntegrationError: LocalizedError, Equatable {
    case unsupportedManifest
    case tailModelMissing(URL)
    case validationCorpusMissing(URL)
    case derivedManifestMissing(URL)
    case invalidDerivedManifest
    case modelHashMismatch(URL)
    case invalidActivationCount(expected: Int, actual: Int)
    case ambiguousTailInput
    case invalidTailInput(name: String, shape: [Int])
    case invalidStemInput(name: String, shape: [Int])
    case invalidStemOutput(name: String, shape: [Int])
    case unexpectedTailOutput(String)
    case emptyValidation

    public var errorDescription: String? {
        switch self {
        case .unsupportedManifest: return "The MobileNetV2 manifest does not describe the inspected 224px, 48x112x112 SAME-bottom-right stem boundary."
        case let .tailModelMissing(url): return "Missing extracted MobileNetV2 tail model at \(url.path)."
        case let .validationCorpusMissing(url): return "Missing MobileNetV2 validation corpus manifest at \(url.path)."
        case let .derivedManifestMissing(url): return "Missing MobileNetV2 derived-artifact manifest at \(url.path)."
        case .invalidDerivedManifest: return "The MobileNetV2 derived-artifact manifest does not preserve the inspected source, stem, and tail boundary."
        case let .modelHashMismatch(url): return "MobileNetV2 model SHA-256 does not match its provenance manifest: \(url.path)."
        case let .invalidActivationCount(expected, actual): return "Tail activation needs \(expected) Float32 values; received \(actual)."
        case .ambiguousTailInput: return "The tail must expose exactly one Float32 multi-array input for the stem activation."
        case let .invalidTailInput(name, shape): return "Tail input '\(name)' must be Float32 with exact shape \(shape)."
        case let .invalidStemInput(name, shape): return "StemArray input '\(name)' must be Float32 with exact shape \(shape)."
        case let .invalidStemOutput(name, shape): return "StemArray output '\(name)' must be Float32 with exact shape \(shape)."
        case let .unexpectedTailOutput(name): return "The tail output '\(name)' is not the expected classification-probability dictionary."
        case .emptyValidation: return "A MobileNetV2 output-agreement report needs at least one paired sample."
        }
    }
}

/// Parsed output from `prepare_mobilenetv2.py`. It is a local provenance gate:
/// the source and all three derived graph files are hash-checked before a parity
/// result can claim that the tail is unchanged from the inspected classifier.
public struct MobileNetV2DerivedArtifactManifest: Codable, Equatable {
    public struct Stem: Codable, Equatable {
        public let path: String
        public let sha256: String
        public let layerCount: Int
        public let input: String
        public let inputShape: [Int]
        public let output: String
        public let shape: [Int]
        public let paddingMode: String
        public let asymmetryMode: String
        public let inputCoordinate: String
    }

    public struct FullArray: Codable, Equatable {
        public let path: String
        public let sha256: String
        public let input: String
        public let inputShape: [Int]
        public let output: String
        public let derivedFromSourceClassifier: Bool
    }

    public struct Tail: Codable, Equatable {
        public let path: String
        public let sha256: String
        public let input: String
        public let shape: [Int]
        public let output: String
        public let sourceLayerStart: Int
        public let preservesSourceClassifier: Bool
    }

    public let schemaVersion: Int
    public let source: String
    public let sourceSha256: String
    public let stem: Stem
    public let fullArray: FullArray
    public let tail: Tail

    public static let arrayInputName = "planefuse_mobilenetv2_normalized_rgb"
    public static let arrayInputShape = [3, 224, 224]

    public static func load(from url: URL) throws -> MobileNetV2DerivedArtifactManifest {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Self.self, from: Data(contentsOf: url))
    }

    public func validate(at root: URL, expectedSourceSHA256: String? = MobileNetV2AssetManifest.inspected.sourceSHA256) throws {
        let files = [(source, sourceSha256), (stem.path, stem.sha256), (fullArray.path, fullArray.sha256), (tail.path, tail.sha256)]
        for (path, expectedHash) in files {
            let url = root.appendingPathComponent(path)
            guard FileManager.default.fileExists(atPath: url.path) else { throw MobileNetV2IntegrationError.modelHashMismatch(url) }
            guard Self.sha256(url) == expectedHash.lowercased() else { throw MobileNetV2IntegrationError.modelHashMismatch(url) }
        }
        guard expectedSourceSHA256 == nil || sourceSha256 == expectedSourceSHA256,
              schemaVersion == 1,
              stem.layerCount == 6,
              stem.input == Self.arrayInputName,
              stem.inputShape == Self.arrayInputShape,
              stem.output == MobileNetV2AssetManifest.inspected.tailInputName,
              stem.shape == MobileNetV2AssetManifest.expectedActivationShape,
              stem.paddingMode == "same_bottom_right",
              stem.asymmetryMode == "BOTTOM_RIGHT_HEAVY",
              stem.inputCoordinate == "2 * output + tap",
              fullArray.derivedFromSourceClassifier,
              fullArray.input == stem.input,
              fullArray.inputShape == stem.inputShape,
              fullArray.output == MobileNetV2AssetManifest.inspected.tailOutputName,
              tail.preservesSourceClassifier,
              tail.sourceLayerStart == stem.layerCount,
              tail.input == stem.output,
              tail.shape == stem.shape,
              tail.output == fullArray.output else { throw MobileNetV2IntegrationError.invalidDerivedManifest }
    }

    private static func sha256(_ url: URL) -> String {
        let digest = SHA256.hash(data: try! Data(contentsOf: url))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

/// Both B and C must call the same implementation with their first activation.
/// It owns no preprocessing and does not claim a GPU/ANE tensor handoff: the
/// `MLMultiArray` construction is an explicit CPU-visible adapter boundary.
public protocol MobileNetV2TailRunning {
    func predict(stemActivation: [Float]) throws -> [String: Double]
}

public final class CoreMLMobileNetV2TailAdapter: MobileNetV2TailRunning {
    private let model: MLModel
    private let inputName: String
    private let outputName: String
    private let activationShape: [NSNumber]
    private let activationCount: Int

    public init(modelURL: URL, manifest: MobileNetV2AssetManifest) throws {
        guard FileManager.default.fileExists(atPath: modelURL.path) else { throw MobileNetV2IntegrationError.tailModelMissing(modelURL) }
        self.model = try MLModel(contentsOf: Self.resolvedModelURL(modelURL))
        let inputs = self.model.modelDescription.inputDescriptionsByName
        guard inputs.count == 1, let input = inputs.first,
              input.value.type == .multiArray else { throw MobileNetV2IntegrationError.ambiguousTailInput }
        // The artifact's input name is authoritative. Preparation tools may rename
        // the boundary, but B and C still use this same loaded tail instance.
        guard input.key == manifest.tailInputName,
              Self.matches(input.value.multiArrayConstraint, shape: manifest.activationShape) else {
            throw MobileNetV2IntegrationError.invalidTailInput(name: input.key, shape: manifest.activationShape)
        }
        self.inputName = manifest.tailInputName
        self.outputName = manifest.tailOutputName
        self.activationShape = manifest.activationShape.map { NSNumber(value: $0) }
        self.activationCount = manifest.activationShape.reduce(1, *)
    }

    public func predict(stemActivation: [Float]) throws -> [String: Double] {
        guard stemActivation.count == activationCount else {
            throw MobileNetV2IntegrationError.invalidActivationCount(expected: activationCount, actual: stemActivation.count)
        }
        let array = try MLMultiArray(shape: activationShape, dataType: .float32)
        for index in 0..<activationCount { array[index] = NSNumber(value: stemActivation[index]) }
        let output = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: [inputName: array]))
        guard let probabilities = output.featureValue(for: outputName)?.dictionaryValue else {
            throw MobileNetV2IntegrationError.unexpectedTailOutput(outputName)
        }
        return probabilities.reduce(into: [:]) { result, entry in
            guard let label = entry.key as? String else { return }
            result[label] = entry.value.doubleValue
        }
    }

    fileprivate static func resolvedModelURL(_ url: URL) -> URL {
        if FileManager.default.fileExists(atPath: url.appendingPathComponent("metadata.json").path) { return url }
        let children = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
        return children.first(where: { $0.pathExtension == "mlmodelc" }) ?? url
    }

    fileprivate static func matches(_ constraint: MLMultiArrayConstraint?, shape: [Int]) -> Bool {
        guard let constraint, constraint.dataType == .float32 else { return false }
        return constraint.shape.map(\.intValue) == shape
    }
}

/// Runs the first six original-derived graph layers after the original image
/// scaler has been replaced by an explicit Float32 CHW [-1, 1] input.
public final class CoreMLMobileNetV2StemArrayAdapter {
    private let model: MLModel
    private let inputName: String
    private let outputName: String

    public init(modelURL: URL, lineage: MobileNetV2DerivedArtifactManifest, computeUnits: MLComputeUnits = .all) throws {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = computeUnits
        self.model = try MLModel(contentsOf: CoreMLMobileNetV2TailAdapter.resolvedModelURL(modelURL), configuration: configuration)
        let inputs = model.modelDescription.inputDescriptionsByName
        guard inputs.count == 1, let input = inputs.first,
              input.key == lineage.stem.input,
              CoreMLMobileNetV2TailAdapter.matches(input.value.multiArrayConstraint, shape: lineage.stem.inputShape) else {
            throw MobileNetV2IntegrationError.invalidStemInput(name: lineage.stem.input, shape: lineage.stem.inputShape)
        }
        guard let output = model.modelDescription.outputDescriptionsByName[lineage.stem.output],
              output.type == .multiArray,
              CoreMLMobileNetV2TailAdapter.matches(output.multiArrayConstraint, shape: lineage.stem.shape) else {
            throw MobileNetV2IntegrationError.invalidStemOutput(name: lineage.stem.output, shape: lineage.stem.shape)
        }
        self.inputName = lineage.stem.input
        self.outputName = lineage.stem.output
    }

    public func predict(normalizedRGB: [Float]) throws -> [Float] {
        let input = try Self.array(normalizedRGB, shape: MobileNetV2DerivedArtifactManifest.arrayInputShape)
        let output = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: [inputName: input]))
        guard let result = output.featureValue(for: outputName)?.multiArrayValue else {
            throw MobileNetV2IntegrationError.invalidStemOutput(name: outputName, shape: MobileNetV2AssetManifest.expectedActivationShape)
        }
        return (0..<MobileNetV2AssetManifest.expectedActivationShape.reduce(1, *)).map { result[$0].floatValue }
    }

    fileprivate static func array(_ values: [Float], shape: [Int]) throws -> MLMultiArray {
        guard values.count == shape.reduce(1, *) else {
            throw MobileNetV2IntegrationError.invalidActivationCount(expected: shape.reduce(1, *), actual: values.count)
        }
        let array = try MLMultiArray(shape: shape.map { NSNumber(value: $0) }, dataType: .float32)
        for index in values.indices { array[index] = NSNumber(value: values[index]) }
        return array
    }
}

/// Full original-derived classifier with the same explicit Float32 CHW input as
/// StemArray. It is used only for independent lineage/parity validation.
public final class CoreMLMobileNetV2FullArrayAdapter {
    private let model: MLModel
    private let inputName: String
    private let outputName: String

    public init(modelURL: URL, lineage: MobileNetV2DerivedArtifactManifest, computeUnits: MLComputeUnits = .all) throws {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = computeUnits
        self.model = try MLModel(contentsOf: CoreMLMobileNetV2TailAdapter.resolvedModelURL(modelURL), configuration: configuration)
        let inputs = model.modelDescription.inputDescriptionsByName
        guard inputs.count == 1, let input = inputs.first,
              input.key == lineage.fullArray.input,
              CoreMLMobileNetV2TailAdapter.matches(input.value.multiArrayConstraint, shape: lineage.fullArray.inputShape) else {
            throw MobileNetV2IntegrationError.invalidStemInput(name: lineage.fullArray.input, shape: lineage.fullArray.inputShape)
        }
        self.inputName = lineage.fullArray.input
        self.outputName = lineage.fullArray.output
    }

    public func predict(normalizedRGB: [Float]) throws -> [String: Double] {
        let input = try CoreMLMobileNetV2StemArrayAdapter.array(normalizedRGB, shape: MobileNetV2DerivedArtifactManifest.arrayInputShape)
        let output = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: [inputName: input]))
        guard let probabilities = output.featureValue(for: outputName)?.dictionaryValue else {
            throw MobileNetV2IntegrationError.unexpectedTailOutput(outputName)
        }
        return probabilities.reduce(into: [:]) { result, entry in
            guard let label = entry.key as? String else { return }
            result[label] = entry.value.doubleValue
        }
    }
}

/// Exact FP32 parameters exported from the inspected source model. No fixture
/// coefficients are accepted for the real M5 stem.
public struct MobileNetV2StemCoefficients: Codable, Equatable {
    public let convolutionWeights: [Double]
    public let batchNormScale: [Double]
    public let batchNormBias: [Double]
    public let batchNormMean: [Double]
    public let batchNormVariance: [Double]
    public let batchNormEpsilon: Double

    public static func load(from url: URL) throws -> MobileNetV2StemCoefficients {
        try JSONDecoder().decode(MobileNetV2StemCoefficients.self, from: Data(contentsOf: url))
    }

    public func makeStem() -> Conv3x3Stride2BatchNormReLU6Stem {
        Conv3x3Stride2BatchNormReLU6Stem(
            outputChannels: 48, convolutionWeights: convolutionWeights,
            convolutionBias: Array(repeating: 0, count: 48), batchNormScale: batchNormScale,
            batchNormBias: batchNormBias, batchNormMean: batchNormMean,
            batchNormVariance: batchNormVariance, batchNormEpsilon: batchNormEpsilon,
            paddingMode: .sameBottomRight
        )
    }
}

public struct MobileNetV2OutputAgreement: Codable, Equatable {
    public let sampleCount: Int
    public let top1Agreement: Double
    public let maxStemAbsoluteError: Double
    public let stemParityThreshold: Double
    public static let requiredTop1Agreement = 0.995
    /// Core ML CPU reference execution and the fused Metal stem can choose
    /// different Float32 accumulation order. This is the contract's reference
    /// math tier; the deployed B/C GPU parity remains at 1e-5.
    public static let referenceStemParityTolerance = 1e-4

    public init(baselineLogits: [[Float]], candidateLogits: [[Float]], maxStemAbsoluteError: Double, stemParityThreshold: Double = Double(FairABCBenchmark.featureParityTolerance)) throws {
        guard !baselineLogits.isEmpty, baselineLogits.count == candidateLogits.count else { throw MobileNetV2IntegrationError.emptyValidation }
        let matches = zip(baselineLogits, candidateLogits).filter { Self.argmax($0) == Self.argmax($1) }.count
        self.sampleCount = baselineLogits.count
        self.top1Agreement = Double(matches) / Double(sampleCount)
        self.maxStemAbsoluteError = maxStemAbsoluteError
        self.stemParityThreshold = stemParityThreshold
    }

    public var passes: Bool { top1Agreement >= Self.requiredTop1Agreement && maxStemAbsoluteError <= stemParityThreshold }

    private static func argmax(_ values: [Float]) -> Int {
        values.enumerated().max { $0.element < $1.element }?.offset ?? -1
    }
}
