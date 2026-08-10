import Foundation
import Metal

/// Direct final-protocol comparison of the strongest materialized-RGB B2 path
/// and native-plane C1 path. Both candidates write a Float32 activation into a
/// persistent shared Metal buffer and invoke the same caller-owned Core ML tail
/// through a persistent `BufferBackedMultiArray` view.
public final class MobileNetV2DirectSharedBenchmark {
    public struct Configuration: Codable, Equatable {
        public let warmupIterations: Int
        /// Fixed by the preregistered final hierarchical-bootstrap protocol.
        public let measuredPairsPerBatch: Int
        /// Fixed by the preregistered final hierarchical-bootstrap protocol.
        public let batchCount: Int
        /// Zero means every frame in the supplied corpus.
        public let validationSamples: Int

        public init(warmupIterations: Int = 20, validationSamples: Int = 0) throws {
            guard warmupIterations >= 20, validationSamples >= 0 else {
                throw Error.invalidConfiguration
            }
            self.warmupIterations = warmupIterations
            self.measuredPairsPerBatch = BenchmarkStatistics.bootstrapPairsPerBatch
            self.batchCount = BenchmarkStatistics.bootstrapBatchCount
            self.validationSamples = validationSamples
        }

        private enum CodingKeys: String, CodingKey {
            case warmupIterations
            case measuredPairsPerBatch
            case batchCount
            case validationSamples
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let warmupIterations = try container.decode(Int.self, forKey: .warmupIterations)
            let measuredPairsPerBatch = try container.decode(Int.self, forKey: .measuredPairsPerBatch)
            let batchCount = try container.decode(Int.self, forKey: .batchCount)
            let validationSamples = try container.decode(Int.self, forKey: .validationSamples)
            guard measuredPairsPerBatch == BenchmarkStatistics.bootstrapPairsPerBatch,
                  batchCount == BenchmarkStatistics.bootstrapBatchCount else {
                throw DecodingError.dataCorruptedError(
                    forKey: measuredPairsPerBatch == BenchmarkStatistics.bootstrapPairsPerBatch ? .batchCount : .measuredPairsPerBatch,
                    in: container,
                    debugDescription: "MobileNetV2DirectSharedBenchmark always uses exactly \(BenchmarkStatistics.bootstrapBatchCount) batches of \(BenchmarkStatistics.bootstrapPairsPerBatch) pairs."
                )
            }
            try self.init(warmupIterations: warmupIterations, validationSamples: validationSamples)
        }
    }

    public struct RawPairRecord: Codable, Equatable {
        public let batchID: String
        public let frameIndex: Int
        public let sourceSampleID: String
        /// `B2_then_C1` or `C1_then_B2`; alternated in global pair order.
        public let executionOrder: String
        public let b2Milliseconds: Double
        public let c1Milliseconds: Double
        /// Direct B2-minus-C1 latency. Positive values favor C1.
        public let b2MinusC1Milliseconds: Double

        public init(
            batchID: String,
            frameIndex: Int,
            sourceSampleID: String,
            executionOrder: String,
            b2Milliseconds: Double,
            c1Milliseconds: Double
        ) {
            self.batchID = batchID
            self.frameIndex = frameIndex
            self.sourceSampleID = sourceSampleID
            self.executionOrder = executionOrder
            self.b2Milliseconds = b2Milliseconds
            self.c1Milliseconds = c1Milliseconds
            self.b2MinusC1Milliseconds = b2Milliseconds - c1Milliseconds
        }
    }

    public struct Measurement: Codable, Equatable {
        public let schemaVersion: Int
        public let configuration: Configuration
        public let rawPairedRecords: [RawPairRecord]
        public let batchDifferences: [BenchmarkStatistics.PairedBatch]
        public let pairedBootstrapConfidenceInterval: BenchmarkStatistics.PairedBootstrapResult
        public let b2Statistics: BenchmarkStatistics.Summary
        public let c1Statistics: BenchmarkStatistics.Summary
        public let b2MinusC1Statistics: BenchmarkStatistics.Summary
        /// Positive means C1 has a lower p50 than B2.
        public let aggregatePercentage: Double
        public let activationMaxAbsoluteError: Double
        public let top1Agreement: Double
        public let b2RGBLogicalBytes: Int
        public let b2RGBAllocatedBytes: Int
        public let c1RGBLogicalBytes: Int
        public let c1RGBAllocatedBytes: Int
        /// No B2/C1 measured-path activation element is copied through Swift.
        public let cpuElementByElementActivationCopyBytes: Int
        public let cpuElementByElementActivationCopyStatus: String
        public let deviceName: String
        public let computeUnitsPolicy: String
        public let sourceSampleIDs: [String]
        public let validationSampleCount: Int
        public let statisticsAlgorithmVersion: String
        public let bootstrapSeed: UInt64
        public let bootstrapReplicateCount: Int
        public let bootstrapBatchCount: Int
        public let bootstrapPairsPerBatch: Int
        public let bootstrapBlockSize: Int
    }

    public enum Error: Swift.Error, LocalizedError, Equatable {
        case noDevice
        case invalidConfiguration
        case invalidValidationSampleCount(requested: Int, available: Int)
        case unmatchedTailComputeUnitsPolicy(String)
        case activationParityFailed(maxError: Double)
        case outputAgreementFailed(agreement: Double)

        public var errorDescription: String? {
            switch self {
            case .noDevice:
                return "No Metal device is available for the direct B2/C1 shared benchmark."
            case .invalidConfiguration:
                return "Direct B2/C1 shared benchmarking requires at least 20 warmups and a nonnegative validation count."
            case let .invalidValidationSampleCount(requested, available):
                return "Requested \(requested) validation samples, but the corpus has \(available)."
            case let .unmatchedTailComputeUnitsPolicy(policy):
                return "Direct B2/C1 shared benchmarking requires the same Core ML .all policy; received \(policy)."
            case let .activationParityFailed(maxError):
                return "B2/C1 activation parity failed with max error \(maxError)."
            case let .outputAgreementFailed(agreement):
                return "B2/C1 top-1 agreement was \(agreement), below the established threshold."
            }
        }
    }

    private let configuration: Configuration
    private let coefficients: MobileNetV2StemCoefficients
    /// The concrete adapter is also a `MobileNetV2TailRunning` implementation;
    /// this direct benchmark deliberately uses only its shared-activation API.
    private let tail: CoreMLMobileNetV2TailAdapter
    private let corpus: MobileNetV2Corpus

    public init(
        configuration: Configuration,
        coefficientsURL: URL,
        tail: CoreMLMobileNetV2TailAdapter,
        corpus: MobileNetV2Corpus
    ) throws {
        guard tail.computeUnitsPolicyLabel == "all" else {
            throw Error.unmatchedTailComputeUnitsPolicy(tail.computeUnitsPolicyLabel)
        }
        self.configuration = configuration
        self.coefficients = try MobileNetV2StemCoefficients.load(from: coefficientsURL)
        self.tail = tail
        self.corpus = corpus
    }

    public func run(device: MTLDevice? = MTLCreateSystemDefaultDevice()) throws -> Measurement {
        guard let device else { throw Error.noDevice }

        let frames = try corpus.loadFrames()
        let validationCount = configuration.validationSamples == 0 ? frames.count : configuration.validationSamples
        guard validationCount > 0, validationCount <= frames.count else {
            throw Error.invalidValidationSampleCount(requested: validationCount, available: frames.count)
        }

        let inputFactory = try MetalRGBBaseline(device: device)
        let b2 = try MetalMobileNetV2RGBPipeline(device: device, coefficients: coefficients)
        let c1 = try MetalMobileNetV2NativeStem(device: device, coefficients: coefficients)

        // Allocate every resource, including one texture pair per corpus frame,
        // before validation, warmup, or measured candidate timing begins.
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
        let b2SharedActivation = try BufferBackedMultiArray(
            buffer: b2Activation,
            shape: MetalMobileNetV2NativeStem.activationShape
        )
        let c1SharedActivation = try BufferBackedMultiArray(
            buffer: c1Activation,
            shape: MetalMobileNetV2NativeStem.activationShape
        )

        let quality = try validateParity(
            frames: Array(frames.prefix(validationCount)),
            inputs: Array(inputs.prefix(validationCount)),
            b2: b2,
            c1: c1,
            b2NormalizedRGB: b2NormalizedRGB,
            b2Activation: b2Activation,
            c1Activation: c1Activation,
            b2SharedActivation: b2SharedActivation,
            c1SharedActivation: c1SharedActivation
        )

        for warmupIndex in 0..<configuration.warmupIterations {
            let frameIndex = warmupIndex % frames.count
            if warmupIndex.isMultiple(of: 2) {
                _ = try executeB2(b2, input: inputs[frameIndex], normalizedRGB: b2NormalizedRGB, activation: b2Activation, sharedActivation: b2SharedActivation)
                _ = try executeC1(c1, input: inputs[frameIndex], activation: c1Activation, sharedActivation: c1SharedActivation)
            } else {
                _ = try executeC1(c1, input: inputs[frameIndex], activation: c1Activation, sharedActivation: c1SharedActivation)
                _ = try executeB2(b2, input: inputs[frameIndex], normalizedRGB: b2NormalizedRGB, activation: b2Activation, sharedActivation: b2SharedActivation)
            }
        }

        let totalPairs = configuration.batchCount * configuration.measuredPairsPerBatch
        var rawPairedRecords: [RawPairRecord] = []
        var batchDifferences: [BenchmarkStatistics.PairedBatch] = []
        rawPairedRecords.reserveCapacity(totalPairs)
        batchDifferences.reserveCapacity(configuration.batchCount)

        for batchIndex in 0..<configuration.batchCount {
            let batchID = "batch-\(batchIndex)"
            var differences: [Double] = []
            differences.reserveCapacity(configuration.measuredPairsPerBatch)
            for pairIndex in 0..<configuration.measuredPairsPerBatch {
                let globalPairIndex = batchIndex * configuration.measuredPairsPerBatch + pairIndex
                let frameIndex = globalPairIndex % frames.count
                let b2First = globalPairIndex.isMultiple(of: 2)
                let b2Result: TimedResult
                let c1Result: TimedResult
                if b2First {
                    b2Result = try executeB2(b2, input: inputs[frameIndex], normalizedRGB: b2NormalizedRGB, activation: b2Activation, sharedActivation: b2SharedActivation)
                    c1Result = try executeC1(c1, input: inputs[frameIndex], activation: c1Activation, sharedActivation: c1SharedActivation)
                } else {
                    c1Result = try executeC1(c1, input: inputs[frameIndex], activation: c1Activation, sharedActivation: c1SharedActivation)
                    b2Result = try executeB2(b2, input: inputs[frameIndex], normalizedRGB: b2NormalizedRGB, activation: b2Activation, sharedActivation: b2SharedActivation)
                }
                let record = RawPairRecord(
                    batchID: batchID,
                    frameIndex: frameIndex,
                    sourceSampleID: frames[frameIndex].id,
                    executionOrder: b2First ? "B2_then_C1" : "C1_then_B2",
                    b2Milliseconds: b2Result.milliseconds,
                    c1Milliseconds: c1Result.milliseconds
                )
                rawPairedRecords.append(record)
                differences.append(record.b2MinusC1Milliseconds)
            }
            batchDifferences.append(BenchmarkStatistics.PairedBatch(batchID: batchID, differences: differences))
        }

        let b2Samples = rawPairedRecords.map(\.b2Milliseconds)
        let c1Samples = rawPairedRecords.map(\.c1Milliseconds)
        let differenceSamples = rawPairedRecords.map(\.b2MinusC1Milliseconds)
        return try Measurement(
            schemaVersion: 1,
            configuration: configuration,
            rawPairedRecords: rawPairedRecords,
            batchDifferences: batchDifferences,
            pairedBootstrapConfidenceInterval: BenchmarkStatistics.pairedBlockBootstrap(batchDifferences),
            b2Statistics: BenchmarkStatistics.summary(b2Samples),
            c1Statistics: BenchmarkStatistics.summary(c1Samples),
            b2MinusC1Statistics: BenchmarkStatistics.summary(differenceSamples),
            aggregatePercentage: BenchmarkStatistics.aggregatePercentage(pipelineB: b2Samples, pipelineC: c1Samples),
            activationMaxAbsoluteError: quality.maxActivationAbsoluteError,
            top1Agreement: quality.top1Agreement,
            b2RGBLogicalBytes: MobileNetV2Corpus.inputWidth * MobileNetV2Corpus.inputHeight * 3 * MemoryLayout<Float>.stride,
            b2RGBAllocatedBytes: b2NormalizedRGB.allocatedSize,
            c1RGBLogicalBytes: 0,
            c1RGBAllocatedBytes: 0,
            cpuElementByElementActivationCopyBytes: 0,
            cpuElementByElementActivationCopyStatus: "none; B2/C1 measured path uses persistent buffer-backed MLMultiArray views",
            deviceName: device.name,
            computeUnitsPolicy: tail.computeUnitsPolicyLabel,
            sourceSampleIDs: frames.map(\.id),
            validationSampleCount: validationCount,
            statisticsAlgorithmVersion: BenchmarkStatistics.algorithmVersion,
            bootstrapSeed: BenchmarkStatistics.bootstrapSeed,
            bootstrapReplicateCount: BenchmarkStatistics.bootstrapReplicateCount,
            bootstrapBatchCount: BenchmarkStatistics.bootstrapBatchCount,
            bootstrapPairsPerBatch: BenchmarkStatistics.bootstrapPairsPerBatch,
            bootstrapBlockSize: BenchmarkStatistics.bootstrapBlockSize
        )
    }

    private struct TimedResult {
        let milliseconds: Double
        let probabilities: [String: Double]
    }

    private struct QualityResult {
        let maxActivationAbsoluteError: Double
        let top1Agreement: Double
    }

    /// Candidate timing starts immediately before its own stem submission and
    /// ends after this candidate's tail result, never including predecessor work.
    private func executeB2(
        _ b2: MetalMobileNetV2RGBPipeline,
        input: MetalRGBBaseline.NV12Textures,
        normalizedRGB: MTLBuffer,
        activation: MTLBuffer,
        sharedActivation: BufferBackedMultiArray
    ) throws -> TimedResult {
        let start = ProcessInfo.processInfo.systemUptime
        try b2.executeCHW(input, normalizedRGB: normalizedRGB, into: activation)
        let probabilities = try tail.predict(sharedActivation: sharedActivation)
        return TimedResult(
            milliseconds: (ProcessInfo.processInfo.systemUptime - start) * 1_000,
            probabilities: probabilities
        )
    }

    /// Candidate timing starts immediately before its own stem submission and
    /// ends after this candidate's tail result, never including predecessor work.
    private func executeC1(
        _ c1: MetalMobileNetV2NativeStem,
        input: MetalRGBBaseline.NV12Textures,
        activation: MTLBuffer,
        sharedActivation: BufferBackedMultiArray
    ) throws -> TimedResult {
        let start = ProcessInfo.processInfo.systemUptime
        try c1.execute(input, into: activation)
        let probabilities = try tail.predict(sharedActivation: sharedActivation)
        return TimedResult(
            milliseconds: (ProcessInfo.processInfo.systemUptime - start) * 1_000,
            probabilities: probabilities
        )
    }

    private func validateParity(
        frames: [MobileNetV2CorpusFrame],
        inputs: [MetalRGBBaseline.NV12Textures],
        b2: MetalMobileNetV2RGBPipeline,
        c1: MetalMobileNetV2NativeStem,
        b2NormalizedRGB: MTLBuffer,
        b2Activation: MTLBuffer,
        c1Activation: MTLBuffer,
        b2SharedActivation: BufferBackedMultiArray,
        c1SharedActivation: BufferBackedMultiArray
    ) throws -> QualityResult {
        var top1Matches = 0
        var maxActivationAbsoluteError = 0.0
        for index in frames.indices {
            try b2.executeCHW(inputs[index], normalizedRGB: b2NormalizedRGB, into: b2Activation)
            let b2Output = try tail.predict(sharedActivation: b2SharedActivation)
            try c1.execute(inputs[index], into: c1Activation)
            let c1Output = try tail.predict(sharedActivation: c1SharedActivation)
            if Self.topLabel(b2Output) == Self.topLabel(c1Output) { top1Matches += 1 }

            // Validation is deliberately outside the candidate timing region.
            let b2Features = try b2.readActivation(from: b2Activation)
            let c1Features = try c1.readActivation(from: c1Activation)
            let frameError = zip(b2Features, c1Features).map { abs(Double($0 - $1)) }.max() ?? 0
            maxActivationAbsoluteError = max(maxActivationAbsoluteError, frameError)
        }
        let agreement = Double(top1Matches) / Double(frames.count)
        guard maxActivationAbsoluteError <= Double(FairABCBenchmark.featureParityTolerance) else {
            throw Error.activationParityFailed(maxError: maxActivationAbsoluteError)
        }
        guard agreement >= MobileNetV2OutputAgreement.requiredTop1Agreement else {
            throw Error.outputAgreementFailed(agreement: agreement)
        }
        return QualityResult(maxActivationAbsoluteError: maxActivationAbsoluteError, top1Agreement: agreement)
    }

    private static func topLabel(_ probabilities: [String: Double]) -> String? {
        probabilities.max { lhs, rhs in
            lhs.value == rhs.value ? lhs.key > rhs.key : lhs.value < rhs.value
        }?.key
    }
}
