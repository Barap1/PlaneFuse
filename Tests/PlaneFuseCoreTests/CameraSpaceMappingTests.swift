import XCTest
@testable import PlaneFuseCore

final class CameraSpaceMappingTests: XCTestCase {
    func testGeometryMatchesAccepted1920x1080CameraCrop() throws {
        let mapping = try CameraSpaceMapping(sourceWidth: 1_920, sourceHeight: 1_080)

        XCTAssertEqual(mapping.sourceWidth, 1_920)
        XCTAssertEqual(mapping.sourceHeight, 1_080)
        XCTAssertEqual(mapping.cropOriginX, 420)
        XCTAssertEqual(mapping.cropOriginY, 0)
        XCTAssertEqual(mapping.cropSide, 1_080)
        XCTAssertEqual(CameraSpaceMapping.resizedLumaWidth, 224)
        XCTAssertEqual(CameraSpaceMapping.resizedUVWidth, 112)
    }

    func testLumaAndUVResizeBoundariesUseExactIntegerFormula() throws {
        let mapping = try CameraSpaceMapping(sourceWidth: 1_920, sourceHeight: 1_080)

        XCTAssertEqual(try mapping.lumaSourceCoordinate(resized: .init(x: 0, y: 0)), .init(x: 420, y: 0))
        XCTAssertEqual(try mapping.lumaSourceCoordinate(resized: .init(x: 223, y: 223)), .init(x: 1_495, y: 1_075))
        XCTAssertEqual(try mapping.uvSourceCoordinate(resized: .init(x: 0, y: 0)), .init(x: 210, y: 0))
        XCTAssertEqual(try mapping.uvSourceCoordinate(resized: .init(x: 111, y: 111)), .init(x: 745, y: 535))
    }

    func testDirectCameraMappingEqualsTwoStageReferenceAcrossAllC1Coordinates() throws {
        for dimensions in [(width: 1_920, height: 1_080), (width: 4, height: 2), (width: 2, height: 4), (width: 224, height: 224)] {
            let mapping = try CameraSpaceMapping(sourceWidth: dimensions.width, sourceHeight: dimensions.height)
            for outputY in 0..<CameraSpaceMapping.c1OutputHeight {
                for outputX in 0..<CameraSpaceMapping.c1OutputWidth {
                    for tapY in 0..<CameraSpaceMapping.c1KernelHeight {
                        for tapX in 0..<CameraSpaceMapping.c1KernelWidth {
                            let output = CameraSpaceCoordinate(x: outputX, y: outputY)
                            let tap = CameraSpaceCoordinate(x: tapX, y: tapY)
                            XCTAssertEqual(
                                try mapping.directCameraC1TapMapping(output: output, tap: tap),
                                try mapping.twoStageC1TapMapping(output: output, tap: tap),
                                "source=\(dimensions.width)x\(dimensions.height), output=\(output), tap=\(tap)"
                            )
                        }
                    }
                }
            }
        }
    }

    func testBottomRightSameSkipsOnlyOutOfBoundsTaps() throws {
        let mapping = try CameraSpaceMapping(sourceWidth: 1_920, sourceHeight: 1_080)

        let valid = try mapping.directCameraC1TapMapping(
            output: .init(x: 111, y: 111), tap: .init(x: 1, y: 1)
        )
        XCTAssertTrue(valid.isValid)
        XCTAssertEqual(valid.resizedLumaCoordinate, .init(x: 223, y: 223))
        XCTAssertEqual(valid.resizedUVCoordinate, .init(x: 111, y: 111))
        XCTAssertEqual(valid.lumaSourceCoordinate, .init(x: 1_495, y: 1_075))
        XCTAssertEqual(valid.uvSourceCoordinate, .init(x: 745, y: 535))

        for tap in [CameraSpaceCoordinate(x: 2, y: 1), CameraSpaceCoordinate(x: 1, y: 2), CameraSpaceCoordinate(x: 2, y: 2)] {
            let mapping = try mapping.directCameraC1TapMapping(output: .init(x: 111, y: 111), tap: tap)
            XCTAssertFalse(mapping.isValid)
            XCTAssertNil(mapping.resizedLumaCoordinate)
            XCTAssertNil(mapping.resizedUVCoordinate)
            XCTAssertNil(mapping.lumaSourceCoordinate)
            XCTAssertNil(mapping.uvSourceCoordinate)
        }
    }

    func testRejectedAndOutOfBoundsInputsAreExplicit() throws {
        XCTAssertThrowsError(try CameraSpaceMapping(sourceWidth: 0, sourceHeight: 1080)) {
            XCTAssertEqual($0 as? CameraSpaceMappingError, .nonPositiveSourceDimensions)
        }
        XCTAssertThrowsError(try CameraSpaceMapping(sourceWidth: 1_919, sourceHeight: 1_080)) {
            XCTAssertEqual($0 as? CameraSpaceMappingError, .oddSourceDimensions)
        }
        XCTAssertThrowsError(try CameraSpaceMapping(sourceWidth: 1, sourceHeight: 1)) {
            XCTAssertEqual($0 as? CameraSpaceMappingError, .oddSourceDimensions)
        }

        let mapping = try CameraSpaceMapping(sourceWidth: 4, sourceHeight: 2)
        XCTAssertThrowsError(try mapping.lumaSourceCoordinate(resized: .init(x: 224, y: 0))) {
            XCTAssertEqual($0 as? CameraSpaceMappingError, .resizedLumaCoordinateOutOfBounds)
        }
        XCTAssertThrowsError(try mapping.uvSourceCoordinate(resized: .init(x: 0, y: 112))) {
            XCTAssertEqual($0 as? CameraSpaceMappingError, .resizedUVCoordinateOutOfBounds)
        }
        XCTAssertThrowsError(try mapping.directCameraC1TapMapping(output: .init(x: 112, y: 0), tap: .init(x: 0, y: 0))) {
            XCTAssertEqual($0 as? CameraSpaceMappingError, .stemOutputCoordinateOutOfBounds)
        }
        XCTAssertThrowsError(try mapping.directCameraC1TapMapping(output: .init(x: 0, y: 0), tap: .init(x: 3, y: 0))) {
            XCTAssertEqual($0 as? CameraSpaceMappingError, .stemTapCoordinateOutOfBounds)
        }
    }
}
