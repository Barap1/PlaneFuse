import Metal
import XCTest
@testable import PlaneFuseCore

final class MobileNetV2PretrainedParityTests: XCTestCase {
    func testNativeStemMatchesDoubleReferenceForExportedAppleWeights() throws {
        let coefficientURL = URL(fileURLWithPath: "models/derived/MobileNetV2StemCoefficients.json")
        guard FileManager.default.fileExists(atPath: coefficientURL.path) else {
            throw XCTSkip("Run scripts/prepare_mobilenetv2.py to install the local pretrained coefficients.")
        }
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal is unavailable.")
        }

        let coefficients = try MobileNetV2StemCoefficients.load(from: coefficientURL)
        let fixture = MetalBaselineBenchmark.deterministicNV12Fixture(width: 224, height: 224)
        let factory = try MetalRGBBaseline(device: device)
        let input = try factory.makeNV12Textures(
            width: 224, height: 224,
            yPlaneBytes: fixture.yPlaneBytes,
            uvPlaneBytes: fixture.uvPlaneBytes
        )
        let native = try MetalMobileNetV2NativeStem(device: device, coefficients: coefficients)
        let output = try native.makeActivationBuffer()
        try native.execute(input, into: output)
        let actual = try native.readActivation(from: output)

        let referenceStem = coefficients.makeStem()
        let expected = ReferenceConv3x3Stem.evaluate(
            yPlane: fixture.yPlaneBytes,
            uvPlane: fixture.uvPlaneBytes,
            width: 224,
            height: 224,
            semantics: .bt601VideoRange,
            normalization: RGBNormalization(mean: [0.5, 0.5, 0.5], standardDeviation: [0.5, 0.5, 0.5]),
            stem: referenceStem
        ).map(Float.init)
        let maxError = zip(expected, actual).map { abs($0 - $1) }.max() ?? .infinity
        XCTAssertLessThanOrEqual(maxError, 1e-5)
    }
}
