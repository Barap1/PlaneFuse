import Metal
import XCTest
@testable import PlaneFuseCore

final class MetalNativeStemTests: XCTestCase {
    func testNV12FixtureMatchesReferenceStemForAllFeatureChannelsAcrossMultipleUVRows() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal-specific test skipped: no Metal device is available.")
        }

        let inputFactory = try MetalRGBBaseline(device: device)
        let input = try inputFactory.makeNV12Textures(
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
        let nativeStem = try MetalNativeStem(device: device)
        let output = try nativeStem.makeFeatureTexture(width: input.width, height: input.height)

        _ = try nativeStem.execute(input, into: output)
        let values = readRGBA32Float(from: output)

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

    func testNativeStemRejectsNonFourChannelStem() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal-specific test skipped: no Metal device is available.")
        }

        let invalidStem = OneByOneStem(weights: [0.1, 0.2, 0.3], bias: [0])
        XCTAssertThrowsError(try MetalNativeStem(device: device, stem: invalidStem)) { error in
            XCTAssertEqual(error as? MetalNativeStem.Error, .unsupportedOutputChannelCount(1))
        }
    }

    func testNativeStemRejectsUnsupportedSemanticsBeforeShaderUse() throws {
        let unsupportedSemantics = NV12Semantics(
            name: "nv12-unsupported-fixture",
            yOffset: 0,
            yScale: 255,
            chromaOffset: 128,
            chromaScale: 255,
            rgbFromSource: [
                [1, 0, 0],
                [0, 1, 0],
                [0, 0, 1],
            ]
        )

        XCTAssertThrowsError(try MetalNativeStem(semantics: unsupportedSemantics)) { error in
            XCTAssertEqual(error as? MetalNativeStem.Error, .unsupportedSemantics(unsupportedSemantics))
        }
    }

    private func readRGBA32Float(from texture: MTLTexture) -> [Float] {
        var values = [Float](repeating: 0, count: texture.width * texture.height * 4)
        values.withUnsafeMutableBytes { destination in
            texture.getBytes(
                destination.baseAddress!,
                bytesPerRow: texture.width * MemoryLayout<Float>.stride * 4,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height),
                mipmapLevel: 0
            )
        }
        return values
    }
}
