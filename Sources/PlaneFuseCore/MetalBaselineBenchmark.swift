import Foundation
import Metal

/// A deterministic quick measurement for Pipeline B's NV12-to-normalized-RGBA
/// frontend. This is an isolated frontend measurement, not an A/B/C result.
public struct MetalBaselineBenchmark {
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
    }

    public struct Measurement: Codable, Equatable {
        public let frontendP50Milliseconds: Double
        public let frontendP95Milliseconds: Double
        public let frontendMeanMilliseconds: Double
        public let measuredIterations: Int
        public let warmupIterations: Int
        public let width: Int
        public let height: Int
        public let inputByteCount: Int
        public let outputIntermediateByteCount: Int
        public let outputAllocatedBytes: Int?
        public let deviceName: String
        public let deviceClass: String

        public init(
            frontendP50Milliseconds: Double,
            frontendP95Milliseconds: Double,
            frontendMeanMilliseconds: Double,
            measuredIterations: Int,
            warmupIterations: Int,
            width: Int,
            height: Int,
            inputByteCount: Int,
            outputIntermediateByteCount: Int,
            outputAllocatedBytes: Int?,
            deviceName: String,
            deviceClass: String
        ) {
            self.frontendP50Milliseconds = frontendP50Milliseconds
            self.frontendP95Milliseconds = frontendP95Milliseconds
            self.frontendMeanMilliseconds = frontendMeanMilliseconds
            self.measuredIterations = measuredIterations
            self.warmupIterations = warmupIterations
            self.width = width
            self.height = height
            self.inputByteCount = inputByteCount
            self.outputIntermediateByteCount = outputIntermediateByteCount
            self.outputAllocatedBytes = outputAllocatedBytes
            self.deviceName = deviceName
            self.deviceClass = deviceClass
        }
    }

    public enum Error: Swift.Error, LocalizedError, Equatable {
        case noDevice
        case invalidConfiguration

        public var errorDescription: String? {
            switch self {
            case .noDevice:
                return "No Metal device is available for the Pipeline B benchmark."
            case .invalidConfiguration:
                return "Benchmark configuration must use positive even dimensions and positive iteration counts."
            }
        }
    }

    public let configuration: Configuration

    public init(configuration: Configuration = .quick) {
        self.configuration = configuration
    }

    /// Returns the deterministic 8-bit NV12 fixture used by the benchmark.
    /// The fixture is generated arithmetically, so it has no random or device state.
    public static func deterministicNV12Fixture(
        width: Int,
        height: Int
    ) -> (yPlaneBytes: [UInt8], uvPlaneBytes: [UInt8]) {
        let yCount = width * height
        let uvCount = yCount / 2
        let y = (0..<yCount).map { index in
            UInt8((index &* 17 &+ (index / max(1, width)) &* 31 &+ 16) & 0xFF)
        }
        let uv = (0..<uvCount).map { index in
            UInt8((index &* 29 &+ (index / max(1, width / 2)) &* 7 &+ 37) & 0xFF)
        }
        return (y, uv)
    }

    /// Runs reusable Pipeline B work. p95 uses deterministic nearest-rank:
    /// `sorted[ceil(0.95 * n) - 1]`.
    public func run(device: MTLDevice? = MTLCreateSystemDefaultDevice()) throws -> Measurement {
        guard let device else { throw Error.noDevice }
        guard configuration.warmupIterations > 0,
              configuration.measuredIterations > 0,
              configuration.width > 0,
              configuration.height > 0,
              configuration.width.isMultiple(of: 2),
              configuration.height.isMultiple(of: 2) else {
            throw Error.invalidConfiguration
        }

        let baseline = try MetalRGBBaseline(device: device)
        let fixture = Self.deterministicNV12Fixture(width: configuration.width, height: configuration.height)
        let input = try baseline.makeNV12Textures(
            width: configuration.width,
            height: configuration.height,
            yPlaneBytes: fixture.yPlaneBytes,
            uvPlaneBytes: fixture.uvPlaneBytes
        )
        let output = try baseline.makeRGBA32FloatTexture(
            width: configuration.width,
            height: configuration.height
        )

        for _ in 0..<configuration.warmupIterations {
            _ = try baseline.execute(input, into: output)
        }

        var durations: [Double] = []
        durations.reserveCapacity(configuration.measuredIterations)
        for _ in 0..<configuration.measuredIterations {
            let start = ProcessInfo.processInfo.systemUptime
            _ = try baseline.execute(input, into: output)
            let end = ProcessInfo.processInfo.systemUptime
            durations.append((end - start) * 1_000.0)
        }

        let sorted = durations.sorted()
        let p50 = nearestRank(sorted, percentile: 0.50)
        let p95 = nearestRank(sorted, percentile: 0.95)
        let mean = durations.reduce(0, +) / Double(durations.count)
        return Measurement(
            frontendP50Milliseconds: p50,
            frontendP95Milliseconds: p95,
            frontendMeanMilliseconds: mean,
            measuredIterations: configuration.measuredIterations,
            warmupIterations: configuration.warmupIterations,
            width: configuration.width,
            height: configuration.height,
            inputByteCount: fixture.yPlaneBytes.count + fixture.uvPlaneBytes.count,
            outputIntermediateByteCount: configuration.width * configuration.height * 4 * MemoryLayout<Float>.stride,
            outputAllocatedBytes: output.allocatedSize,
            deviceName: device.name,
            deviceClass: String(describing: type(of: device))
        )
    }

    private func nearestRank(_ sorted: [Double], percentile: Double) -> Double {
        let rank = max(1, Int(ceil(percentile * Double(sorted.count))))
        return sorted[rank - 1]
    }
}
