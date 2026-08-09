import Foundation
import Metal

/// R2 matched bridge ablation. B2/C0 retain the current boxed MLMultiArray
/// control; B2/C1 use one persistent buffer-backed view per activation buffer.
public final class MobileNetV2SharedBridgeBenchmark {
    public struct Configuration: Codable, Equatable {
        public let warmupIterations: Int
        public let measuredIterations: Int
        public init(warmupIterations: Int = 5, measuredIterations: Int = 20) {
            self.warmupIterations = warmupIterations
            self.measuredIterations = measuredIterations
        }
        public static let quick = Configuration()
    }

    public struct Statistics: Codable, Equatable {
        public let p50Milliseconds: Double
        public let p95Milliseconds: Double
        public let meanMilliseconds: Double
        public let medianAbsoluteDeviationMilliseconds: Double

        public init(_ values: [Double]) {
            let sorted = values.sorted()
            func nearestRank(_ percentile: Double) -> Double {
                sorted[max(1, Int(ceil(percentile * Double(sorted.count)))) - 1]
            }
            let median = nearestRank(0.50)
            p50Milliseconds = median
            p95Milliseconds = nearestRank(0.95)
            meanMilliseconds = values.reduce(0, +) / Double(values.count)
            let deviations = values.map { abs($0 - median) }.sorted()
            medianAbsoluteDeviationMilliseconds = deviations[max(1, Int(ceil(0.50 * Double(deviations.count)))) - 1]
        }
    }

    public struct Measurement: Codable, Equatable {
        public let schemaVersion: Int
        public let configuration: Configuration
        public let pipelineBBoxedEndToEnd: Statistics
        public let pipelineBSharedEndToEnd: Statistics
        public let pipelineCBoxedEndToEnd: Statistics
        public let pipelineCSharedEndToEnd: Statistics
        public let pipelineBBoxedBridge: Statistics
        public let pipelineBSharedBridge: Statistics
        public let pipelineCBoxedBridge: Statistics
        public let pipelineCSharedBridge: Statistics
        public let bBridgeReductionPercentage: Double
        public let cBridgeReductionPercentage: Double
        public let bEndToEndReductionPercentage: Double
        public let cEndToEndReductionPercentage: Double
        public let sharedTop1Agreement: Double
        public let boxedTop1Agreement: Double
        public let sharedVsBoxedTop1Agreement: Double
        public let maxActivationAbsoluteDifference: Double
        public let bufferBackedShape: [Int]
        public let bufferBackedStride: [Int]
        public let bActivationAllocatedBytes: Int
        public let cActivationAllocatedBytes: Int
        public let deviceName: String
        public let deviceClass: String
        public let methodology: String
    }

    private struct TimedResult {
        let total: Double
        let bridge: Double
        let output: [String: Double]
    }

    private let configuration: Configuration
    private let coefficients: MobileNetV2StemCoefficients
    private let tail: CoreMLMobileNetV2TailAdapter
    private let corpus: MobileNetV2Corpus

    public init(configuration: Configuration = .quick, coefficientsURL: URL, tail: CoreMLMobileNetV2TailAdapter, corpus: MobileNetV2Corpus) throws {
        guard configuration.warmupIterations >= 0, configuration.measuredIterations > 0 else { throw MobileNetV2Benchmark.Error.invalidConfiguration }
        self.configuration = configuration
        self.coefficients = try MobileNetV2StemCoefficients.load(from: coefficientsURL)
        self.tail = tail
        self.corpus = corpus
    }

    public func run(device: MTLDevice? = MTLCreateSystemDefaultDevice()) throws -> Measurement {
        guard let device else { throw MobileNetV2Benchmark.Error.noDevice }
        let factory = try MetalRGBBaseline(device: device)
        let rgb = try MetalMobileNetV2RGBPipeline(device: device, coefficients: coefficients)
        let native = try MetalMobileNetV2NativeStem(device: device, coefficients: coefficients)
        let normalizedRGB = try rgb.makeNormalizedRGBCHWBuffer()
        let bActivation = try rgb.makeActivationBuffer()
        let cActivation = try native.makeActivationBuffer()
        let bShared = try BufferBackedMultiArray(buffer: bActivation, shape: MetalMobileNetV2NativeStem.activationShape)
        let cShared = try BufferBackedMultiArray(buffer: cActivation, shape: MetalMobileNetV2NativeStem.activationShape)
        let frames = try corpus.loadFrames()

        var bBoxedEnd: [Double] = []; var bSharedEnd: [Double] = []
        var cBoxedEnd: [Double] = []; var cSharedEnd: [Double] = []
        var bBoxedBridge: [Double] = []; var bSharedBridge: [Double] = []
        var cBoxedBridge: [Double] = []; var cSharedBridge: [Double] = []
        var boxedMatches = 0; var sharedMatches = 0; var sharedBoxedMatches = 0
        var maxActivationError = 0.0
        let totalIterations = configuration.warmupIterations + configuration.measuredIterations

        for iteration in 0..<totalIterations {
            let frame = frames[iteration % frames.count]
            let input = try factory.makeNV12Textures(width: 224, height: 224, yPlaneBytes: frame.yPlaneBytes, uvPlaneBytes: frame.uvPlaneBytes)
            let bBoxed = try timedBBoxed(rgb: rgb, input: input, normalizedRGB: normalizedRGB, activation: bActivation)
            let bSharedResult = try timedBShared(rgb: rgb, input: input, normalizedRGB: normalizedRGB, activation: bActivation, shared: bShared)
            let cBoxed = try timedCBoxed(native: native, input: input, activation: cActivation)
            let cSharedResult = try timedCShared(native: native, input: input, activation: cActivation, shared: cShared)
            guard Self.topLabel(bBoxed.output) == Self.topLabel(bSharedResult.output), Self.topLabel(cBoxed.output) == Self.topLabel(cSharedResult.output) else {
                throw MobileNetV2Benchmark.Error.outputAgreementFailed(agreement: 0)
            }
            if iteration >= configuration.warmupIterations {
                bBoxedEnd.append(bBoxed.total); bSharedEnd.append(bSharedResult.total)
                cBoxedEnd.append(cBoxed.total); cSharedEnd.append(cSharedResult.total)
                bBoxedBridge.append(bBoxed.bridge); bSharedBridge.append(bSharedResult.bridge)
                cBoxedBridge.append(cBoxed.bridge); cSharedBridge.append(cSharedResult.bridge)
                if Self.topLabel(bBoxed.output) == Self.topLabel(cBoxed.output) { boxedMatches += 1 }
                if Self.topLabel(bSharedResult.output) == Self.topLabel(cSharedResult.output) { sharedMatches += 1 }
                if Self.topLabel(bBoxed.output) == Self.topLabel(bSharedResult.output) { sharedBoxedMatches += 1 }
                let bFeatures = try rgb.readActivation(from: bActivation)
                let cFeatures = try native.readActivation(from: cActivation)
                maxActivationError = max(maxActivationError, zip(bFeatures, cFeatures).map { abs(Double($0 - $1)) }.max() ?? 0)
            }
        }

        let bBoxedBridgeP50 = Statistics(bBoxedBridge).p50Milliseconds
        let cBoxedBridgeP50 = Statistics(cBoxedBridge).p50Milliseconds
        return Measurement(
            schemaVersion: 1,
            configuration: configuration,
            pipelineBBoxedEndToEnd: Statistics(bBoxedEnd), pipelineBSharedEndToEnd: Statistics(bSharedEnd),
            pipelineCBoxedEndToEnd: Statistics(cBoxedEnd), pipelineCSharedEndToEnd: Statistics(cSharedEnd),
            pipelineBBoxedBridge: Statistics(bBoxedBridge), pipelineBSharedBridge: Statistics(bSharedBridge),
            pipelineCBoxedBridge: Statistics(cBoxedBridge), pipelineCSharedBridge: Statistics(cSharedBridge),
            bBridgeReductionPercentage: (bBoxedBridgeP50 - Statistics(bSharedBridge).p50Milliseconds) / bBoxedBridgeP50 * 100,
            cBridgeReductionPercentage: (cBoxedBridgeP50 - Statistics(cSharedBridge).p50Milliseconds) / cBoxedBridgeP50 * 100,
            bEndToEndReductionPercentage: (Statistics(bBoxedEnd).p50Milliseconds - Statistics(bSharedEnd).p50Milliseconds) / Statistics(bBoxedEnd).p50Milliseconds * 100,
            cEndToEndReductionPercentage: (Statistics(cBoxedEnd).p50Milliseconds - Statistics(cSharedEnd).p50Milliseconds) / Statistics(cBoxedEnd).p50Milliseconds * 100,
            sharedTop1Agreement: Double(sharedMatches) / Double(configuration.measuredIterations),
            boxedTop1Agreement: Double(boxedMatches) / Double(configuration.measuredIterations),
            sharedVsBoxedTop1Agreement: Double(sharedBoxedMatches) / Double(configuration.measuredIterations),
            maxActivationAbsoluteDifference: maxActivationError,
            bufferBackedShape: MetalMobileNetV2NativeStem.activationShape,
            bufferBackedStride: [112 * 112, 112, 1],
            bActivationAllocatedBytes: bActivation.allocatedSize,
            cActivationAllocatedBytes: cActivation.allocatedSize,
            deviceName: device.name,
            deviceClass: String(describing: type(of: device)),
            methodology: "Matched B2/C0 boxed controls and B2/C1 persistent buffer-backed MLMultiArray views. Each path reuses one activation buffer and one view; GPU completion is awaited before Core ML prediction. Bridge timings include the current Swift-array read plus boxed allocation/population for controls, versus the shared-view prediction call for candidates. No hidden Core ML copy is inferred."
        )
    }

    private func timedBBoxed(rgb: MetalMobileNetV2RGBPipeline, input: MetalRGBBaseline.NV12Textures, normalizedRGB: MTLBuffer, activation: MTLBuffer) throws -> TimedResult {
        let start = ProcessInfo.processInfo.systemUptime
        try rgb.executeCHW(input, normalizedRGB: normalizedRGB, into: activation)
        let bridgeStart = ProcessInfo.processInfo.systemUptime
        let output = try tail.predict(stemActivation: rgb.readActivation(from: activation))
        let end = ProcessInfo.processInfo.systemUptime
        return TimedResult(total: (end - start) * 1_000, bridge: (end - bridgeStart) * 1_000, output: output)
    }

    private func timedBShared(rgb: MetalMobileNetV2RGBPipeline, input: MetalRGBBaseline.NV12Textures, normalizedRGB: MTLBuffer, activation: MTLBuffer, shared: BufferBackedMultiArray) throws -> TimedResult {
        let start = ProcessInfo.processInfo.systemUptime
        try rgb.executeCHW(input, normalizedRGB: normalizedRGB, into: activation)
        let bridgeStart = ProcessInfo.processInfo.systemUptime
        let output = try tail.predict(sharedActivation: shared)
        let end = ProcessInfo.processInfo.systemUptime
        return TimedResult(total: (end - start) * 1_000, bridge: (end - bridgeStart) * 1_000, output: output)
    }

    private func timedCBoxed(native: MetalMobileNetV2NativeStem, input: MetalRGBBaseline.NV12Textures, activation: MTLBuffer) throws -> TimedResult {
        let start = ProcessInfo.processInfo.systemUptime
        try native.execute(input, into: activation)
        let bridgeStart = ProcessInfo.processInfo.systemUptime
        let output = try tail.predict(stemActivation: native.readActivation(from: activation))
        let end = ProcessInfo.processInfo.systemUptime
        return TimedResult(total: (end - start) * 1_000, bridge: (end - bridgeStart) * 1_000, output: output)
    }

    private func timedCShared(native: MetalMobileNetV2NativeStem, input: MetalRGBBaseline.NV12Textures, activation: MTLBuffer, shared: BufferBackedMultiArray) throws -> TimedResult {
        let start = ProcessInfo.processInfo.systemUptime
        try native.execute(input, into: activation)
        let bridgeStart = ProcessInfo.processInfo.systemUptime
        let output = try tail.predict(sharedActivation: shared)
        let end = ProcessInfo.processInfo.systemUptime
        return TimedResult(total: (end - start) * 1_000, bridge: (end - bridgeStart) * 1_000, output: output)
    }

    private static func topLabel(_ probabilities: [String: Double]) -> String? {
        probabilities.max { $0.value < $1.value }?.key
    }
}
