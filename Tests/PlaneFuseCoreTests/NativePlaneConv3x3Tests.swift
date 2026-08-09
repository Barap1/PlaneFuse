import XCTest
@testable import PlaneFuseCore

final class NativePlaneConv3x3Tests: XCTestCase {
    func testSameBottomRightUsesTopLeftAtOutputOriginAndPadsOnlyBottomRight() {
        let padding = Conv3x3Stride2PaddingMode.sameBottomRight
        XCTAssertEqual(padding.inputCoordinate(output: 0, kernelTap: 0), 0)
        XCTAssertEqual(padding.inputCoordinate(output: 0, kernelTap: 2), 2)
        XCTAssertEqual(padding.inputCoordinate(output: 111, kernelTap: 0), 222)
        XCTAssertEqual(padding.inputCoordinate(output: 111, kernelTap: 2), 224)
    }

    func testSameBottomRightDoesNotDiscardTheOriginTap() {
        let stem = Conv3x3Stride2BatchNormReLU6Stem(
            outputChannels: 1,
            convolutionWeights: [1, 0, 0, 0, 0, 0, 0, 0, 0,
                                  0, 0, 0, 0, 0, 0, 0, 0, 0,
                                  0, 0, 0, 0, 0, 0, 0, 0, 0],
            convolutionBias: [0], batchNormScale: [1], batchNormBias: [0],
            batchNormMean: [0], batchNormVariance: [1], batchNormEpsilon: 0
        )
        let y: [UInt8] = [235, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16]
        let uv = [UInt8](repeating: 128, count: 8)
        let normalization = RGBNormalization(mean: [0, 0, 0], standardDeviation: [1, 1, 1])
        let reference = ReferenceConv3x3Stem.evaluate(yPlane: y, uvPlane: uv, width: 4, height: 4, semantics: .bt601VideoRange, normalization: normalization, stem: stem)
        XCTAssertEqual(reference[0], 1, accuracy: 1e-12)
    }

    func testCompiledConvBatchNormReLU6MatchesReferenceIncludingZeroPadding() {
        let channels = 2
        let weights = (0..<(channels * 27)).map { Double(($0 % 11) - 5) / 17 }
        let stem = Conv3x3Stride2BatchNormReLU6Stem(
            outputChannels: channels, convolutionWeights: weights, convolutionBias: [0.2, -0.3],
            batchNormScale: [1.2, 0.7], batchNormBias: [0.1, -0.2], batchNormMean: [0.05, -0.1],
            batchNormVariance: [0.8, 1.3], batchNormEpsilon: 1e-5
        )
        let normalization = RGBNormalization(mean: [0.485, 0.456, 0.406], standardDeviation: [0.229, 0.224, 0.225])
        let y: [UInt8] = [16, 81, 145, 235, 32, 96, 160, 224, 48, 112, 176, 208, 64, 128, 192, 220]
        let uv: [UInt8] = [90, 240, 166, 16, 54, 34, 202, 210]
        let reference = ReferenceConv3x3Stem.evaluate(yPlane: y, uvPlane: uv, width: 4, height: 4, semantics: .bt601VideoRange, normalization: normalization, stem: stem)
        let native = NativePlaneConv3x3Compiler.compile(semantics: .bt601VideoRange, normalization: normalization, stem: stem)
            .evaluate(yPlane: y, uvPlane: uv, width: 4, height: 4, semantics: .bt601VideoRange)
        XCTAssertLessThanOrEqual(Parity.maxAbsoluteDifference(reference, native), 1e-12)
    }
}
