import XCTest
@testable import PlaneFuseCore

final class NativePlaneMathTests: XCTestCase {
    private let semantics = NV12Semantics.bt601VideoRange
    private let normalization = RGBNormalization(
        mean: [0.485, 0.456, 0.406],
        standardDeviation: [0.229, 0.224, 0.225]
    )
    private let stem = OneByOneStem(
        weights: [
            0.25, -0.50, 0.75,
            -0.20, 0.40, 0.10,
            0.90, 0.05, -0.30,
            0.12, 0.33, 0.27,
        ],
        bias: [0.10, -0.20, 0.30, 0.05]
    )

    func testBT601VideoRangeFixtureVectors() {
        XCTAssertEqual(semantics.decodeRGB(y: 16, cb: 128, cr: 128), [0.0, 0.0, 0.0])
        XCTAssertEqual(semantics.decodeRGB(y: 235, cb: 128, cr: 128), [1.0, 1.0, 1.0])

        let red = semantics.decodeRGB(y: 81, cb: 90, cr: 240)
        XCTAssertEqual(red[0], 1.0, accuracy: 0.01)
        XCTAssertEqual(red[1], 0.0, accuracy: 0.01)
        XCTAssertEqual(red[2], 0.0, accuracy: 0.01)
    }

    func testCompiledNativeStemMatchesReferenceOnDeterministicCorpus() {
        let compiled = NativePlaneStemCompiler.compile(
            semantics: semantics,
            normalization: normalization,
            stem: stem
        )

        var generator = LCG(seed: 0x504C414E)
        var maximumError = 0.0
        for _ in 0..<512 {
            let y = generator.nextByte(in: 16...235)
            let cb = generator.nextByte(in: 16...240)
            let cr = generator.nextByte(in: 16...240)
            let reference = ReferenceStem.evaluate(
                y: y,
                cb: cb,
                cr: cr,
                semantics: semantics,
                normalization: normalization,
                stem: stem
            )
            let transformed = compiled.apply(to: semantics.decodeSource(y: y, cb: cb, cr: cr))
            maximumError = max(maximumError, Parity.maxAbsoluteDifference(reference, transformed))
        }

        XCTAssertLessThanOrEqual(maximumError, 1e-12)
    }

    func testUnsupportedAssumptionIsVisibleInSemantics() {
        XCTAssertEqual(semantics.name, "nv12-bt601-video-range")
        XCTAssertEqual(semantics.yOffset, 16)
        XCTAssertEqual(semantics.yScale, 219)
        XCTAssertEqual(semantics.chromaScale, 224)
    }
}

private struct LCG {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func nextByte(in range: ClosedRange<UInt8>) -> UInt8 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        let span = UInt64(range.upperBound - range.lowerBound + 1)
        return range.lowerBound + UInt8((state >> 32) % span)
    }
}
