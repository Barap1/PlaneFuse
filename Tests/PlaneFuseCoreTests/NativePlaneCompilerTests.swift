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
