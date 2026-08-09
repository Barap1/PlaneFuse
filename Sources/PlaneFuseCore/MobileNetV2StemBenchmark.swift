import Foundation
import Metal

/// Preallocated M5 stem-region comparison. This deliberately measures only the
/// region PlaneFuse changes; model-tail execution belongs in the paired M5
/// end-to-end benchmark once the extracted artifact has passed output agreement.
public struct MobileNetV2StemBenchmark {
    public struct Measurement: Equatable {
        public let pipelineBMilliseconds: [Double]
        public let pipelineCMilliseconds: [Double]
        public let pipelineBRGBIntermediateBytes: Int
        public let pipelineBRGBIntermediateAllocatedBytes: Int
        public let pipelineCRGBIntermediateBytes: Int
        public let commandBufferMethodology: String
    }

    public static let commandBufferMethodology = "B: one command buffer / one submission containing NV12-to-RGBA and RGB 3x3 stem encoders. C: one command buffer / one submission containing the native 3x3 stem encoder."

    public static func run(
        baseline: MetalMobileNetV2RGBPipeline,
        native: MetalMobileNetV2NativeStem,
        input: MetalRGBBaseline.NV12Textures,
        normalizedRGB: MTLTexture,
        baselineActivation: MTLBuffer,
        nativeActivation: MTLBuffer,
        warmupIterations: Int = 10,
        measuredIterations: Int = 30
    ) throws -> Measurement {
        precondition(warmupIterations >= 0 && measuredIterations > 0)
        for iteration in 0..<warmupIterations {
            if iteration.isMultiple(of: 2) {
                try baseline.execute(input, normalizedRGB: normalizedRGB, into: baselineActivation)
                try native.execute(input, into: nativeActivation)
            } else {
                try native.execute(input, into: nativeActivation)
                try baseline.execute(input, normalizedRGB: normalizedRGB, into: baselineActivation)
            }
        }
        var b = [Double](); var c = [Double](); b.reserveCapacity(measuredIterations); c.reserveCapacity(measuredIterations)
        for iteration in 0..<measuredIterations {
            if iteration.isMultiple(of: 2) {
                b.append(try elapsed { try baseline.execute(input, normalizedRGB: normalizedRGB, into: baselineActivation) })
                c.append(try elapsed { try native.execute(input, into: nativeActivation) })
            } else {
                c.append(try elapsed { try native.execute(input, into: nativeActivation) })
                b.append(try elapsed { try baseline.execute(input, normalizedRGB: normalizedRGB, into: baselineActivation) })
            }
        }
        return Measurement(
            pipelineBMilliseconds: b, pipelineCMilliseconds: c,
            pipelineBRGBIntermediateBytes: 224 * 224 * 4 * MemoryLayout<Float>.stride,
            pipelineBRGBIntermediateAllocatedBytes: normalizedRGB.allocatedSize,
            pipelineCRGBIntermediateBytes: 0,
            commandBufferMethodology: commandBufferMethodology
        )
    }

    private static func elapsed(_ operation: () throws -> Void) rethrows -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        try operation()
        return Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    }
}
