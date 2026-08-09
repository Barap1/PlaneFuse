import XCTest
import Metal
@testable import PlaneFuseCore

final class MobileNetV2IntegrationTests: XCTestCase {
    func testOutputAgreementRequiresExistingStemThresholdAnd995PercentTaskAgreement() throws {
        let passing = try MobileNetV2OutputAgreement(
            baselineLogits: [[0, 3], [4, 1], [1, 5], [8, 2]], candidateLogits: [[0, 2], [3, 1], [1, 4], [7, 2]],
            maxStemAbsoluteError: 0.000009
        )
        XCTAssertEqual(passing.top1Agreement, 1)
        XCTAssertTrue(passing.passes)
        let failing = try MobileNetV2OutputAgreement(
            baselineLogits: [[0, 3], [4, 1]], candidateLogits: [[4, 0], [3, 1]], maxStemAbsoluteError: 0.000009
        )
        XCTAssertFalse(failing.passes)
    }

    func testManifestRejectsWrongStemShape() throws {
        let manifest = MobileNetV2AssetManifest(modelIdentifier: "Apple MobileNetV2 ImageNet", sourceURL: URL(string: "https://example.invalid")!, sourceModelFile: "x", sourceSHA256: nil, tailModelDirectory: "x", tailInputName: "x", tailOutputName: "x", activationShape: [3, 224, 224], paddingMode: .sameBottomRight, validationCorpusManifest: "x", derivedManifest: "x")
        XCTAssertThrowsError(try manifest.validate(at: URL(fileURLWithPath: "/tmp")))
    }

    func testCompiledTailAcceptsTheInspectedThreeDimensionalStemBoundary() throws {
        let url = URL(fileURLWithPath: "models/derived/tail-compiled/MobileNetV2Tail.mlmodelc")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Local MobileNetV2 tail artifact is not installed.")
        }
        let tail = try CoreMLMobileNetV2TailAdapter(modelURL: url, manifest: .inspected)
        let probabilities = try tail.predict(stemActivation: [Float](repeating: 0, count: 48 * 112 * 112))
        // The checked compiled artifact exposes 1,000 ImageNet label entries;
        // its source-side classifier metadata includes the additional background
        // index, which is not emitted in this probability dictionary.
        XCTAssertEqual(probabilities.count, 1000)
        XCTAssertNotNil(probabilities.values.max())
    }

    func testBufferBackedMultiArrayRetainsCanonicalShapeAndStorage() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let buffer = device.makeBuffer(length: 48 * 112 * 112 * MemoryLayout<Float>.stride, options: .storageModeShared) else {
            throw XCTSkip("Metal device or shared buffer unavailable.")
        }
        let view = try BufferBackedMultiArray(buffer: buffer, shape: [48, 112, 112])
        XCTAssertEqual(view.multiArray.shape.map(\.intValue), [48, 112, 112])
        XCTAssertEqual(view.multiArray.strides.map(\.intValue), [112 * 112, 112, 1])
        XCTAssertEqual(view.storageLength, buffer.length)
    }

    func testBufferBackedMultiArrayRejectsWrongStrides() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let buffer = device.makeBuffer(length: 48 * 112 * 112 * MemoryLayout<Float>.stride, options: .storageModeShared) else {
            throw XCTSkip("Metal device or shared buffer unavailable.")
        }
        XCTAssertThrowsError(try BufferBackedMultiArray(buffer: buffer, shape: [48, 112, 112], strides: [1, 112, 112 * 112]))
    }
}
