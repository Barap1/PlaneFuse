import XCTest
@testable import PlaneFuseCore

final class NativePlaneCompilerTests: XCTestCase {
    func testMobileNetV2ConfigurationIsValid() throws {
        let configuration = NativePlaneStemConfiguration.mobileNetV2()

        try configuration.validate()
        XCTAssertEqual(configuration.outputChannels, 48)
        XCTAssertTrue(configuration.usesBatchNormalization)
        XCTAssertTrue(configuration.usesReLU6)
        XCTAssertEqual(configuration.paddingMode, "same_bottom_right")
        XCTAssertEqual(configuration.normalization.mean, [0.5, 0.5, 0.5])
        XCTAssertEqual(configuration.normalization.standardDeviation, [0.5, 0.5, 0.5])
    }

    func testInvalidGeometryHasPreciseError() {
        let configuration = NativePlaneStemConfiguration.mobileNetV2().with(inputWidth: 192)

        XCTAssertThrowsError(try configuration.validate()) { error in
            XCTAssertEqual(error as? NativePlaneStemValidationError,
                           .invalidInputGeometry(width: 192, height: 224))
        }
    }

    func testUnsupportedPaddingHasPreciseError() {
        let configuration = NativePlaneStemConfiguration.mobileNetV2().with(paddingMode: "valid")

        XCTAssertThrowsError(try configuration.validate()) { error in
            XCTAssertEqual(error as? NativePlaneStemValidationError, .unsupportedPadding("valid"))
        }
    }

    func testConfigurationSerializesAndRoundTrips() throws {
        let configuration = NativePlaneStemConfiguration.mobileNetV2()
        let data = try JSONEncoder().encode(configuration)
        let decoded = try JSONDecoder().decode(NativePlaneStemConfiguration.self, from: data)

        XCTAssertEqual(decoded, configuration)
    }

    func testParameterizedReferenceFixtureUsesSameCompatibilityContract() throws {
        let fixture = NativePlaneStemConfiguration.referenceFixture()

        try fixture.validate()
        XCTAssertEqual(fixture.outputChannels, 16)
        XCTAssertNotEqual(fixture.modelLineage, NativePlaneStemConfiguration.mobileNetV2().modelLineage)
    }

    func testInspectorProducesMachineReadableCompatibilityResult() {
        let result = NativePlaneStemInspection.inspect(.mobileNetV2())

        XCTAssertTrue(result.compatible)
        XCTAssertNil(result.rejectionReason)
        XCTAssertTrue(result.supportedSemantics.contains("NV12 8-bit bi-planar Y+UV input"))
    }

    func testNearestSitedPolyphaseCompilerMatchesIndependentReferenceAcrossPhasesAndEdges() {
        let stem = Conv3x3Stride2BatchNormReLU6Stem(
            outputChannels: 1,
            convolutionWeights: (0..<27).map { Double(($0 % 7) - 3) * 0.01 },
            convolutionBias: [0], batchNormScale: [1], batchNormBias: [0],
            batchNormMean: [0], batchNormVariance: [1], batchNormEpsilon: 0
        )
        let normalization = RGBNormalization(mean: [0.5, 0.5, 0.5], standardDeviation: [0.5, 0.5, 0.5])
        let polyphase = NativePlaneConv3x3Compiler.compilePolyphase(semantics: .bt601VideoRange, normalization: normalization, stem: stem)
        let perTap = NativePlaneConv3x3Compiler.compile(semantics: .bt601VideoRange, normalization: normalization, stem: stem)
        var flatY: [UInt8] = []; for index in 0..<24 { flatY.append(UInt8((index * 37 + 3) % 256)) }
        var flatUV: [UInt8] = []; for index in 0..<6 {
            flatUV.append(UInt8((index * 29 + 11) % 256)); flatUV.append(UInt8((index * 53 + 97) % 256))
        }
        var edgeY: [UInt8] = []; for index in 0..<36 {
            edgeY.append(index % 3 == 0 ? 16 : (index % 3 == 1 ? 128 : 235))
        }
        var edgeUV: [UInt8] = []; for index in 0..<9 {
            edgeUV.append(UInt8((index % 4) * 43 + 1)); edgeUV.append(UInt8(255 - (index % 4) * 31))
        }
        let cases: [(Int, Int, [UInt8], [UInt8])] = [
            (4, 4, [UInt8](repeating: 128, count: 16), [UInt8](repeating: 128, count: 8)),
            (6, 4, flatY, flatUV),
            (6, 6, edgeY, edgeUV)
        ]
        for (width, height, y, uv) in cases {
            let independent = ReferenceConv3x3Stem.evaluate(
                yPlane: y, uvPlane: uv, width: width, height: height,
                semantics: .bt601VideoRange, normalization: normalization, stem: stem
            )
            let compiled = polyphase.evaluate(yPlane: y, uvPlane: uv, width: width, height: height, semantics: .bt601VideoRange)
            let perTapResult = perTap.evaluate(yPlane: y, uvPlane: uv, width: width, height: height, semantics: .bt601VideoRange)
            XCTAssertEqual(independent.count, compiled.count)
            for (lhs, rhs) in zip(independent, compiled) { XCTAssertEqual(lhs, rhs, accuracy: 1e-9) }
            for (lhs, rhs) in zip(independent, perTapResult) { XCTAssertEqual(lhs, rhs, accuracy: 1e-9) }
        }
        XCTAssertEqual(polyphase.chromaWeights.count, 1 * 4 * 2)
        XCTAssertEqual(perTap.operatorMetadata.uvReadInstructions, 9)
        XCTAssertEqual(polyphase.operatorMetadata.uvReadInstructions, 4)
        XCTAssertEqual(polyphase.operatorMetadata.weightedMultiplications, 17)
    }
}

private extension NativePlaneStemSpec {
    func with(inputWidth: Int? = nil, paddingMode: String? = nil) -> Self {
        Self(
            inputWidth: inputWidth ?? self.inputWidth, inputHeight: self.inputHeight,
            outputWidth: outputWidth, outputHeight: outputHeight,
            kernelWidth: kernelWidth, kernelHeight: kernelHeight,
            strideX: strideX, strideY: strideY, paddingMode: paddingMode ?? self.paddingMode,
            normalization: normalization, outputChannels: outputChannels,
            usesBatchNormalization: usesBatchNormalization, usesReLU6: usesReLU6,
            coefficientLineage: coefficientLineage, modelLineage: modelLineage
        )
    }
}
