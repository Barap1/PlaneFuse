import Foundation
import Metal

/// Separate, non-benchmark profiler path for the exact accepted R7 B2-shared
/// and C1-shared implementations. It reuses the production encoder methods and
/// persistent buffer-backed tail views, but records only compact summaries so a
/// Metal/Xcode trace can be captured without changing the final benchmark.
public final class MobileNetV2SharedPathProfile {
    public struct Configuration: Codable, Equatable {
        public let warmupIterations: Int
        public let measuredIterations: Int

        public init(warmupIterations: Int = 5, measuredIterations: Int = 20) throws {
            guard warmupIterations >= 0, measuredIterations > 0 else { throw Error.invalidConfiguration }
            self.warmupIterations = warmupIterations
            self.measuredIterations = measuredIterations
        }

        public static let quick: Configuration = try! Configuration()
    }

    public struct Statistics: Codable, Equatable {
        public let count: Int
        public let p50Milliseconds: Double
        public let p95Milliseconds: Double
        public let meanMilliseconds: Double
        public let medianAbsoluteDeviationMilliseconds: Double

        public init(_ values: [Double]) throws {
            guard !values.isEmpty else { throw Error.noSamples }
            let sorted = values.sorted()
            func nearestRank(_ percentile: Double) -> Double {
                sorted[max(1, Int(ceil(percentile * Double(sorted.count)))) - 1]
            }
            let median = nearestRank(0.50)
            count = values.count
            p50Milliseconds = median
            p95Milliseconds = nearestRank(0.95)
            meanMilliseconds = values.reduce(0, +) / Double(values.count)
            let deviations = values.map { abs($0 - median) }.sorted()
            medianAbsoluteDeviationMilliseconds = deviations[max(1, Int(ceil(0.50 * Double(deviations.count)))) - 1]
        }
    }

    public struct PathMeasurement: Codable, Equatable {
        public let wallFrontend: Statistics
        public let gpuExecution: Statistics?
        public let gpuTimestampSamples: Int
        public let encode: Statistics
        public let synchronizationWait: Statistics
        public let tailPrediction: Statistics
        public let inputToResult: Statistics
    }

    public struct Measurement: Codable, Equatable {
        public let schemaVersion: Int
        public let status: String
        public let commit: String?
        public let environment: EnvironmentSnapshot
        public let command: String
        public let configuration: Configuration
        public let pipelineB2Shared: PathMeasurement
        public let pipelineC1Shared: PathMeasurement
        public let top1Agreement: Double
        public let activationMaxAbsoluteError: Double
        public let validationSampleCount: Int
        public let deviceName: String
        public let deviceClass: String
        public let requestedCoreMLComputeUnits: String
        public let comparison: String
        public let resources: ResourceEvidence
        public let persistentActivationHandoff: ActivationHandoffEvidence
        public let sourceSymbols: SourceSymbols
        public let trace: TraceEvidence
    }

    public struct ResourceEvidence: Codable, Equatable {
        public let b2RGBLogicalPayloadBytes: Int
        public let b2RGBMetalAllocatedBytes: Int
        public let c1RGBLogicalPayloadBytes: Int
        public let c1RGBMetalAllocatedBytes: Int
        public let cpuElementByElementActivationCopyBytes: Int
        public let c1RGBResourceStatement: String
    }

    public struct ActivationHandoffEvidence: Codable, Equatable {
        public let shape: [Int]
        public let strides: [Int]
        public let elementType: String
        public let b2BufferLengthBytes: Int
        public let c1BufferLengthBytes: Int
        public let bridge: String
    }

    public struct SourceSymbols: Codable, Equatable {
        public let b2Pipeline: String
        public let c1Pipeline: String
        public let sharedTail: String
        public let b2Shader: String
        public let c1Shader: String
    }

    public struct TraceEvidence: Codable, Equatable {
        public let status: String
        public let format: String
        public let rawTracePath: String
        public let exportedSummaryPath: String?
        public let captureCommand: String
    }

    public enum Error: Swift.Error, LocalizedError, Equatable {
        case invalidConfiguration
        case noSamples
        case noDevice
        case noFrames
        case noGPUTimestamps
        case executionFailed

        public var errorDescription: String? {
            switch self {
            case .invalidConfiguration: return "Shared-path profiling requires nonnegative warmups and measured iterations."
            case .noSamples: return "Shared-path profiling produced no samples."
            case .noDevice: return "No Metal device is available for shared-path profiling."
            case .noFrames: return "The profiling corpus is empty."
            case .noGPUTimestamps: return "The profiler received no GPU timestamp samples."
            case .executionFailed: return "A shared-path profiling command failed."
            }
        }
    }

    private let configuration: Configuration
    private let coefficients: MobileNetV2StemCoefficients
    private let tail: CoreMLMobileNetV2TailAdapter
    private let corpus: MobileNetV2Corpus

    public init(configuration: Configuration = .quick, coefficientsURL: URL, tail: CoreMLMobileNetV2TailAdapter, corpus: MobileNetV2Corpus) throws {
        self.configuration = configuration
        self.coefficients = try MobileNetV2StemCoefficients.load(from: coefficientsURL)
        self.tail = tail
        self.corpus = corpus
    }

    public func run(device: MTLDevice? = MTLCreateSystemDefaultDevice()) throws -> Measurement {
        guard let device else { throw Error.noDevice }
        let frames = try corpus.loadFrames()
        guard !frames.isEmpty else { throw Error.noFrames }
        let inputFactory = try MetalRGBBaseline(device: device)
        let b2 = try MetalMobileNetV2RGBPipeline(device: device, coefficients: coefficients)
        let c1 = try MetalMobileNetV2NativeStem(device: device, coefficients: coefficients)
        let inputs = try frames.map {
            try inputFactory.makeNV12Textures(width: MobileNetV2Corpus.inputWidth, height: MobileNetV2Corpus.inputHeight, yPlaneBytes: $0.yPlaneBytes, uvPlaneBytes: $0.uvPlaneBytes)
        }
        let b2RGB = try b2.makeNormalizedRGBCHWBuffer()
        let b2Activation = try b2.makeActivationBuffer()
        let c1Activation = try c1.makeActivationBuffer()
        let b2Shared = try BufferBackedMultiArray(buffer: b2Activation, shape: MetalMobileNetV2NativeStem.activationShape)
        let c1Shared = try BufferBackedMultiArray(buffer: c1Activation, shape: MetalMobileNetV2NativeStem.activationShape)

        for iteration in 0..<configuration.warmupIterations {
            let index = iteration % frames.count
            _ = try executeB2(b2, input: inputs[index], rgb: b2RGB, activation: b2Activation, shared: b2Shared)
            _ = try executeC1(c1, input: inputs[index], activation: c1Activation, shared: c1Shared)
        }

        var bWall: [Double] = []; var cWall: [Double] = []
        var bGPU: [Double] = []; var cGPU: [Double] = []
        var bEncode: [Double] = []; var cEncode: [Double] = []
        var bWait: [Double] = []; var cWait: [Double] = []
        var bTail: [Double] = []; var cTail: [Double] = []
        var bTotal: [Double] = []; var cTotal: [Double] = []
        var bMatches = 0; var maxError = 0.0
        for iteration in 0..<configuration.measuredIterations {
            let index = (configuration.warmupIterations + iteration) % frames.count
            let b = try executeB2(b2, input: inputs[index], rgb: b2RGB, activation: b2Activation, shared: b2Shared)
            let c = try executeC1(c1, input: inputs[index], activation: c1Activation, shared: c1Shared)
            bWall.append(b.timing.totalMilliseconds); cWall.append(c.timing.totalMilliseconds)
            bEncode.append(b.timing.encodeMilliseconds); cEncode.append(c.timing.encodeMilliseconds)
            bWait.append(b.timing.gpuWaitMilliseconds); cWait.append(c.timing.gpuWaitMilliseconds)
            bTail.append(b.tailMilliseconds); cTail.append(c.tailMilliseconds)
            bTotal.append(b.totalMilliseconds); cTotal.append(c.totalMilliseconds)
            if let gpu = b.timing.gpuExecutionMilliseconds { bGPU.append(gpu) }
            if let gpu = c.timing.gpuExecutionMilliseconds { cGPU.append(gpu) }
            if b.label == c.label { bMatches += 1 }
            let bFeatures = try b2.readActivation(from: b2Activation)
            let cFeatures = try c1.readActivation(from: c1Activation)
            maxError = max(maxError, zip(bFeatures, cFeatures).map { abs(Double($0 - $1)) }.max() ?? 0)
        }
        guard !bGPU.isEmpty, !cGPU.isEmpty else { throw Error.noGPUTimestamps }
        return Measurement(
            schemaVersion: 1,
            status: "r7_final_shared_path_profiler",
            commit: ProcessInfo.processInfo.environment["PF_GIT_COMMIT"],
            environment: EnvironmentSnapshot(),
            command: ProcessInfo.processInfo.environment["PF_PROFILE_COMMAND"] ?? "./pf profile mobilenetv2 shared",
            configuration: configuration,
            pipelineB2Shared: try makePathMeasurement(wall: bWall, gpu: bGPU, encode: bEncode, wait: bWait, tail: bTail, total: bTotal),
            pipelineC1Shared: try makePathMeasurement(wall: cWall, gpu: cGPU, encode: cEncode, wait: cWait, tail: cTail, total: cTotal),
            top1Agreement: Double(bMatches) / Double(configuration.measuredIterations),
            activationMaxAbsoluteError: maxError,
            validationSampleCount: configuration.measuredIterations,
            deviceName: device.name,
            deviceClass: String(describing: type(of: device)),
            requestedCoreMLComputeUnits: tail.computeUnitsPolicyLabel,
            comparison: "Exact accepted R7 B2-shared Float32 CHW materialized-RGB path versus C1-shared Float32 native-plane path; profiling is separate from the five-batch final benchmark.",
            resources: ResourceEvidence(
                b2RGBLogicalPayloadBytes: 224 * 224 * 3 * MemoryLayout<Float>.stride,
                b2RGBMetalAllocatedBytes: b2RGB.allocatedSize,
                c1RGBLogicalPayloadBytes: 0,
                c1RGBMetalAllocatedBytes: 0,
                cpuElementByElementActivationCopyBytes: 0,
                c1RGBResourceStatement: "C1 allocates no normalized RGB buffer; only its required activation buffer is retained."
            ),
            persistentActivationHandoff: ActivationHandoffEvidence(
                shape: MetalMobileNetV2NativeStem.activationShape,
                strides: [112 * 112, 112, 1],
                elementType: "Float32",
                b2BufferLengthBytes: b2Activation.length,
                c1BufferLengthBytes: c1Activation.length,
                bridge: "BufferBackedMultiArray(dataPointer:) retained over each persistent MTLBuffer; same Core ML tail adapter for B2 and C1."
            ),
            sourceSymbols: SourceSymbols(
                b2Pipeline: "MetalMobileNetV2RGBPipeline.executeCHWTimed / encodeCHWConversion / encodeCHWStem",
                c1Pipeline: "MetalMobileNetV2NativeStem.executeTimed / encode",
                sharedTail: "CoreMLMobileNetV2TailAdapter.predict(sharedActivation:)",
                b2Shader: "Sources/PlaneFuseCore/Shaders/NV12MobileNetV2RGB.metal (nv12ToMobileNetV2NormalizedRGBCHW, mobileNetV2RGBCHWStem)",
                c1Shader: "Sources/PlaneFuseCore/Shaders/NV12MobileNetV2Stem.metal (nv12ToMobileNetV2Stem)"
            ),
            trace: TraceEvidence(
                status: ProcessInfo.processInfo.environment["PF_PROFILE_TRACE_STATUS"] ?? "capture-required",
                format: ProcessInfo.processInfo.environment["PF_PROFILE_TRACE_FORMAT"] ?? "Metal System Trace",
                rawTracePath: ProcessInfo.processInfo.environment["PF_PROFILE_TRACE_PATH"] ?? "proof/profiler/r7-b2-c1-shared.trace",
                exportedSummaryPath: ProcessInfo.processInfo.environment["PF_PROFILE_TRACE_SUMMARY"],
                captureCommand: ProcessInfo.processInfo.environment["PF_PROFILE_TRACE_COMMAND"] ?? "xcrun xctrace record --template 'Metal System Trace' --output proof/profiler/r7-b2-c1-shared.trace --launch -- <release planefuse profile mobilenetv2 shared binary>"
            )
        )
    }

    private struct CandidateResult {
        let timing: MetalMobileNetV2RGBPipeline.ExecutionTiming
        let label: String?
        let tailMilliseconds: Double
        let totalMilliseconds: Double
    }

    private func executeB2(_ b2: MetalMobileNetV2RGBPipeline, input: MetalRGBBaseline.NV12Textures, rgb: MTLBuffer, activation: MTLBuffer, shared: BufferBackedMultiArray) throws -> CandidateResult {
        let start = ProcessInfo.processInfo.systemUptime
        let timing = try b2.executeCHWTimed(input, normalizedRGB: rgb, into: activation)
        let tailStart = ProcessInfo.processInfo.systemUptime
        let probabilities = try tail.predict(sharedActivation: shared)
        let end = ProcessInfo.processInfo.systemUptime
        return CandidateResult(timing: timing, label: Self.topLabel(probabilities), tailMilliseconds: (end - tailStart) * 1_000, totalMilliseconds: (end - start) * 1_000)
    }

    private func executeC1(_ c1: MetalMobileNetV2NativeStem, input: MetalRGBBaseline.NV12Textures, activation: MTLBuffer, shared: BufferBackedMultiArray) throws -> CandidateResult {
        let start = ProcessInfo.processInfo.systemUptime
        let timing = try c1.executeTimed(input, into: activation)
        let tailStart = ProcessInfo.processInfo.systemUptime
        let probabilities = try tail.predict(sharedActivation: shared)
        let end = ProcessInfo.processInfo.systemUptime
        return CandidateResult(timing: MetalMobileNetV2RGBPipeline.ExecutionTiming(encodeMilliseconds: timing.encodeMilliseconds, gpuWaitMilliseconds: timing.gpuWaitMilliseconds, gpuExecutionMilliseconds: timing.gpuExecutionMilliseconds, totalMilliseconds: timing.totalMilliseconds), label: Self.topLabel(probabilities), tailMilliseconds: (end - tailStart) * 1_000, totalMilliseconds: (end - start) * 1_000)
    }

    private func makePathMeasurement(wall: [Double], gpu: [Double], encode: [Double], wait: [Double], tail: [Double], total: [Double]) throws -> PathMeasurement {
        PathMeasurement(wallFrontend: try Statistics(wall), gpuExecution: try Statistics(gpu), gpuTimestampSamples: gpu.count, encode: try Statistics(encode), synchronizationWait: try Statistics(wait), tailPrediction: try Statistics(tail), inputToResult: try Statistics(total))
    }

    private static func topLabel(_ probabilities: [String: Double]) -> String? {
        probabilities.max { lhs, rhs in lhs.value == rhs.value ? lhs.key > rhs.key : lhs.value < rhs.value }?.key
    }
}
