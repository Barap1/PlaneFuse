import Foundation

/// Errors produced while constructing or querying the fixed Camera -> NV12 -> C1 mapping.
public enum CameraSpaceMappingError: Error, Equatable, Sendable {
    /// NV12 camera planes require positive luma dimensions.
    case nonPositiveSourceDimensions
    /// The live camera path accepts only even NV12 luma dimensions.
    case oddSourceDimensions
    /// An NV12 crop must contain at least one luma and one chroma sample.
    case cropTooSmall
    case resizedLumaCoordinateOutOfBounds
    case resizedUVCoordinateOutOfBounds
    case stemOutputCoordinateOutOfBounds
    case stemTapCoordinateOutOfBounds
}

/// An integer coordinate whose `x` component addresses a column and `y` a row.
public struct CameraSpaceCoordinate: Equatable, Sendable {
    public let x: Int
    public let y: Int

    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }
}

/// The exact mapping of one valid C1 tap into resized and original NV12 coordinates.
///
/// `resizedUVCoordinate` uses the native stem's integer `rx / 2`, `ry / 2`
/// operation before the UV resize formula. Invalid bottom/right SAME taps have
/// no resized or source coordinates.
public struct CameraSpaceC1TapMapping: Equatable, Sendable {
    public let outputCoordinate: CameraSpaceCoordinate
    public let tapCoordinate: CameraSpaceCoordinate
    public let resizedLumaCoordinate: CameraSpaceCoordinate?
    public let resizedUVCoordinate: CameraSpaceCoordinate?
    public let lumaSourceCoordinate: CameraSpaceCoordinate?
    public let uvSourceCoordinate: CameraSpaceCoordinate?

    public var isValid: Bool {
        resizedLumaCoordinate != nil
    }

    init(
        outputCoordinate: CameraSpaceCoordinate,
        tapCoordinate: CameraSpaceCoordinate,
        resizedLumaCoordinate: CameraSpaceCoordinate?,
        resizedUVCoordinate: CameraSpaceCoordinate?,
        lumaSourceCoordinate: CameraSpaceCoordinate?,
        uvSourceCoordinate: CameraSpaceCoordinate?
    ) {
        self.outputCoordinate = outputCoordinate
        self.tapCoordinate = tapCoordinate
        self.resizedLumaCoordinate = resizedLumaCoordinate
        self.resizedUVCoordinate = resizedUVCoordinate
        self.lumaSourceCoordinate = lumaSourceCoordinate
        self.uvSourceCoordinate = uvSourceCoordinate
    }
}

/// Integer-only reference geometry for the accepted camera preprocessing contract.
///
/// This type models the existing separate nearest-resize and native C1 stem
/// operations. It deliberately rejects odd dimensions, matching
/// `CameraResizeGeometry`; masking an odd frame would invent a camera contract
/// that the live path does not support.
public struct CameraSpaceMapping: Equatable, Sendable {
    public static let resizedLumaWidth = 224
    public static let resizedLumaHeight = 224
    public static let resizedUVWidth = 112
    public static let resizedUVHeight = 112
    public static let c1OutputWidth = 112
    public static let c1OutputHeight = 112
    public static let c1KernelWidth = 3
    public static let c1KernelHeight = 3
    public static let c1Stride = 2

    public let sourceWidth: Int
    public let sourceHeight: Int
    public let cropOriginX: Int
    public let cropOriginY: Int
    public let cropSide: Int

    /// Creates the even-aligned square center crop used by the live NV12 bridge.
    public init(sourceWidth: Int, sourceHeight: Int) throws {
        guard sourceWidth > 0, sourceHeight > 0 else {
            throw CameraSpaceMappingError.nonPositiveSourceDimensions
        }
        guard sourceWidth.isMultiple(of: 2), sourceHeight.isMultiple(of: 2) else {
            throw CameraSpaceMappingError.oddSourceDimensions
        }

        let cropSide = min(sourceWidth, sourceHeight) & ~1
        guard cropSide >= 2 else {
            throw CameraSpaceMappingError.cropTooSmall
        }

        self.sourceWidth = sourceWidth
        self.sourceHeight = sourceHeight
        self.cropOriginX = ((sourceWidth - cropSide) / 2) & ~1
        self.cropOriginY = ((sourceHeight - cropSide) / 2) & ~1
        self.cropSide = cropSide
    }

    /// Maps a 224x224 resized luma coordinate to the original camera luma plane.
    public func lumaSourceCoordinate(
        resized coordinate: CameraSpaceCoordinate
    ) throws -> CameraSpaceCoordinate {
        guard isInBounds(coordinate, width: Self.resizedLumaWidth, height: Self.resizedLumaHeight) else {
            throw CameraSpaceMappingError.resizedLumaCoordinateOutOfBounds
        }
        return CameraSpaceCoordinate(
            x: cropOriginX + nearestSourceIndex(coordinate.x, sourceLength: cropSide, destinationLength: Self.resizedLumaWidth),
            y: cropOriginY + nearestSourceIndex(coordinate.y, sourceLength: cropSide, destinationLength: Self.resizedLumaHeight)
        )
    }

    /// Maps a 112x112 resized interleaved-UV coordinate to the original UV plane.
    public func uvSourceCoordinate(
        resized coordinate: CameraSpaceCoordinate
    ) throws -> CameraSpaceCoordinate {
        guard isInBounds(coordinate, width: Self.resizedUVWidth, height: Self.resizedUVHeight) else {
            throw CameraSpaceMappingError.resizedUVCoordinateOutOfBounds
        }
        let cropUVSide = cropSide / 2
        return CameraSpaceCoordinate(
            x: cropOriginX / 2 + nearestSourceIndex(coordinate.x, sourceLength: cropUVSide, destinationLength: Self.resizedUVWidth),
            y: cropOriginY / 2 + nearestSourceIndex(coordinate.y, sourceLength: cropUVSide, destinationLength: Self.resizedUVHeight)
        )
    }

    /// Scalar oracle for the existing two-stage path: C1 tap -> resized sample -> camera sample.
    public func twoStageC1TapMapping(
        output: CameraSpaceCoordinate,
        tap: CameraSpaceCoordinate
    ) throws -> CameraSpaceC1TapMapping {
        try validateStemCoordinates(output: output, tap: tap)
        let resizedLuma = c1ResizedLumaCoordinate(output: output, tap: tap)
        guard let resizedLuma else {
            return invalidTapMapping(output: output, tap: tap)
        }
        let resizedUV = CameraSpaceCoordinate(x: resizedLuma.x / 2, y: resizedLuma.y / 2)
        return CameraSpaceC1TapMapping(
            outputCoordinate: output,
            tapCoordinate: tap,
            resizedLumaCoordinate: resizedLuma,
            resizedUVCoordinate: resizedUV,
            lumaSourceCoordinate: try lumaSourceCoordinate(resized: resizedLuma),
            uvSourceCoordinate: try uvSourceCoordinate(resized: resizedUV)
        )
    }

    /// Direct camera-space oracle for one C1 tap, derived by composing resize and C1 indices.
    public func directCameraC1TapMapping(
        output: CameraSpaceCoordinate,
        tap: CameraSpaceCoordinate
    ) throws -> CameraSpaceC1TapMapping {
        try validateStemCoordinates(output: output, tap: tap)
        let rx = Self.c1Stride * output.x + tap.x
        let ry = Self.c1Stride * output.y + tap.y
        guard rx < Self.resizedLumaWidth, ry < Self.resizedLumaHeight else {
            return invalidTapMapping(output: output, tap: tap)
        }

        let resizedLuma = CameraSpaceCoordinate(x: rx, y: ry)
        let resizedUV = CameraSpaceCoordinate(x: rx / 2, y: ry / 2)
        let cropUVSide = cropSide / 2
        return CameraSpaceC1TapMapping(
            outputCoordinate: output,
            tapCoordinate: tap,
            resizedLumaCoordinate: resizedLuma,
            resizedUVCoordinate: resizedUV,
            lumaSourceCoordinate: CameraSpaceCoordinate(
                x: cropOriginX + nearestSourceIndex(rx, sourceLength: cropSide, destinationLength: Self.resizedLumaWidth),
                y: cropOriginY + nearestSourceIndex(ry, sourceLength: cropSide, destinationLength: Self.resizedLumaHeight)
            ),
            uvSourceCoordinate: CameraSpaceCoordinate(
                x: cropOriginX / 2 + nearestSourceIndex(resizedUV.x, sourceLength: cropUVSide, destinationLength: Self.resizedUVWidth),
                y: cropOriginY / 2 + nearestSourceIndex(resizedUV.y, sourceLength: cropUVSide, destinationLength: Self.resizedUVHeight)
            )
        )
    }

    private func validateStemCoordinates(
        output: CameraSpaceCoordinate,
        tap: CameraSpaceCoordinate
    ) throws {
        guard isInBounds(output, width: Self.c1OutputWidth, height: Self.c1OutputHeight) else {
            throw CameraSpaceMappingError.stemOutputCoordinateOutOfBounds
        }
        guard isInBounds(tap, width: Self.c1KernelWidth, height: Self.c1KernelHeight) else {
            throw CameraSpaceMappingError.stemTapCoordinateOutOfBounds
        }
    }

    private func c1ResizedLumaCoordinate(
        output: CameraSpaceCoordinate,
        tap: CameraSpaceCoordinate
    ) -> CameraSpaceCoordinate? {
        let x = Self.c1Stride * output.x + tap.x
        let y = Self.c1Stride * output.y + tap.y
        guard x < Self.resizedLumaWidth, y < Self.resizedLumaHeight else {
            return nil
        }
        return CameraSpaceCoordinate(x: x, y: y)
    }

    private func invalidTapMapping(
        output: CameraSpaceCoordinate,
        tap: CameraSpaceCoordinate
    ) -> CameraSpaceC1TapMapping {
        CameraSpaceC1TapMapping(
            outputCoordinate: output,
            tapCoordinate: tap,
            resizedLumaCoordinate: nil,
            resizedUVCoordinate: nil,
            lumaSourceCoordinate: nil,
            uvSourceCoordinate: nil
        )
    }

    private func isInBounds(_ coordinate: CameraSpaceCoordinate, width: Int, height: Int) -> Bool {
        coordinate.x >= 0 && coordinate.x < width && coordinate.y >= 0 && coordinate.y < height
    }

    /// Computes `(destinationIndex * sourceLength) / destinationLength` without
    /// overflowing when `sourceLength` is a valid `Int` camera dimension.
    private func nearestSourceIndex(
        _ destinationIndex: Int,
        sourceLength: Int,
        destinationLength: Int
    ) -> Int {
        let quotient = sourceLength / destinationLength
        let remainder = sourceLength % destinationLength
        return destinationIndex * quotient + (destinationIndex * remainder) / destinationLength
    }
}
