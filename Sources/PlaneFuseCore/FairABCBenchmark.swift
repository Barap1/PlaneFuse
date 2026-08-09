import Foundation
import Metal

/// A preallocated, interleaved comparison of the optimized RGB baseline (Pipeline B)
/// and the native-plane stem (Pipeline C). The benchmark intentionally keeps setup,
/// readback, and reporting outside each timed region.
public struct FairABCBenchmark {
    public struct Configuration: Codable, Equatable {
        public let warmupIterations: Int
        public let measuredIterations: Int
        public let width: Int
        public let height: Int

        public init(
            warmupIterations: Int,
            measuredIterations: Int,
            width: Int,
            height: Int
        ) {
            self.warmupIterations = warmupIterations
            self.measuredIterations = measuredIterations
            self.width = width
            self.height = height
        }

        public static let quick = Configuration(
            warmupIterations: 10,
            measuredIterations: 30,
            width: 640,
            height: 480
        )

        public static let confirm = Configuration(
            warmupIterations: 30,
            measuredIterations: 100,
            width: 640,
            height: 480
        )
    }

    public struct TimingStatistics: Codable, Equatable {
        public let p50Milliseconds: Double
        public let p95Milliseconds: Double
        public let meanMilliseconds: Double

        public init(
            p50Milliseconds: Double,
            p95Milliseconds: Double,
            meanMilliseconds: Double
        ) {
            self.p50Milliseconds = p50Milliseconds
            self.p95Milliseconds = p95Milliseconds
            self.meanMilliseconds = meanMilliseconds
        }
    }

    public struct Measurement: Codable, Equatable {
        /// B frontend: NV12 to materialized normalized RGBA32Float.
        public let pipelineBFrontend: TimingStatistics
        /// B end-to-end: NV12 to normalized RGBA32Float, then the normal RGB 1x1 stem.
        public let pipelineBEndToEnd: TimingStatistics
        /// C frontend: the native-plane stem dispatch measured in the frontend pass.
        public let pipelineCFrontend: TimingStatistics
        /// C end-to-end: the native-plane stem dispatch measured in the end-to-end pass.
        public let pipelineCEndToEnd: TimingStatistics
        public let measuredIterations: Int
        public let warmupIterations: Int
        public let width: Int
        public let height: Int
        /// Requested byte count of B's full RGBA32Float model-input intermediate.
        public let pipelineBRGBIntermediateBytes: Int
        /// Metal-reported allocation size of B's RGB intermediate texture.
        public let pipelineBRGBIntermediateAllocatedBytes: Int
        /// Must remain zero because Pipeline C does not allocate an RGB intermediate.
        public let pipelineCRGBIntermediateBytes: Int
        /// Metal-reported allocation size of Pipeline C's required feature output texture.
        public let pipelineCFeatureAllocatedBytes: Int
        public let maxFeatureAbsoluteDifference: Float
        public let featureParityPass: Bool
        public let deviceName: String
        public let deviceClass: String
        /// `sorted[ceil(p * n) - 1]`, using one-based nearest rank.
        public let percentileDefinition: String
        /// C-vs-B p50 frontend delta, computed as `(B - C) / B * 100`.
        public let cVsBFrontendPercentageDelta: Double?
        /// C-vs-B p50 end-to-end delta, computed as `(B - C) / B * 100`.
        public let cVsBEndToEndPercentageDelta: Double?
        public let percentageDeltaFormula: String
        /// Submission topology for the independently measured frontend and end-to-end passes.
        /// Optional to retain decoding compatibility with results written before this field existed.
        public let commandBufferMethodology: String?

        public init(
            pipelineBFrontend: TimingStatistics,
            pipelineBEndToEnd: TimingStatistics,
            pipelineCFrontend: TimingStatistics,
            pipelineCEndToEnd: TimingStatistics,
            measuredIterations: Int,
            warmupIterations: Int,
            width: Int,
            height: Int,
            pipelineBRGBIntermediateBytes: Int,
            pipelineBRGBIntermediateAllocatedBytes: Int,
            pipelineCRGBIntermediateBytes: Int,
            pipelineCFeatureAllocatedBytes: Int,
            maxFeatureAbsoluteDifference: Float,
            featureParityPass: Bool,
            deviceName: String,
            deviceClass: String,
            percentileDefinition: String,
            cVsBFrontendPercentageDelta: Double?,
            cVsBEndToEndPercentageDelta: Double?,
            percentageDeltaFormula: String,
            commandBufferMethodology: String? = nil
        ) {
            self.pipelineBFrontend = pipelineBFrontend
            self.pipelineBEndToEnd = pipelineBEndToEnd
            self.pipelineCFrontend = pipelineCFrontend
            self.pipelineCEndToEnd = pipelineCEndToEnd
            self.measuredIterations = measuredIterations
            self.warmupIterations = warmupIterations
            self.width = width
            self.height = height
            self.pipelineBRGBIntermediateBytes = pipelineBRGBIntermediateBytes
            self.pipelineBRGBIntermediateAllocatedBytes = pipelineBRGBIntermediateAllocatedBytes
            self.pipelineCRGBIntermediateBytes = pipelineCRGBIntermediateBytes
            self.pipelineCFeatureAllocatedBytes = pipelineCFeatureAllocatedBytes
            self.maxFeatureAbsoluteDifference = maxFeatureAbsoluteDifference
            self.featureParityPass = featureParityPass
            self.deviceName = deviceName
            self.deviceClass = deviceClass
            self.percentileDefinition = percentileDefinition
            self.cVsBFrontendPercentageDelta = cVsBFrontendPercentageDelta
            self.cVsBEndToEndPercentageDelta = cVsBEndToEndPercentageDelta
            self.percentageDeltaFormula = percentageDeltaFormula
            self.commandBufferMethodology = commandBufferMethodology
        }
    }

    public enum Error: Swift.Error, LocalizedError, Equatable {
        case noDevice
        case invalidConfiguration

        public var errorDescription: String? {
            switch self {
            case .noDevice:
                return "No Metal device is available for the fair Pipeline B/C benchmark."
            case .invalidConfiguration:
                return "Benchmark configuration requires positive even dimensions, positive measured iterations, and nonnegative warmup iterations."
            }
        }
    }

    public static let featureParityTolerance: Float = 0.00001
    public static let nearestRankPercentileDefinition = "nearest-rank: sorted[ceil(p * n) - 1]"
    public static let percentageDeltaFormula = "(B - C) / B * 100"
    public static let commandBufferMethodology = "Frontend: one command buffer / one submission per B conversion and C native stem. End-to-end: Pipeline B uses one command buffer / one submission containing conversion and RGB stem dispatches; Pipeline C uses one command buffer / one submission containing one native-stem dispatch."

    public let configuration: Configuration

    public init(configuration: Configuration = .quick) {
        self.configuration = configuration
    }

    /// Compiles all three reusable Metal paths and allocates every input, intermediate,
    /// and output before warmup. Measured iterations alternate B-first and C-first
    /// ordering to avoid consistently favoring one path as the GPU warms or drifts.
    public func run(device: MTLDevice? = MTLCreateSystemDefaultDevice()) throws -> Measurement {
        guard let device else { throw Error.noDevice }
        try validateConfiguration()

        let stem = MetalNativeStem.m1FixtureStem
        let baseline = try MetalRGBBaseline(device: device)
        let rgbStem = try MetalRGBNormalStem(device: device, stem: stem)
        let nativeStem = try MetalNativeStem(device: device, stem: stem)
        let fixture = MetalBaselineBenchmark.deterministicNV12Fixture(
            width: configuration.width,
            height: configuration.height
        )
        let input = try baseline.makeNV12Textures(
            width: configuration.width,
            height: configuration.height,
            yPlaneBytes: fixture.yPlaneBytes,
            uvPlaneBytes: fixture.uvPlaneBytes
        )
        let pipelineBRGBIntermediate = try baseline.makeRGBA32FloatTexture(
            width: configuration.width,
            height: configuration.height
        )
        let pipelineBFeatures = try rgbStem.makeFeatureTexture(
            width: configuration.width,
            height: configuration.height
        )
        let pipelineCFeatures = try nativeStem.makeFeatureTexture(
            width: configuration.width,
            height: configuration.height
        )

        var pipelineBFrontendDurations: [Double] = []
        var pipelineCFrontendDurations: [Double] = []
        var pipelineBEndToEndDurations: [Double] = []
        var pipelineCEndToEndDurations: [Double] = []
        pipelineBFrontendDurations.reserveCapacity(configuration.measuredIterations)
        pipelineCFrontendDurations.reserveCapacity(configuration.measuredIterations)
        pipelineBEndToEndDurations.reserveCapacity(configuration.measuredIterations)
        pipelineCEndToEndDurations.reserveCapacity(configuration.measuredIterations)

        // Frontend pass: B measures only NV12-to-RGBA conversion, while C measures
        // its one native-stem dispatch. Both paths warm up in alternating order.
        for iteration in 0..<configuration.warmupIterations {
            try executeInterleaved(
                iteration: iteration,
                pipelineB: {
                    _ = try baseline.execute(input, into: pipelineBRGBIntermediate)
                },
                pipelineC: {
                    _ = try nativeStem.execute(input, into: pipelineCFeatures)
                }
            )
        }

        for iteration in 0..<configuration.measuredIterations {
            try executeInterleaved(
                iteration: iteration,
                pipelineB: {
                    pipelineBFrontendDurations.append(try measure {
                        _ = try baseline.execute(input, into: pipelineBRGBIntermediate)
                    })
                },
                pipelineC: {
                    pipelineCFrontendDurations.append(try measure {
                        _ = try nativeStem.execute(input, into: pipelineCFeatures)
                    })
                }
            )
        }

        // End-to-end pass: B composes conversion and normal-RGB stem encoders in
        // one command buffer and waits once. C remains one native-stem dispatch in
        // one command buffer. Each iteration measures exactly one B and one C path.
        for iteration in 0..<configuration.warmupIterations {
            try executeInterleaved(
                iteration: iteration,
                pipelineB: {
                    try executePipelineBEndToEnd(
                        baseline: baseline,
                        rgbStem: rgbStem,
                        input: input,
                        rgbIntermediate: pipelineBRGBIntermediate,
                        features: pipelineBFeatures
                    )
                },
                pipelineC: {
                    _ = try nativeStem.execute(input, into: pipelineCFeatures)
                }
            )
        }

        for iteration in 0..<configuration.measuredIterations {
            try executeInterleaved(
                iteration: iteration,
                pipelineB: {
                    pipelineBEndToEndDurations.append(try measure {
                        try executePipelineBEndToEnd(
                            baseline: baseline,
                            rgbStem: rgbStem,
                            input: input,
                            rgbIntermediate: pipelineBRGBIntermediate,
                            features: pipelineBFeatures
                        )
                    })
                },
                pipelineC: {
                    pipelineCEndToEndDurations.append(try measure {
                        _ = try nativeStem.execute(input, into: pipelineCFeatures)
                    })
                }
            )
        }

        // Texture readback and output comparison are intentionally after all timing.
        let pipelineBFeatureValues = try baseline.readRGBA32Float(from: pipelineBFeatures)
        let pipelineCFeatureValues = try baseline.readRGBA32Float(from: pipelineCFeatures)
        let maxFeatureAbsoluteDifference = zip(pipelineBFeatureValues, pipelineCFeatureValues)
            .reduce(Float.zero) { maximum, pair in
                max(maximum, abs(pair.0 - pair.1))
            }

        let pipelineBFrontend = statistics(for: pipelineBFrontendDurations)
        let pipelineCFrontend = statistics(for: pipelineCFrontendDurations)
        let pipelineBEndToEnd = statistics(for: pipelineBEndToEndDurations)
        let pipelineCEndToEnd = statistics(for: pipelineCEndToEndDurations)
        return Measurement(
            pipelineBFrontend: pipelineBFrontend,
            pipelineBEndToEnd: pipelineBEndToEnd,
            pipelineCFrontend: pipelineCFrontend,
            pipelineCEndToEnd: pipelineCEndToEnd,
            measuredIterations: configuration.measuredIterations,
            warmupIterations: configuration.warmupIterations,
            width: configuration.width,
            height: configuration.height,
            pipelineBRGBIntermediateBytes: configuration.width * configuration.height * 4 * MemoryLayout<Float>.stride,
            pipelineBRGBIntermediateAllocatedBytes: pipelineBRGBIntermediate.allocatedSize,
            pipelineCRGBIntermediateBytes: 0,
            pipelineCFeatureAllocatedBytes: pipelineCFeatures.allocatedSize,
            maxFeatureAbsoluteDifference: maxFeatureAbsoluteDifference,
            featureParityPass: maxFeatureAbsoluteDifference <= Self.featureParityTolerance,
            deviceName: device.name,
            deviceClass: String(describing: type(of: device)),
            percentileDefinition: Self.nearestRankPercentileDefinition,
            cVsBFrontendPercentageDelta: percentageDelta(
                baseline: pipelineBFrontend.p50Milliseconds,
                candidate: pipelineCFrontend.p50Milliseconds
            ),
            cVsBEndToEndPercentageDelta: percentageDelta(
                baseline: pipelineBEndToEnd.p50Milliseconds,
                candidate: pipelineCEndToEnd.p50Milliseconds
            ),
            percentageDeltaFormula: Self.percentageDeltaFormula,
            commandBufferMethodology: Self.commandBufferMethodology
        )
    }

    /// Executes Pipeline B's conversion and normal RGB stem as two ordered compute
    /// encoders in one command buffer from the baseline queue. It commits once and
    /// waits once so B's end-to-end timing has the same submission count as C.
    private func executePipelineBEndToEnd(
        baseline: MetalRGBBaseline,
        rgbStem: MetalRGBNormalStem,
        input: MetalRGBBaseline.NV12Textures,
        rgbIntermediate: MTLTexture,
        features: MTLTexture
    ) throws {
        guard let commandBuffer = baseline.commandQueue.makeCommandBuffer() else {
            throw MetalRGBBaseline.Error.commandBufferUnavailable
        }
        guard let conversionEncoder = commandBuffer.makeComputeCommandEncoder() else {
            throw MetalRGBBaseline.Error.commandEncoderUnavailable
        }
        try baseline.encode(input, into: rgbIntermediate, using: conversionEncoder)
        conversionEncoder.endEncoding()

        guard let stemEncoder = commandBuffer.makeComputeCommandEncoder() else {
            throw MetalRGBNormalStem.Error.commandEncoderUnavailable
        }
        try rgbStem.encode(normalizedRGB: rgbIntermediate, into: features, using: stemEncoder)
        stemEncoder.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else {
            throw MetalRGBBaseline.Error.commandExecutionFailed
        }
    }

    private func validateConfiguration() throws {
        guard configuration.warmupIterations >= 0,
              configuration.measuredIterations > 0,
              configuration.width > 0,
              configuration.height > 0,
              configuration.width.isMultiple(of: 2),
              configuration.height.isMultiple(of: 2) else {
            throw Error.invalidConfiguration
        }
    }

    /// Runs exactly one B sequence and one C sequence per iteration. Odd-numbered
    /// iterations run C first, so no path is always measured first.
    private func executeInterleaved(
        iteration: Int,
        pipelineB: () throws -> Void,
        pipelineC: () throws -> Void
    ) throws {
        if iteration.isMultiple(of: 2) {
            try pipelineB()
            try pipelineC()
        } else {
            try pipelineC()
            try pipelineB()
        }
    }

    private func measure(_ operation: () throws -> Void) throws -> Double {
        let start = ProcessInfo.processInfo.systemUptime
        try operation()
        return (ProcessInfo.processInfo.systemUptime - start) * 1_000.0
    }

    private func statistics(for durations: [Double]) -> TimingStatistics {
        let sorted = durations.sorted()
        return TimingStatistics(
            p50Milliseconds: nearestRank(sorted, percentile: 0.50),
            p95Milliseconds: nearestRank(sorted, percentile: 0.95),
            meanMilliseconds: durations.reduce(0, +) / Double(durations.count)
        )
    }

    private func nearestRank(_ sorted: [Double], percentile: Double) -> Double {
        let rank = max(1, Int(ceil(percentile * Double(sorted.count))))
        return sorted[rank - 1]
    }

    private func percentageDelta(baseline: Double, candidate: Double) -> Double? {
        guard baseline > 0 else { return nil }
        return (baseline - candidate) / baseline * 100
    }
}
