import CoreML
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
    public let validationCorpusManifest: String

    /// Core ML neural-network multi-array inputs omit the batch dimension.
    public static let expectedActivationShape = [48, 112, 112]

    public static let inspected = MobileNetV2AssetManifest(
        modelIdentifier: "Apple MobileNetV2 ImageNet",
        sourceURL: URL(string: "https://developer.apple.com/machine-learning/models/?q=MobileNetV2")!,
        sourceModelFile: "MobileNetV2.mlmodel",
        sourceSHA256: "cb5a35f593582232140556bbfa4618e66b37b8ff2fc33ba17db909e1050fd144",
        tailModelDirectory: "MobileNetV2Tail.mlmodelc",
        tailInputName: "planefuse_mobilenetv2_stem_features",
        tailOutputName: "classLabelProbs",
        activationShape: expectedActivationShape,
        validationCorpusManifest: "proof/m5-validation-corpus.json"
    )

    public func validate(at root: URL) throws {
        guard modelIdentifier == "Apple MobileNetV2 ImageNet", activationShape == Self.expectedActivationShape else {
            throw MobileNetV2IntegrationError.unsupportedManifest
        }
        guard !tailInputName.isEmpty, !tailOutputName.isEmpty else { throw MobileNetV2IntegrationError.unsupportedManifest }
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent(validationCorpusManifest).path) else {
            throw MobileNetV2IntegrationError.validationCorpusMissing(root.appendingPathComponent(validationCorpusManifest))
        }
    }
}

public enum MobileNetV2IntegrationError: LocalizedError, Equatable {
    case unsupportedManifest
    case tailModelMissing(URL)
    case validationCorpusMissing(URL)
    case invalidActivationCount(expected: Int, actual: Int)
    case ambiguousTailInput
    case unexpectedTailOutput(String)
    case emptyValidation

    public var errorDescription: String? {
        switch self {
        case .unsupportedManifest: return "The MobileNetV2 manifest does not describe the inspected 224px, 48x112x112 stem boundary."
        case let .tailModelMissing(url): return "Missing extracted MobileNetV2 tail model at \(url.path)."
        case let .validationCorpusMissing(url): return "Missing MobileNetV2 validation corpus manifest at \(url.path)."
        case let .invalidActivationCount(expected, actual): return "Tail activation needs \(expected) Float32 values; received \(actual)."
        case .ambiguousTailInput: return "The tail must expose exactly one Float32 multi-array input for the stem activation."
        case let .unexpectedTailOutput(name): return "The tail output '\(name)' is not the expected classification-probability dictionary."
        case .emptyValidation: return "A MobileNetV2 output-agreement report needs at least one paired sample."
        }
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
        self.inputName = input.key
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

    private static func resolvedModelURL(_ url: URL) -> URL {
        if FileManager.default.fileExists(atPath: url.appendingPathComponent("metadata.json").path) { return url }
        let children = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
        return children.first(where: { $0.pathExtension == "mlmodelc" }) ?? url
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
            batchNormVariance: batchNormVariance, batchNormEpsilon: batchNormEpsilon
        )
    }
}

public struct MobileNetV2OutputAgreement: Codable, Equatable {
    public let sampleCount: Int
    public let top1Agreement: Double
    public let maxStemAbsoluteError: Double
    public let stemParityThreshold: Double
    public static let requiredTop1Agreement = 0.995

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
