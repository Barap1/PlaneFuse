import Metal
import XCTest
@testable import PlaneFuseCore

final class MetalRGBNormalStemTests: XCTestCase {
    func testRGBStemMatchesReferenceStemAfterBaselinePreprocessing() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal-specific test skipped: no Metal device is available.")
        }

        let baseline = try MetalRGBBaseline(device: device)
        let normalizedRGB = try baseline.makeRGBA32FloatTexture(width: 4, height: 4)
        let input = try baseline.makeNV12Textures(
            width: 4,
            height: 4,
            yPlaneBytes: [
                16, 81, 145, 235,
                32, 96, 160, 224,
                48, 112, 176, 208,
                64, 128, 192, 220,
            ],
            uvPlaneBytes: [
                90, 240, 166, 16,
                54, 34, 202, 210,
            ]
        )
        let rgbStem = try MetalRGBNormalStem(device: device)
        let features = try rgbStem.makeFeatureTexture(width: input.width, height: input.height)

        _ = try baseline.execute(input, into: normalizedRGB)
        _ = try rgbStem.execute(normalizedRGB: normalizedRGB, into: features)
        let values = try baseline.readRGBA32Float(from: features)

        let yPlane: [UInt8] = [
            16, 81, 145, 235,
            32, 96, 160, 224,
            48, 112, 176, 208,
            64, 128, 192, 220,
        ]
        let uvPlane: [UInt8] = [
            90, 240, 166, 16,
            54, 34, 202, 210,
        ]
        var maximumAbsoluteError: Float = 0
        for y in 0..<input.height {
            for x in 0..<input.width {
                let pixel = y * input.width + x
                let uvPixel = (y / 2) * (input.width / 2) + (x / 2)
                let expected = ReferenceStem.evaluate(
                    y: yPlane[pixel],
                    cb: uvPlane[uvPixel * 2],
                    cr: uvPlane[uvPixel * 2 + 1],
                    semantics: .bt601VideoRange,
                    normalization: MetalNativeStem.m1FixtureNormalization,
                    stem: MetalNativeStem.m1FixtureStem
                )
                for channel in 0..<4 {
                    maximumAbsoluteError = max(
                        maximumAbsoluteError,
                        abs(values[pixel * 4 + channel] - Float(expected[channel]))
                    )
                }
            }
        }

        XCTAssertLessThanOrEqual(maximumAbsoluteError, 0.00001)
    }

    func testRGBStemRejectsNonFourChannelStem() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal-specific test skipped: no Metal device is available.")
        }

        let invalidStem = OneByOneStem(weights: [0.1, 0.2, 0.3], bias: [0])
        XCTAssertThrowsError(try MetalRGBNormalStem(device: device, stem: invalidStem)) { error in
            XCTAssertEqual(error as? MetalRGBNormalStem.Error, .unsupportedOutputChannelCount(1))
        }
    }
}
