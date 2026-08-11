import Foundation
import Metal

/// One independently launched batch of the repaired R7 B2/C1 protocol.
/// The final protocol orchestrator launches this type once per process so
/// initialization and warmup are batch-local rather than labels on one run.
public final class MobileNetV2DirectSharedBatchBenchmark {
    public typealias RawPairRecord = MobileNetV2DirectSharedBenchmark.RawPairRecord

    public struct Configuration: Codable, Equatable {
        public let warmupIterations: Int
        public let measuredPairs: Int
        public let batchIndex: Int
        public let sourceOffset: Int
        public let orderPhase: Int

        public init(
            warmupIterations: Int = 20,
            measuredPairs: Int = BenchmarkStatistics.bootstrapPairsPerBatch,
            batchIndex: Int,
            sourceOffset: Int,
            orderPhase: Int
        ) throws {
            guard warmupIterations >= 20,
                  measuredPairs == BenchmarkStatistics.bootstrapPairsPerBatch,
                  batchIndex >= 0,
                  sourceOffset >= 0,
                  orderPhase == 0 || orderPhase == 1 else {
                throw Error.invalidConfiguration
            }
            self.warmupIterations = warmupIterations
            self.measuredPairs = measuredPairs
            self.batchIndex = batchIndex
            self.sourceOffset = sourceOffset
            self.orderPhase = orderPhase
        }
    }

    public struct Measurement: Codable, Equatable {
        public let schemaVersion: Int
        public let status: String
        public let configuration: Configuration
        public let rawPairedRecords: [RawPairRecord]
        public let activationMaxAbsoluteError: Double
        public let top1Agreement: Double
        public let b2RGBLogicalBytes: Int
        public let b2RGBAllocatedBytes: Int
        public let c1RGBLogicalBytes: Int
        public let c1RGBAllocatedBytes: Int
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

        public init(
            configuration: Configuration,
            rawPairedRecords: [RawPairRecord],
            activationMaxAbsoluteError: Double,
            top1Agreement: Double,
            b2RGBLogicalBytes: Int,
            b2RGBAllocatedBytes: Int,
            deviceName: String,
            computeUnitsPolicy: String,
            sourceSampleIDs: [String]
        ) {
            self.schemaVersion = 1
            self.status = "mobilenetv2_direct_b2_c1_shared_batch"
            self.configuration = configuration
            self.rawPairedRecords = rawPairedRecords
            self.activationMaxAbsoluteError = activationMaxAbsoluteError
            self.top1Agreement = top1Agreement
            self.b2RGBLogicalBytes = b2RGBLogicalBytes
            self.b2RGBAllocatedBytes = b2RGBAllocatedBytes
            self.c1RGBLogicalBytes = 0
            self.c1RGBAllocatedBytes = 0
            self.cpuElementByElementActivationCopyBytes = 0
            self.cpuElementByElementActivationCopyStatus = "none; persistent buffer-backed MLMultiArray views"
            self.deviceName = deviceName
            self.computeUnitsPolicy = computeUnitsPolicy
            self.sourceSampleIDs = sourceSampleIDs
            self.validationSampleCount = sourceSampleIDs.count
            self.statisticsAlgorithmVersion = BenchmarkStatistics.algorithmVersion
            self.bootstrapSeed = BenchmarkStatistics.bootstrapSeed
            self.bootstrapReplicateCount = BenchmarkStatistics.bootstrapReplicateCount
            self.bootstrapBatchCount = BenchmarkStatistics.bootstrapBatchCount
            self.bootstrapPairsPerBatch = BenchmarkStatistics.bootstrapPairsPerBatch
            self.bootstrapBlockSize = BenchmarkStatistics.bootstrapBlockSize
        }
    }

    public enum Error: Swift.Error, LocalizedError, Equatable {
        case noDevice
        case invalidConfiguration
        case invalidCorpus
        case activationParityFailed(Double)
        case outputAgreementFailed(Double)

        public var errorDescription: String? {
            switch self {
            case .noDevice: return "No Metal device is available for the repaired direct shared batch."
            case .invalidConfiguration: return "The repaired R7 batch requires 20+ warmups, exactly 200 pairs, and binary order phase."
            case .invalidCorpus: return "The repaired R7 batch requires a non-empty 64-input corpus."
            case let .activationParityFailed(error): return "B2/C1 activation parity failed with max error \(error)."
            case let .outputAgreementFailed(agreement): return "B2/C1 top-1 agreement failed with \(agreement)."
            }
        }
    }

    private let configuration: Configuration
    private let coefficients: MobileNetV2StemCoefficients
    private let tail: CoreMLMobileNetV2TailAdapter
    private let corpus: MobileNetV2Corpus

    public init(
        configuration: Configuration,
        coefficientsURL: URL,
        tail: CoreMLMobileNetV2TailAdapter,
        corpus: MobileNetV2Corpus
    ) throws {
        guard tail.computeUnitsPolicyLabel == "all" else { throw Error.invalidConfiguration }
        self.configuration = configuration
        self.coefficients = try MobileNetV2StemCoefficients.load(from: coefficientsURL)
        self.tail = tail
        self.corpus = corpus
    }

    public func run(device: MTLDevice? = MTLCreateSystemDefaultDevice()) throws -> Measurement {
        guard let device else { throw Error.noDevice }
        let frames = try corpus.loadFrames()
        guard frames.count == 64 else { throw Error.invalidCorpus }

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

        var top1Matches = 0
        var maxActivationError = 0.0
        for index in frames.indices {
            try b2.executeCHW(inputs[index], normalizedRGB: b2NormalizedRGB, into: b2Activation)
            let b2Output = try tail.predict(sharedActivation: b2SharedActivation)
            try c1.execute(inputs[index], into: c1Activation)
            let c1Output = try tail.predict(sharedActivation: c1SharedActivation)
            if Self.topLabel(b2Output) == Self.topLabel(c1Output) { top1Matches += 1 }
            let b2Features = try b2.readActivation(from: b2Activation)
            let c1Features = try c1.readActivation(from: c1Activation)
            maxActivationError = max(maxActivationError, zip(b2Features, c1Features).map { abs(Double($0 - $1)) }.max() ?? 0)
        }
        let top1Agreement = Double(top1Matches) / Double(frames.count)
        guard maxActivationError <= Double(FairABCBenchmark.featureParityTolerance) else { throw Error.activationParityFailed(maxActivationError) }
        guard top1Agreement >= MobileNetV2OutputAgreement.requiredTop1Agreement else { throw Error.outputAgreementFailed(top1Agreement) }

        // This warmup is inside the independently launched batch process.
        for warmupIndex in 0..<configuration.warmupIterations {
            let frameIndex = (configuration.sourceOffset + warmupIndex) % frames.count
            if ((warmupIndex + configuration.orderPhase) % 2) == 0 {
                _ = try executeB2(b2, input: inputs[frameIndex], normalizedRGB: b2NormalizedRGB, activation: b2Activation, sharedActivation: b2SharedActivation)
                _ = try executeC1(c1, input: inputs[frameIndex], activation: c1Activation, sharedActivation: c1SharedActivation)
            } else {
                _ = try executeC1(c1, input: inputs[frameIndex], activation: c1Activation, sharedActivation: c1SharedActivation)
                _ = try executeB2(b2, input: inputs[frameIndex], normalizedRGB: b2NormalizedRGB, activation: b2Activation, sharedActivation: b2SharedActivation)
            }
        }

        var records: [RawPairRecord] = []
        records.reserveCapacity(configuration.measuredPairs)
        for pairIndex in 0..<configuration.measuredPairs {
            let frameIndex = (configuration.sourceOffset + pairIndex) % frames.count
            let b2First = ((pairIndex + configuration.orderPhase) % 2) == 0
            let b2Result: TimedResult
            let c1Result: TimedResult
            if b2First {
                b2Result = try executeB2(b2, input: inputs[frameIndex], normalizedRGB: b2NormalizedRGB, activation: b2Activation, sharedActivation: b2SharedActivation)
                c1Result = try executeC1(c1, input: inputs[frameIndex], activation: c1Activation, sharedActivation: c1SharedActivation)
            } else {
                c1Result = try executeC1(c1, input: inputs[frameIndex], activation: c1Activation, sharedActivation: c1SharedActivation)
                b2Result = try executeB2(b2, input: inputs[frameIndex], normalizedRGB: b2NormalizedRGB, activation: b2Activation, sharedActivation: b2SharedActivation)
            }
            records.append(RawPairRecord(
                batchID: String(format: "batch-%02d", configuration.batchIndex),
                frameIndex: frameIndex,
                sourceSampleID: frames[frameIndex].id,
                executionOrder: b2First ? "B2_then_C1" : "C1_then_B2",
                b2Milliseconds: b2Result.milliseconds,
                c1Milliseconds: c1Result.milliseconds
            ))
        }

        return Measurement(
            configuration: configuration,
            rawPairedRecords: records,
            activationMaxAbsoluteError: maxActivationError,
            top1Agreement: top1Agreement,
            b2RGBLogicalBytes: MobileNetV2Corpus.inputWidth * MobileNetV2Corpus.inputHeight * 3 * MemoryLayout<Float>.stride,
            b2RGBAllocatedBytes: b2NormalizedRGB.allocatedSize,
            deviceName: device.name,
            computeUnitsPolicy: tail.computeUnitsPolicyLabel,
            sourceSampleIDs: frames.map(\.id)
        )
    }

    private struct TimedResult {
        let milliseconds: Double
        let probabilities: [String: Double]
    }

    private func executeB2(_ b2: MetalMobileNetV2RGBPipeline, input: MetalRGBBaseline.NV12Textures, normalizedRGB: MTLBuffer, activation: MTLBuffer, sharedActivation: BufferBackedMultiArray) throws -> TimedResult {
        let start = ProcessInfo.processInfo.systemUptime
        try b2.executeCHW(input, normalizedRGB: normalizedRGB, into: activation)
        let probabilities = try tail.predict(sharedActivation: sharedActivation)
        return TimedResult(milliseconds: (ProcessInfo.processInfo.systemUptime - start) * 1_000, probabilities: probabilities)
    }

    private func executeC1(_ c1: MetalMobileNetV2NativeStem, input: MetalRGBBaseline.NV12Textures, activation: MTLBuffer, sharedActivation: BufferBackedMultiArray) throws -> TimedResult {
        let start = ProcessInfo.processInfo.systemUptime
        try c1.execute(input, into: activation)
        let probabilities = try tail.predict(sharedActivation: sharedActivation)
        return TimedResult(milliseconds: (ProcessInfo.processInfo.systemUptime - start) * 1_000, probabilities: probabilities)
    }

    private static func topLabel(_ probabilities: [String: Double]) -> String? {
        probabilities.max { lhs, rhs in lhs.value == rhs.value ? lhs.key > rhs.key : lhs.value < rhs.value }?.key
    }
}
