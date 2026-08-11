import Foundation
import Metal

/// Output-blind R7 quality evidence for the matched Float32 shared-bridge
/// candidates. This deliberately has no timing loop: it measures B2 and C1
/// outputs over every preselected corpus sample without perturbing the final
/// latency protocol.
public final class MobileNetV2SharedQualityEvidence {
    public struct DeclaredThresholds: Codable, Equatable {
        /// D008: deployed Float32 Metal B/C activation parity.
        public let deployedMetalActivationMaximumAbsoluteError: Double
        /// D011: independent CPU-only source-derived stem reference threshold.
        /// It is recorded here for contract completeness, not re-evaluated by
        /// this B2/C1-only command.
        public let sourceDerivedCPUActivationMaximumAbsoluteError: Double
        /// D009/D011 task-output agreement contract.
        public let taskAgreement: Double
    }

    public struct Sample: Codable, Equatable {
        public let id: String
        public let category: String
        public let corpusKind: String
        public let b2Top1Label: String?
        public let c1Top1Label: String?
        public let b2Top5Labels: [String]
        public let c1Top5Labels: [String]
        public let top1Agreement: Bool
        public let top5SetAgreement: Bool
        public let top5RankingAgreement: Bool
        public let activationMaximumAbsoluteError: Double
        public let activationMeanAbsoluteError: Double
        public let activationCosineSimilarity: Double
        public let probabilityMaximumAbsoluteError: Double
        public let probabilityL1Distance: Double

        public var hasClassificationDisagreement: Bool {
            !top1Agreement || !top5SetAgreement || !top5RankingAgreement
        }
    }

    public struct Summary: Codable, Equatable {
        public let corpusSampleCount: Int
        public let realImageCount: Int
        public let proceduralSampleCount: Int
        public let top1Agreement: Double
        public let top5SetAgreement: Double
        public let top5RankingAgreement: Double
        public let activationMaximumAbsoluteError: Double
        /// Arithmetic mean across every compared Float32 activation element.
        public let activationMeanAbsoluteError: Double
        /// Arithmetic mean of per-sample cosine similarities.
        public let activationMeanCosineSimilarity: Double
        public let activationMinimumCosineSimilarity: Double
        public let probabilityMaximumAbsoluteError: Double
        /// Arithmetic mean of per-sample probability-vector L1 distances.
        public let probabilityMeanL1Distance: Double
        public let classificationDisagreementCount: Int
    }

    public struct ResourceEvidence: Codable, Equatable {
        public let precision: String
        public let b2RGBLogicalPayloadBytes: Int
        public let b2RGBMetalAllocatedBytes: Int
        public let c1RGBLogicalPayloadBytes: Int
        public let c1RGBMetalAllocatedBytes: Int
        public let cpuElementByElementActivationCopyBytes: Int
        public let cpuElementByElementActivationCopyStatus: String
    }

    public struct Measurement: Codable, Equatable {
        public let schemaVersion: Int
        public let comparison: String
        public let outputBlindCorpusSelection: String
        public let requestedCoreMLComputeUnits: String
        public let tailComputeUnitsPolicy: String
        public let deviceName: String
        public let declaredThresholds: DeclaredThresholds
        public let establishedGatesPassed: Bool
        public let summary: Summary
        public let resources: ResourceEvidence
        /// Every classification disagreement, with its manifest-derived
        /// category and both label/ranking views. Per-sample numeric evidence
        /// remains available for all corpus samples in `samples`.
        public let disagreements: [Sample]
        public let samples: [Sample]
        public let limitations: [String]
    }

    public enum Error: Swift.Error, LocalizedError, Equatable {
        case noDevice
        case unmatchedTailComputeUnitsPolicy(String)
        case invalidCorpusComposition(total: Int, real: Int, procedural: Int)
        case activationParityFailed(maximumAbsoluteError: Double)
        case outputAgreementFailed(agreement: Double)

        public var errorDescription: String? {
            switch self {
            case .noDevice:
                return "No Metal device is available for R7 B2/C1 quality evidence."
            case let .unmatchedTailComputeUnitsPolicy(policy):
                return "R7 B2/C1 quality evidence requires explicitly configured MLComputeUnits.all; received \(policy)."
            case let .invalidCorpusComposition(total, real, procedural):
                return "R7 B2/C1 quality evidence requires the fixed 64-input corpus (32 real, 32 procedural); received \(total) total, \(real) real, \(procedural) procedural."
            case let .activationParityFailed(maximumAbsoluteError):
                return "B2/C1 activation parity failed with max error \(maximumAbsoluteError)."
            case let .outputAgreementFailed(agreement):
                return "B2/C1 task agreement was \(agreement), below the established threshold."
            }
        }
    }

    private let coefficients: MobileNetV2StemCoefficients
    private let tail: CoreMLMobileNetV2TailAdapter
    private let corpus: MobileNetV2Corpus

    public init(coefficientsURL: URL, tail: CoreMLMobileNetV2TailAdapter, corpus: MobileNetV2Corpus) throws {
        guard tail.computeUnitsPolicyLabel == "all" else {
            throw Error.unmatchedTailComputeUnitsPolicy(tail.computeUnitsPolicyLabel)
        }
        self.coefficients = try MobileNetV2StemCoefficients.load(from: coefficientsURL)
        self.tail = tail
        self.corpus = corpus
    }

    public func run(device: MTLDevice? = MTLCreateSystemDefaultDevice()) throws -> Measurement {
        guard let device else { throw Error.noDevice }
        let frames = try corpus.loadFrames()
        let descriptors = corpus.manifest.samples
        let classifications = descriptors.map(Self.classification(for:))
        let realCount = classifications.filter { $0.kind == "real" }.count
        let proceduralCount = classifications.filter { $0.kind == "procedural" }.count
        guard frames.count == descriptors.count,
              frames.count == 64,
              realCount == 32,
              proceduralCount == 32 else {
            throw Error.invalidCorpusComposition(total: frames.count, real: realCount, procedural: proceduralCount)
        }

        let inputFactory = try MetalRGBBaseline(device: device)
        let b2 = try MetalMobileNetV2RGBPipeline(device: device, coefficients: coefficients)
        let c1 = try MetalMobileNetV2NativeStem(device: device, coefficients: coefficients)
        let inputs = try frames.map {
            try inputFactory.makeNV12Textures(
                width: MobileNetV2Corpus.inputWidth,
                height: MobileNetV2Corpus.inputHeight,
                yPlaneBytes: $0.yPlaneBytes,
                uvPlaneBytes: $0.uvPlaneBytes
            )
        }
        let b2NormalizedRGB = try b2.makeNormalizedRGBCHWBuffer()
        let b2Activation = try b2.makeActivationBuffer()
        let c1Activation = try c1.makeActivationBuffer()
        let b2SharedActivation = try BufferBackedMultiArray(buffer: b2Activation, shape: MetalMobileNetV2NativeStem.activationShape)
        let c1SharedActivation = try BufferBackedMultiArray(buffer: c1Activation, shape: MetalMobileNetV2NativeStem.activationShape)

        var samples: [Sample] = []
        samples.reserveCapacity(frames.count)
        for index in frames.indices {
            try b2.executeCHW(inputs[index], normalizedRGB: b2NormalizedRGB, into: b2Activation)
            let b2Probabilities = try tail.predict(sharedActivation: b2SharedActivation)
            let b2ActivationValues = try b2.readActivation(from: b2Activation)

            try c1.execute(inputs[index], into: c1Activation)
            let c1Probabilities = try tail.predict(sharedActivation: c1SharedActivation)
            let c1ActivationValues = try c1.readActivation(from: c1Activation)

            samples.append(Self.compare(
                id: frames[index].id,
                category: classifications[index].category,
                corpusKind: classifications[index].kind,
                b2Activation: b2ActivationValues,
                c1Activation: c1ActivationValues,
                b2Probabilities: b2Probabilities,
                c1Probabilities: c1Probabilities
            ))
        }

        let summary = Self.summarize(samples, realImageCount: realCount, proceduralSampleCount: proceduralCount)
        let thresholds = DeclaredThresholds(
            deployedMetalActivationMaximumAbsoluteError: Double(FairABCBenchmark.featureParityTolerance),
            sourceDerivedCPUActivationMaximumAbsoluteError: MobileNetV2OutputAgreement.referenceStemParityTolerance,
            taskAgreement: MobileNetV2OutputAgreement.requiredTop1Agreement
        )
        guard summary.activationMaximumAbsoluteError <= thresholds.deployedMetalActivationMaximumAbsoluteError else {
            throw Error.activationParityFailed(maximumAbsoluteError: summary.activationMaximumAbsoluteError)
        }
        guard summary.top1Agreement >= thresholds.taskAgreement else {
            throw Error.outputAgreementFailed(agreement: summary.top1Agreement)
        }

        return Measurement(
            schemaVersion: 1,
            comparison: "B2 shared Float32 CHW materialized-RGB stem versus C1 shared Float32 native-plane stem; same persistent buffer-backed MLMultiArray tail adapter.",
            outputBlindCorpusSelection: "All 64 samples from proof/m5-validation-corpus.json are evaluated once in manifest order. Sample inclusion, real/procedural classification, and category are determined before inference from manifest metadata or the fixed stress-* procedural namespace; no model output affects selection.",
            requestedCoreMLComputeUnits: "MLComputeUnits.all",
            tailComputeUnitsPolicy: tail.computeUnitsPolicyLabel,
            deviceName: device.name,
            declaredThresholds: thresholds,
            establishedGatesPassed: true,
            summary: summary,
            resources: ResourceEvidence(
                precision: "Float32 activations; B2 materializes normalized RGB as Float32 CHW; C1 has no full RGB resource.",
                b2RGBLogicalPayloadBytes: MobileNetV2Corpus.inputWidth * MobileNetV2Corpus.inputHeight * 3 * MemoryLayout<Float>.stride,
                b2RGBMetalAllocatedBytes: b2NormalizedRGB.allocatedSize,
                c1RGBLogicalPayloadBytes: 0,
                c1RGBMetalAllocatedBytes: 0,
                cpuElementByElementActivationCopyBytes: 0,
                cpuElementByElementActivationCopyStatus: "none; both B2 and C1 pass persistent shared Metal activation buffers through BufferBackedMultiArray, with no PlaneFuse CPU element-by-element activation population. Core ML internal-copy behavior is not measured by this artifact."
            ),
            disagreements: samples.filter(\.hasClassificationDisagreement),
            samples: samples,
            limitations: [
                "This command measures B2/C1 activation and classification outputs, not source-model lineage or the CPU-only source-derived stem threshold; that threshold is recorded without claiming it was remeasured.",
                "MLComputeUnits.all is the explicit requested Core ML policy. Core ML runtime hardware placement and any internal copy are not observable through this adapter and are not inferred."
            ]
        )
    }

    /// Public pure comparison helper for focused metric tests. Both activation
    /// arrays and probability dictionaries are actual candidate outputs when
    /// invoked by `run`.
    public static func compare(
        id: String,
        category: String,
        corpusKind: String,
        b2Activation: [Float],
        c1Activation: [Float],
        b2Probabilities: [String: Double],
        c1Probabilities: [String: Double]
    ) -> Sample {
        precondition(b2Activation.count == c1Activation.count && !b2Activation.isEmpty, "B2/C1 activation shape mismatch")
        let b2Top5 = topLabels(b2Probabilities, count: 5)
        let c1Top5 = topLabels(c1Probabilities, count: 5)
        var activationMax = 0.0
        var activationTotal = 0.0
        var dot = 0.0
        var b2NormSquared = 0.0
        var c1NormSquared = 0.0
        for (b2Value, c1Value) in zip(b2Activation, c1Activation) {
            let b2Double = Double(b2Value)
            let c1Double = Double(c1Value)
            let error = abs(b2Double - c1Double)
            activationMax = max(activationMax, error)
            activationTotal += error
            dot += b2Double * c1Double
            b2NormSquared += b2Double * b2Double
            c1NormSquared += c1Double * c1Double
        }
        let labels = Set(b2Probabilities.keys).union(c1Probabilities.keys)
        let probabilityMaximum = labels.map { abs((b2Probabilities[$0] ?? 0) - (c1Probabilities[$0] ?? 0)) }.max() ?? 0
        let probabilityL1 = labels.reduce(0.0) { $0 + abs((b2Probabilities[$1] ?? 0) - (c1Probabilities[$1] ?? 0)) }
        let denominator = sqrt(b2NormSquared) * sqrt(c1NormSquared)
        let cosine = denominator == 0 ? (b2NormSquared == c1NormSquared ? 1.0 : 0.0) : dot / denominator
        return Sample(
            id: id,
            category: category,
            corpusKind: corpusKind,
            b2Top1Label: b2Top5.first,
            c1Top1Label: c1Top5.first,
            b2Top5Labels: b2Top5,
            c1Top5Labels: c1Top5,
            top1Agreement: b2Top5.first == c1Top5.first,
            top5SetAgreement: Set(b2Top5) == Set(c1Top5),
            top5RankingAgreement: b2Top5 == c1Top5,
            activationMaximumAbsoluteError: activationMax,
            activationMeanAbsoluteError: activationTotal / Double(b2Activation.count),
            activationCosineSimilarity: cosine,
            probabilityMaximumAbsoluteError: probabilityMaximum,
            probabilityL1Distance: probabilityL1
        )
    }

    private static func summarize(_ samples: [Sample], realImageCount: Int, proceduralSampleCount: Int) -> Summary {
        precondition(!samples.isEmpty)
        return Summary(
            corpusSampleCount: samples.count,
            realImageCount: realImageCount,
            proceduralSampleCount: proceduralSampleCount,
            top1Agreement: Double(samples.filter(\.top1Agreement).count) / Double(samples.count),
            top5SetAgreement: Double(samples.filter(\.top5SetAgreement).count) / Double(samples.count),
            top5RankingAgreement: Double(samples.filter(\.top5RankingAgreement).count) / Double(samples.count),
            activationMaximumAbsoluteError: samples.map(\.activationMaximumAbsoluteError).max() ?? 0,
            activationMeanAbsoluteError: samples.map(\.activationMeanAbsoluteError).reduce(0, +) / Double(samples.count),
            activationMeanCosineSimilarity: samples.map(\.activationCosineSimilarity).reduce(0, +) / Double(samples.count),
            activationMinimumCosineSimilarity: samples.map(\.activationCosineSimilarity).min() ?? 0,
            probabilityMaximumAbsoluteError: samples.map(\.probabilityMaximumAbsoluteError).max() ?? 0,
            probabilityMeanL1Distance: samples.map(\.probabilityL1Distance).reduce(0, +) / Double(samples.count),
            classificationDisagreementCount: samples.filter(\.hasClassificationDisagreement).count
        )
    }

    private static func topLabels(_ probabilities: [String: Double], count: Int) -> [String] {
        probabilities.sorted { lhs, rhs in
            lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
        }.prefix(count).map(\.key)
    }

    private static func classification(for sample: MobileNetV2CorpusManifest.Sample) -> (kind: String, category: String) {
        let kind = sample.kind ?? (sample.id.hasPrefix("stress-") ? "procedural" : "unclassified")
        let category = sample.bucket ?? (kind == "procedural" ? "procedural-stress" : "unclassified")
        return (kind, category)
    }
}
