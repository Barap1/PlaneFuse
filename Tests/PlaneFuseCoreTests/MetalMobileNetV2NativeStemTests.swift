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
}
