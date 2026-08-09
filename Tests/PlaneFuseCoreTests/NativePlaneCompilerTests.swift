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

    func testNearestSitedPolyphaseCompilerMatchesPerTapReference() {
        let stem = Conv3x3Stride2BatchNormReLU6Stem(
            outputChannels: 1,
            convolutionWeights: (0..<27).map { Double($0 + 1) },
            convolutionBias: [0], batchNormScale: [1], batchNormBias: [0],
            batchNormMean: [0], batchNormVariance: [1], batchNormEpsilon: 0
        )
        let normalization = RGBNormalization(mean: [0.5, 0.5, 0.5], standardDeviation: [0.5, 0.5, 0.5])
        let perTap = NativePlaneConv3x3Compiler.compile(semantics: .bt601VideoRange, normalization: normalization, stem: stem)
        let polyphase = NativePlaneConv3x3Compiler.compilePolyphase(semantics: .bt601VideoRange, normalization: normalization, stem: stem)
        let y = [UInt8](repeating: 128, count: 16)
        let uv: [UInt8] = [128, 128, 140, 110, 120, 145, 150, 100]
        let reference = perTap.evaluate(yPlane: y, uvPlane: uv, width: 4, height: 4, semantics: .bt601VideoRange)
        let candidate = polyphase.evaluate(yPlane: y, uvPlane: uv, width: 4, height: 4, semantics: .bt601VideoRange)
        XCTAssertEqual(reference.count, candidate.count)
        for (lhs, rhs) in zip(reference, candidate) { XCTAssertEqual(lhs, rhs, accuracy: 1e-9) }
        XCTAssertEqual(polyphase.chromaWeights.count, 1 * 4 * 2)
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
