import Metal
import XCTest
@testable import PlaneFuseCore

final class MetalMobileNetV2RGBPipelineTests: XCTestCase {
    func testOneSubmissionRGBPipelineMatchesNativeStemCHWActivation() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("Metal is unavailable.") }
        let weights: [Double] = (0..<(48 * 27)).map { index in Double((index % 13) - 6) / 97.0 }
        let scale: [Double] = (0..<48).map { index in 0.7 + Double(index % 5) * 0.1 }
        let bias: [Double] = (0..<48).map { index in Double((index % 7) - 3) / 10.0 }
        let mean: [Double] = (0..<48).map { index in Double((index % 3) - 1) / 20.0 }
        let variance: [Double] = (0..<48).map { index in 0.8 + Double(index % 4) / 10.0 }
        let coefficients = MobileNetV2StemCoefficients(
            convolutionWeights: weights, batchNormScale: scale, batchNormBias: bias,
            batchNormMean: mean, batchNormVariance: variance, batchNormEpsilon: 0
        )
        let inputFactory = try MetalRGBBaseline(device: device)
        var y = [UInt8](); y.reserveCapacity(224 * 224)
        for index in 0..<(224 * 224) { y.append(UInt8(16 + (index * 37) % 220)) }
        var uv = [UInt8](); uv.reserveCapacity(224 * 224 / 2)
        for index in 0..<(224 * 224 / 2) { uv.append(UInt8(16 + (index * 53) % 225)) }
        let input = try inputFactory.makeNV12Textures(width: 224, height: 224, yPlaneBytes: y, uvPlaneBytes: uv)
        let baseline = try MetalMobileNetV2RGBPipeline(device: device, coefficients: coefficients)
        let native = try MetalMobileNetV2NativeStem(device: device, coefficients: coefficients)
        let rgb = try baseline.makeNormalizedRGBTexture()
        let bActivation = try baseline.makeActivationBuffer()
        let cActivation = try native.makeActivationBuffer()

        // B uses one command buffer containing conversion + RGB stem; C uses one
        // command buffer containing the native stem, so submissions are equal.
        try baseline.execute(input, normalizedRGB: rgb, into: bActivation)
        try native.execute(input, into: cActivation)
        let b = try baseline.readActivation(from: bActivation)
        let c = try native.readActivation(from: cActivation)
        let maxError = zip(b, c).reduce(Float.zero) { max($0, abs($1.0 - $1.1)) }
        let requiredRGBBytes = 224 * 224 * 4 * MemoryLayout<Float>.stride
        XCTAssertGreaterThanOrEqual(rgb.allocatedSize, requiredRGBBytes)
        XCTAssertLessThanOrEqual(maxError, FairABCBenchmark.featureParityTolerance)

        let measurement = try MobileNetV2StemBenchmark.run(
            baseline: baseline, native: native, input: input, normalizedRGB: rgb,
            baselineActivation: bActivation, nativeActivation: cActivation,
            warmupIterations: 0, measuredIterations: 2
        )
        XCTAssertEqual(measurement.pipelineBMilliseconds.count, 2)
        XCTAssertEqual(measurement.pipelineCMilliseconds.count, 2)
        XCTAssertEqual(measurement.pipelineBRGBIntermediateBytes, requiredRGBBytes)
        XCTAssertEqual(measurement.pipelineCRGBIntermediateBytes, 0)
        XCTAssertTrue(measurement.commandBufferMethodology.contains("one submission"))
    }
}
