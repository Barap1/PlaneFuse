import Metal
import XCTest
@testable import PlaneFuseCore

final class MetalRGBBaselineTests: XCTestCase {
    func testNV12FixtureMatchesBT601ReferenceMath() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal-specific test skipped: no Metal device is available.")
        }

        let baseline = try MetalRGBBaseline(device: device)
        let input = try baseline.makeNV12Textures(
            width: 2,
            height: 2,
            yPlaneBytes: [16, 81, 145, 235],
            uvPlaneBytes: [90, 240]
        )
        let output = try baseline.makeRGBA32FloatTexture(width: 2, height: 2)

        _ = try baseline.execute(input, into: output)
        let values = try baseline.readRGBA32Float(from: output)

        let referenceRGB = NV12Semantics.bt601VideoRange.decodeRGB(y: 81, cb: 90, cr: 240)
        let expected = RGBNormalization(
            mean: [0.485, 0.456, 0.406],
            standardDeviation: [0.229, 0.224, 0.225]
        ).apply(to: referenceRGB)
        let pixelOffset = 4 // Pixel (1, 0) in RGBA order.

        for channel in 0..<3 {
            XCTAssertEqual(values[pixelOffset + channel], Float(expected[channel]), accuracy: 0.00001)
        }
        XCTAssertEqual(values[pixelOffset + 3], 1.0, accuracy: 0.00001)
    }
}
