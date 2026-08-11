import Metal
import XCTest
@testable import PlaneFuseCore

final class MetalMobileNetV2NativeStemTests: XCTestCase {
    func testNativeStemCompilesAndWritesCHWReLU6Activation() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("Metal is unavailable.") }
        let coefficients = MobileNetV2StemCoefficients(
            convolutionWeights: [Double](repeating: 0, count: 48 * 3 * 3 * 3),
            batchNormScale: [Double](repeating: 1, count: 48),
            batchNormBias: [Double](repeating: 1.25, count: 48),
            batchNormMean: [Double](repeating: 0, count: 48),
            batchNormVariance: [Double](repeating: 1, count: 48), batchNormEpsilon: 0
        )
        let inputFactory = try MetalRGBBaseline(device: device)
        let input = try inputFactory.makeNV12Textures(
            width: 224, height: 224,
            yPlaneBytes: [UInt8](repeating: 128, count: 224 * 224),
            uvPlaneBytes: [UInt8](repeating: 128, count: 224 * 224 / 2)
        )
        let stem = try MetalMobileNetV2NativeStem(device: device, coefficients: coefficients)
        let activation = try stem.makeActivationBuffer()
        try stem.execute(input, into: activation)
        let values = try stem.readActivation(from: activation)
        XCTAssertEqual(values.count, 48 * 112 * 112)
        XCTAssertTrue(values.allSatisfy { abs($0 - 1.25) < 0.000001 })
    }

    func testR75SourceReuseMatchesAcceptedC1Activation() throws {
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
        let pixelCount = 224 * 224
        let y: [UInt8] = (0..<pixelCount).map { index in UInt8(16 + (index * 37) % 220) }
        let uv: [UInt8] = (0..<(pixelCount / 2)).map { index in UInt8(16 + (index * 53) % 225) }
        let input = try inputFactory.makeNV12Textures(width: 224, height: 224, yPlaneBytes: y, uvPlaneBytes: uv)
        let stem = try MetalMobileNetV2NativeStem(device: device, coefficients: coefficients)
        let accepted = try stem.makeActivationBuffer()
        let sourceReuse = try stem.makeActivationBuffer()
        try stem.execute(input, into: accepted)
        _ = try stem.executeSourceReuseTimed(input, into: sourceReuse)
        let expected = try stem.readActivation(from: accepted)
        let actual = try stem.readActivation(from: sourceReuse)
        let maxError = zip(expected, actual).reduce(Float.zero) { max($0, abs($1.0 - $1.1)) }
        XCTAssertLessThanOrEqual(maxError, FairABCBenchmark.featureParityTolerance)
    }
}
