import Foundation
import Metal

/// Stem-only characterization of the C1-SR source-reuse schedule. This is not
/// an end-to-end model benchmark: it varies active output channels while
/// keeping the source planes, geometry, coefficients, and output layout fixed.
public final class SourceReuseScalingBenchmark {
    public static let widths = [8, 16, 24, 32, 40, 48]
    public static let warmupIterations = 4
    public static let measuredIterations = 4
    public static let samplesPerBatch = 16

    public struct Timing: Codable, Equatable {
        public let wallMilliseconds: [Double]
        public let gpuMilliseconds: [Double]

        public init(wallMilliseconds: [Double], gpuMilliseconds: [Double]) {
            self.wallMilliseconds = wallMilliseconds
            self.gpuMilliseconds = gpuMilliseconds
        }
    }

    public struct BatchWidthResult: Codable, Equatable {
        public let activeOutputChannels: Int
        public let sourceSampleIDs: [String]
        public let c1: Timing
        public let c1SourceReuse: Timing
        public let activationMaxAbsoluteError: Double
    }

    public struct BatchResult: Codable, Equatable {
        public let schemaVersion: Int
        public let status: String
        public let commit: String?
        public let batchIndex: Int
        public let orderPhase: Int
        public let warmupIterations: Int
        public let measuredIterations: Int
        public let inputCount: Int
        public let widths: [BatchWidthResult]
        public let fixedSourceSet: String
        public let sourceSetDigest: String

        public init(batchIndex: Int, orderPhase: Int, widths: [BatchWidthResult], sourceSetDigest: String) {
            self.schemaVersion = 1
            self.status = "source_reuse_scaling_stem_only_batch"
            self.commit = ProcessInfo.processInfo.environment["PF_GIT_COMMIT"]
            self.batchIndex = batchIndex
            self.orderPhase = orderPhase
            self.warmupIterations = SourceReuseScalingBenchmark.warmupIterations
            self.measuredIterations = SourceReuseScalingBenchmark.measuredIterations
            self.inputCount = SourceReuseScalingBenchmark.samplesPerBatch
            self.widths = widths
            self.fixedSourceSet = "proof/m5-validation-corpus.json; deterministic manifest order"
            self.sourceSetDigest = sourceSetDigest
        }
    }

    public enum Error: Swift.Error, LocalizedError {
        case invalidBatch
        case invalidCorpus
        case parityFailed(width: Int, error: Double)

        public var errorDescription: String? {
            switch self {
            case .invalidBatch: return "Source-reuse scaling requires batch indices 0, 1, or 2 and order phase 0 or 1."
            case .invalidCorpus: return "Source-reuse scaling requires at least 48 fixed corpus frames."
            case let .parityFailed(width, error): return "Source-reuse scaling parity failed at \(width) channels: max error \(error)."
            }
        }
    }

    private let device: MTLDevice
    private let corpus: MobileNetV2Corpus
    private let stem: MetalMobileNetV2NativeStem

    public init(
        device: MTLDevice? = MTLCreateSystemDefaultDevice(),
        coefficientsURL: URL,
        corpus: MobileNetV2Corpus
    ) throws {
        guard let device else { throw Error.invalidCorpus }
        self.device = device
        self.corpus = corpus
        self.stem = try MetalMobileNetV2NativeStem(device: device, coefficientsURL: coefficientsURL)
    }

    public func run(batchIndex: Int, orderPhase: Int) throws -> BatchResult {
        guard (0..<3).contains(batchIndex), orderPhase == 0 || orderPhase == 1 else { throw Error.invalidBatch }
        let frames = try corpus.loadFrames()
        guard frames.count >= 48 else { throw Error.invalidCorpus }
        let start = batchIndex * Self.samplesPerBatch
        let selected = Array(frames[start..<(start + Self.samplesPerBatch)])
        let textureFactory = try MetalRGBBaseline(device: device)
        let inputs = try selected.map {
            try textureFactory.makeNV12Textures(width: 224, height: 224, yPlaneBytes: $0.yPlaneBytes, uvPlaneBytes: $0.uvPlaneBytes)
        }
        let sourceIDs = selected.map(\.id)
        let sourceDigest = sourceIDs.joined(separator: "|")
        var results: [BatchWidthResult] = []
        for width in Self.widths {
            let c1Activation = try stem.makeActivationBuffer()
            let srActivation = try stem.makeActivationBuffer()
            var c1Wall: [Double] = []; var c1GPU: [Double] = []
            var srWall: [Double] = []; var srGPU: [Double] = []
            c1Wall.reserveCapacity(Self.samplesPerBatch * Self.measuredIterations)
            srWall.reserveCapacity(Self.samplesPerBatch * Self.measuredIterations)

            for input in inputs {
                for _ in 0..<Self.warmupIterations {
                    _ = try stem.executeScaled(input, activeOutputChannels: width, sourceReuse: false, into: c1Activation)
                    _ = try stem.executeScaled(input, activeOutputChannels: width, sourceReuse: true, into: srActivation)
                }
            }

            var maxError = 0.0
            for (frameIndex, input) in inputs.enumerated() {
                _ = try stem.executeScaled(input, activeOutputChannels: width, sourceReuse: false, into: c1Activation)
                let reference = try stem.readActivation(from: c1Activation)
                _ = try stem.executeScaled(input, activeOutputChannels: width, sourceReuse: true, into: srActivation)
                let candidate = try stem.readActivation(from: srActivation)
                let count = width * 112 * 112
                for index in 0..<count { maxError = max(maxError, abs(Double(reference[index]) - Double(candidate[index]))) }
                if maxError > 1e-4 { throw Error.parityFailed(width: width, error: maxError) }
                _ = frameIndex
            }

            for iteration in 0..<Self.measuredIterations {
                for input in inputs {
                    let c1First = (orderPhase + iteration) % 2 == 0
                    if c1First {
                        let c1 = try stem.executeScaled(input, activeOutputChannels: width, sourceReuse: false, into: c1Activation)
                        let sr = try stem.executeScaled(input, activeOutputChannels: width, sourceReuse: true, into: srActivation)
                        append(c1, wall: &c1Wall, gpu: &c1GPU); append(sr, wall: &srWall, gpu: &srGPU)
                    } else {
                        let sr = try stem.executeScaled(input, activeOutputChannels: width, sourceReuse: true, into: srActivation)
                        let c1 = try stem.executeScaled(input, activeOutputChannels: width, sourceReuse: false, into: c1Activation)
                        append(c1, wall: &c1Wall, gpu: &c1GPU); append(sr, wall: &srWall, gpu: &srGPU)
                    }
                }
            }
            results.append(BatchWidthResult(
                activeOutputChannels: width, sourceSampleIDs: sourceIDs,
                c1: Timing(wallMilliseconds: c1Wall, gpuMilliseconds: c1GPU),
                c1SourceReuse: Timing(wallMilliseconds: srWall, gpuMilliseconds: srGPU),
                activationMaxAbsoluteError: maxError
            ))
        }
        return BatchResult(batchIndex: batchIndex, orderPhase: orderPhase, widths: results, sourceSetDigest: sourceDigest)
    }

    private func append(_ timing: MetalMobileNetV2NativeStem.ExecutionTiming, wall: inout [Double], gpu: inout [Double]) {
        wall.append(timing.totalMilliseconds)
        if let duration = timing.gpuExecutionMilliseconds { gpu.append(duration) }
    }
}
