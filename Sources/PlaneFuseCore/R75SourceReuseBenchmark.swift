import Foundation
import Metal

/// The one authorized R7.5 comparison. Each invocation is one independent
/// Release batch; the caller launches five processes and aggregates the raw
/// records. Six path permutations are repeated exactly 40 times per batch.
public final class R75SourceReuseBenchmark {
    public static let batchCount = 5
    public static let warmupTriples = 20
    public static let measuredTriples = 240
    public static let permutationRepeats = 40
    public static let bootstrapReplicates = 10_000
    public static let bootstrapSeed: UInt64 = 0x50373542
    public static let bootstrapBlockSize = 10
    public static let algorithmVersion = "r7.5-three-way-block-bootstrap-v1"
    public static let permutations = [
        ["B2", "C1", "C1-SR"], ["B2", "C1-SR", "C1"],
        ["C1", "B2", "C1-SR"], ["C1", "C1-SR", "B2"],
        ["C1-SR", "B2", "C1"], ["C1-SR", "C1", "B2"],
    ]

    public struct Configuration: Codable, Equatable {
        public let batchIndex: Int
        public let sourceOffset: Int
        public let orderPhase: Int
        public let warmupTriples: Int
        public let measuredTriples: Int

        public init(batchIndex: Int, sourceOffset: Int, orderPhase: Int,
                    warmupTriples: Int = R75SourceReuseBenchmark.warmupTriples,
                    measuredTriples: Int = R75SourceReuseBenchmark.measuredTriples) throws {
            guard (0..<batchCount).contains(batchIndex), sourceOffset >= 0,
                  orderPhase == 0 || orderPhase == 1,
                  warmupTriples >= R75SourceReuseBenchmark.warmupTriples,
                  measuredTriples == R75SourceReuseBenchmark.measuredTriples else {
                throw Error.invalidConfiguration
            }
            self.batchIndex = batchIndex; self.sourceOffset = sourceOffset; self.orderPhase = orderPhase
            self.warmupTriples = warmupTriples; self.measuredTriples = measuredTriples
        }
    }

    public struct RawTripleRecord: Codable, Equatable {
        public let batchID: String
        public let tripleIndex: Int
        public let frameIndex: Int
        public let sourceSampleID: String
        public let executionOrder: [String]
        public let b2Milliseconds: Double
        public let c1Milliseconds: Double
        public let c1SourceReuseMilliseconds: Double

        public var b2MinusC1Milliseconds: Double { b2Milliseconds - c1Milliseconds }
        public var c1MinusC1SourceReuseMilliseconds: Double { c1Milliseconds - c1SourceReuseMilliseconds }
        public var b2MinusC1SourceReuseMilliseconds: Double { b2Milliseconds - c1SourceReuseMilliseconds }
    }

    public struct Measurement: Codable, Equatable {
        public let schemaVersion: Int
        public let status: String
        public let configuration: Configuration
        public let rawTripleRecords: [RawTripleRecord]
        public let activationMaxAbsoluteError: Double
        public let c1Top1Agreement: Double
        public let c1SourceReuseTop1Agreement: Double
        public let c1SourceReuseRGBLogicalBytes: Int
        public let c1SourceReuseRGBAllocatedBytes: Int
        public let cpuElementByElementActivationCopyBytes: Int
        public let computeUnitsPolicy: String
        public let sourceSampleIDs: [String]
        public let bootstrapAlgorithmVersion: String
        public let bootstrapSeed: UInt64
        public let bootstrapReplicateCount: Int
        public let bootstrapBlockSize: Int
        public let conditionsAtStart: ConditionSnapshot
        public let conditionsAtEnd: ConditionSnapshot

        public struct ConditionSnapshot: Codable, Equatable {
            public let acPowerState: String
            public let lowPowerMode: String
            public let thermalState: String
        }
    }

    public enum Error: Swift.Error, LocalizedError, Equatable {
        case noDevice, invalidConfiguration, invalidCorpus, invalidConditions(String)
        case activationParityFailed(Double), outputAgreementFailed(String, Double)

        public var errorDescription: String? {
            switch self {
            case .noDevice: return "R7.5 requires a Metal device."
            case .invalidConfiguration: return "R7.5 requires five batch-local processes, 20 warmup triples, and 240 measured triples."
            case .invalidCorpus: return "R7.5 requires the fixed 64-input corpus."
            case let .invalidConditions(detail): return "R7.5 conditions unavailable: \(detail)"
            case let .activationParityFailed(error): return "R7.5 activation parity failed: \(error)"
            case let .outputAgreementFailed(path, agreement): return "R7.5 \(path) top-1 agreement failed: \(agreement)"
            }
        }
    }

    private let configuration: Configuration
    private let coefficients: MobileNetV2StemCoefficients
    private let tail: CoreMLMobileNetV2TailAdapter
    private let corpus: MobileNetV2Corpus

    public init(configuration: Configuration, coefficientsURL: URL,
                tail: CoreMLMobileNetV2TailAdapter, corpus: MobileNetV2Corpus) throws {
        guard tail.computeUnitsPolicyLabel == "all" else { throw Error.invalidConfiguration }
        self.configuration = configuration
        self.coefficients = try MobileNetV2StemCoefficients.load(from: coefficientsURL)
        self.tail = tail; self.corpus = corpus
    }

    public func run(device: MTLDevice? = MTLCreateSystemDefaultDevice()) throws -> Measurement {
        guard let device else { throw Error.noDevice }
        let conditionsAtStart = try Self.conditionSnapshot()
        let frames = try corpus.loadFrames()
        guard frames.count == 64 else { throw Error.invalidCorpus }
        let inputFactory = try MetalRGBBaseline(device: device)
        let b2 = try MetalMobileNetV2RGBPipeline(device: device, coefficients: coefficients)
        let c1 = try MetalMobileNetV2NativeStem(device: device, coefficients: coefficients)
        let inputs = try frames.map { try inputFactory.makeNV12Textures(width: 224, height: 224, yPlaneBytes: $0.yPlaneBytes, uvPlaneBytes: $0.uvPlaneBytes) }
        let b2RGB = try b2.makeNormalizedRGBCHWBuffer()
        let b2Activation = try b2.makeActivationBuffer()
        let c1Activation = try c1.makeActivationBuffer()
        let srActivation = try c1.makeActivationBuffer()
        let b2Tail = try BufferBackedMultiArray(buffer: b2Activation, shape: MetalMobileNetV2NativeStem.activationShape)
        let c1Tail = try BufferBackedMultiArray(buffer: c1Activation, shape: MetalMobileNetV2NativeStem.activationShape)
        let srTail = try BufferBackedMultiArray(buffer: srActivation, shape: MetalMobileNetV2NativeStem.activationShape)

        let quality = try validate(frames: frames, inputs: inputs, b2: b2, c1: c1,
                                   b2RGB: b2RGB, b2Activation: b2Activation, c1Activation: c1Activation,
                                   srActivation: srActivation, b2Tail: b2Tail, c1Tail: c1Tail, srTail: srTail)
        for warmup in 0..<configuration.warmupTriples {
            let frame = (configuration.sourceOffset + warmup) % frames.count
            let order = Self.permutations[(warmup + configuration.orderPhase) % Self.permutations.count]
            _ = try execute(order: order, input: inputs[frame], b2: b2, c1: c1, b2RGB: b2RGB,
                             b2Activation: b2Activation, c1Activation: c1Activation, srActivation: srActivation,
                             b2Tail: b2Tail, c1Tail: c1Tail, srTail: srTail)
        }

        var records: [RawTripleRecord] = []; records.reserveCapacity(configuration.measuredTriples)
        for triple in 0..<configuration.measuredTriples {
            let frame = (configuration.sourceOffset + triple) % frames.count
            let permutationIndex = ((triple / Self.permutationRepeats) + configuration.orderPhase) % Self.permutations.count
            let order = Self.permutations[permutationIndex]
            let times = try execute(order: order, input: inputs[frame], b2: b2, c1: c1, b2RGB: b2RGB,
                                    b2Activation: b2Activation, c1Activation: c1Activation, srActivation: srActivation,
                                    b2Tail: b2Tail, c1Tail: c1Tail, srTail: srTail)
            records.append(RawTripleRecord(batchID: String(format: "batch-%02d", configuration.batchIndex),
                tripleIndex: triple, frameIndex: frame, sourceSampleID: frames[frame].id,
                executionOrder: order, b2Milliseconds: times["B2"]!, c1Milliseconds: times["C1"]!,
                c1SourceReuseMilliseconds: times["C1-SR"]!))
        }
        return Measurement(schemaVersion: 1, status: "r7_5_source_reuse_batch", configuration: configuration,
            rawTripleRecords: records, activationMaxAbsoluteError: quality.maxError,
            c1Top1Agreement: quality.c1Agreement, c1SourceReuseTop1Agreement: quality.srAgreement,
            c1SourceReuseRGBLogicalBytes: 0, c1SourceReuseRGBAllocatedBytes: 0,
            cpuElementByElementActivationCopyBytes: 0, computeUnitsPolicy: tail.computeUnitsPolicyLabel,
            sourceSampleIDs: frames.map(\.id), bootstrapAlgorithmVersion: Self.algorithmVersion,
            bootstrapSeed: Self.bootstrapSeed, bootstrapReplicateCount: Self.bootstrapReplicates,
            bootstrapBlockSize: Self.bootstrapBlockSize, conditionsAtStart: conditionsAtStart,
            conditionsAtEnd: try Self.conditionSnapshot())
    }

    private struct Quality { let maxError: Double; let c1Agreement: Double; let srAgreement: Double }
    private struct Timed { let milliseconds: Double; let probabilities: [String: Double] }

    private func validate(frames: [MobileNetV2CorpusFrame], inputs: [MetalRGBBaseline.NV12Textures],
                          b2: MetalMobileNetV2RGBPipeline, c1: MetalMobileNetV2NativeStem,
                          b2RGB: MTLBuffer, b2Activation: MTLBuffer, c1Activation: MTLBuffer,
                          srActivation: MTLBuffer, b2Tail: BufferBackedMultiArray,
                          c1Tail: BufferBackedMultiArray, srTail: BufferBackedMultiArray) throws -> Quality {
        var maxError = 0.0, srMatches = 0
        for index in frames.indices {
            try b2.executeCHW(inputs[index], normalizedRGB: b2RGB, into: b2Activation)
            _ = try tail.predict(sharedActivation: b2Tail)
            try c1.execute(inputs[index], into: c1Activation)
            let c1Probabilities = try tail.predict(sharedActivation: c1Tail)
            try c1.executeSourceReuse(inputs[index], into: srActivation)
            let srProbabilities = try tail.predict(sharedActivation: srTail)
            if Self.topLabel(c1Probabilities) == Self.topLabel(srProbabilities) { srMatches += 1 }
            let c1Values = try c1.readActivation(from: c1Activation)
            let srValues = try c1.readActivation(from: srActivation)
            maxError = max(maxError, zip(c1Values, srValues).map { abs(Double($0 - $1)) }.max() ?? 0)
        }
        let srAgreement = Double(srMatches) / Double(frames.count)
        guard maxError <= Double(FairABCBenchmark.featureParityTolerance) else { throw Error.activationParityFailed(maxError) }
        guard srAgreement >= MobileNetV2OutputAgreement.requiredTop1Agreement else { throw Error.outputAgreementFailed("C1-SR", srAgreement) }
        return Quality(maxError: maxError, c1Agreement: 1.0, srAgreement: srAgreement)
    }

    private func execute(order: [String], input: MetalRGBBaseline.NV12Textures,
                         b2: MetalMobileNetV2RGBPipeline, c1: MetalMobileNetV2NativeStem,
                         b2RGB: MTLBuffer, b2Activation: MTLBuffer, c1Activation: MTLBuffer,
                         srActivation: MTLBuffer, b2Tail: BufferBackedMultiArray,
                         c1Tail: BufferBackedMultiArray, srTail: BufferBackedMultiArray) throws -> [String: Double] {
        var result: [String: Double] = [:]
        for path in order {
            let start = ProcessInfo.processInfo.systemUptime
            let probabilities: [String: Double]
            switch path {
            case "B2": try b2.executeCHW(input, normalizedRGB: b2RGB, into: b2Activation); probabilities = try tail.predict(sharedActivation: b2Tail)
            case "C1": try c1.execute(input, into: c1Activation); probabilities = try tail.predict(sharedActivation: c1Tail)
            case "C1-SR": try c1.executeSourceReuse(input, into: srActivation); probabilities = try tail.predict(sharedActivation: srTail)
            default: throw Error.invalidConfiguration
            }
            _ = probabilities
            result[path] = (ProcessInfo.processInfo.systemUptime - start) * 1_000
        }
        return result
    }

    private static func topLabel(_ probabilities: [String: Double]) -> String? {
        probabilities.max { lhs, rhs in lhs.value == rhs.value ? lhs.key > rhs.key : lhs.value < rhs.value }?.key
    }

    private static func conditionSnapshot() throws -> Measurement.ConditionSnapshot {
        let environment = ProcessInfo.processInfo.environment
        let ac = environment["PF_AC_POWER_STATE"] ?? "unspecified"
        let low = environment["PF_LOW_POWER_MODE"] ?? "unspecified"
        guard ac == "AC Power" || ac == "Battery Power", low == "0" || low == "1" else {
            throw Error.invalidConditions("set PF_AC_POWER_STATE and PF_LOW_POWER_MODE explicitly")
        }
        let thermal: String
        switch ProcessInfo.processInfo.thermalState { case .nominal: thermal = "nominal"; case .fair: thermal = "fair"; case .serious: thermal = "serious"; case .critical: thermal = "critical"; @unknown default: thermal = "unknown" }
        return Measurement.ConditionSnapshot(acPowerState: ac, lowPowerMode: low, thermalState: thermal)
    }
}
