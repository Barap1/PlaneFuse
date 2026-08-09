import Metal
import XCTest
@testable import PlaneFuseCore

final class MobileNetV2PaddingMetalTests: XCTestCase {
    func testBothMetalStemsSampleTopLeftForFirstOutput() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("Metal is unavailable.") }
        var weights = [Double](repeating: 0, count: 48 * 27)
        weights[0] = 1 // output 0, red input, kernel tap (0, 0)
        let coefficients = MobileNetV2StemCoefficients(
            convolutionWeights: weights, batchNormScale: [Double](repeating: 1, count: 48),
            batchNormBias: [Double](repeating: 0, count: 48), batchNormMean: [Double](repeating: 0, count: 48),
            batchNormVariance: [Double](repeating: 1, count: 48), batchNormEpsilon: 0
        )
        let inputFactory = try MetalRGBBaseline(device: device)
        var y = [UInt8](repeating: 16, count: 224 * 224); y[0] = 235
        let input = try inputFactory.makeNV12Textures(width: 224, height: 224, yPlaneBytes: y, uvPlaneBytes: [UInt8](repeating: 128, count: 224 * 224 / 2))
        let b = try MetalMobileNetV2RGBPipeline(device: device, coefficients: coefficients)
        let c = try MetalMobileNetV2NativeStem(device: device, coefficients: coefficients)
        let rgb = try b.makeNormalizedRGBTexture(); let bOutput = try b.makeActivationBuffer(); let cOutput = try c.makeActivationBuffer()
        try b.execute(input, normalizedRGB: rgb, into: bOutput); try c.execute(input, into: cOutput)
        XCTAssertEqual(try b.readActivation(from: bOutput)[0], 1, accuracy: 1e-5)
        XCTAssertEqual(try c.readActivation(from: cOutput)[0], 1, accuracy: 1e-5)
    }
}
