import CoreGraphics
import CryptoKit
import Foundation
import ImageIO

/// A fixed, local corpus for M5 equivalence and timing. The source image is decoded
/// with ImageIO, then deterministically converted to the supported NV12 contract.
/// The benchmark intentionally consumes these frames instead of synthetic byte
/// perturbations, so an absent or modified corpus is a hard failure.
public struct MobileNetV2CorpusManifest: Codable, Equatable {
    public struct Input: Codable, Equatable {
        public let width: Int
        public let height: Int
        public let rgbDecode: String
        public let nv12Conversion: String
    }

    public struct Sample: Codable, Equatable {
        public let id: String
        /// R7 manifests classify samples before inference. Legacy procedural
        /// entries predate these fields and are identified by their fixed ID
        /// namespace by the quality-evidence runner.
        public let kind: String?
        public let bucket: String?
        public let relativePath: String
        public let sha256: String
        public let sourceUrl: URL
        public let license: String
        public let attribution: String
    }

    public let schemaVersion: Int
    public let input: Input
    public let samples: [Sample]
}

public struct MobileNetV2CorpusFrame: Equatable {
    public let id: String
    public let yPlaneBytes: [UInt8]
    public let uvPlaneBytes: [UInt8]

    /// Produces the exact RGB values that B and C reconstruct from this frame for
    /// the independent original-derived Core ML stem. Values are CHW Float32 and
    /// use the MobileNetV2 [-1, 1] normalization.
    public func normalizedRGB() -> [Float] {
        let pixels = yPlaneBytes.count
        var result = [Float](repeating: 0, count: pixels * 3)
        for index in 0..<pixels {
            let x = index % MobileNetV2Corpus.inputWidth
            let y = index / MobileNetV2Corpus.inputWidth
            let uv = (y / 2) * (MobileNetV2Corpus.inputWidth / 2) + x / 2
            let rgb = NV12Semantics.bt601VideoRange.decodeRGB(
                y: yPlaneBytes[index], cb: uvPlaneBytes[uv * 2], cr: uvPlaneBytes[uv * 2 + 1]
            )
            result[index] = Float((rgb[0] - 0.5) / 0.5)
            result[pixels + index] = Float((rgb[1] - 0.5) / 0.5)
            result[pixels * 2 + index] = Float((rgb[2] - 0.5) / 0.5)
        }
        return result
    }
}

public struct MobileNetV2CorpusSourceImage {
    public let id: String
    public let image: CGImage

    public init(id: String, image: CGImage) {
        self.id = id
        self.image = image
    }
}

public final class MobileNetV2Corpus {
    public static let inputWidth = 224
    public static let inputHeight = 224
    public static let expectedRGBDecode = "ImageIO decode into sRGB RGBA8; CGContext high-quality deterministic stretch to 224x224"
    public static let expectedNV12Conversion = "BT.601 video-range, 8-bit, 2x2 chroma from arithmetic mean of source RGB samples, round-to-nearest-away-from-zero"

    public enum Error: Swift.Error, LocalizedError, Equatable {
        case invalidManifest
        case imageMissing(URL)
        case imageHashMismatch(URL)
        case imageDecodeFailed(URL)

        public var errorDescription: String? {
            switch self {
            case .invalidManifest: return "The MobileNetV2 corpus manifest must contain non-empty, provenance-bearing 224x224 RGB-to-NV12 samples."
            case let .imageMissing(url): return "MobileNetV2 corpus image is missing: \(url.path)"
            case let .imageHashMismatch(url): return "MobileNetV2 corpus image SHA-256 does not match the manifest: \(url.path)"
            case let .imageDecodeFailed(url): return "ImageIO could not decode MobileNetV2 corpus image: \(url.path)"
            }
        }
    }

    public let manifest: MobileNetV2CorpusManifest
    private let root: URL

    public init(manifestURL: URL, root: URL) throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.manifest = try decoder.decode(MobileNetV2CorpusManifest.self, from: Data(contentsOf: manifestURL))
        self.root = root
        guard manifest.schemaVersion >= 1 && manifest.schemaVersion <= 2,
              manifest.input.width == Self.inputWidth,
              manifest.input.height == Self.inputHeight,
              manifest.input.rgbDecode == Self.expectedRGBDecode,
              manifest.input.nv12Conversion == Self.expectedNV12Conversion,
              !manifest.samples.isEmpty,
              manifest.samples.allSatisfy({ !$0.id.isEmpty && !$0.relativePath.isEmpty && Self.isSHA256($0.sha256) && !$0.license.isEmpty && !$0.sourceUrl.absoluteString.isEmpty }) else {
            throw Error.invalidManifest
        }
    }

    public func loadFrames() throws -> [MobileNetV2CorpusFrame] {
        try manifest.samples.map(loadFrame)
    }

    /// Loads the same deterministic 224x224 sRGB image that feeds the corpus
    /// conversion, for direct original image-input model lineage checks.
    public func loadSourceImages() throws -> [MobileNetV2CorpusSourceImage] {
        try manifest.samples.map { sample in
            MobileNetV2CorpusSourceImage(id: sample.id, image: try loadRenderedImage(sample))
        }
    }

    public func normalizedRGB(for sourceImage: MobileNetV2CorpusSourceImage) throws -> [Float] {
        let rgba = try Self.renderSRGB(image: sourceImage.image, sourceURL: URL(fileURLWithPath: sourceImage.id))
        let pixelCount = Self.inputWidth * Self.inputHeight
        var result = [Float](repeating: 0, count: pixelCount * 3)
        for index in 0..<pixelCount {
            let offset = index * 4
            result[index] = (Float(rgba[offset]) / 255 - 0.5) / 0.5
            result[pixelCount + index] = (Float(rgba[offset + 1]) / 255 - 0.5) / 0.5
            result[pixelCount * 2 + index] = (Float(rgba[offset + 2]) / 255 - 0.5) / 0.5
        }
        return result
    }

    private func loadFrame(_ sample: MobileNetV2CorpusManifest.Sample) throws -> MobileNetV2CorpusFrame {
        let url = root.appendingPathComponent(sample.relativePath)
        let rgb = try Self.renderSRGB(image: loadRenderedImage(sample), sourceURL: url)
        let nv12 = Self.convertRGBToNV12(rgb)
        return MobileNetV2CorpusFrame(id: sample.id, yPlaneBytes: nv12.y, uvPlaneBytes: nv12.uv)
    }

    private func loadRenderedImage(_ sample: MobileNetV2CorpusManifest.Sample) throws -> CGImage {
        let url = root.appendingPathComponent(sample.relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else { throw Error.imageMissing(url) }
        let data = try Data(contentsOf: url)
        guard Self.sha256(data) == sample.sha256.lowercased() else { throw Error.imageHashMismatch(url) }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw Error.imageDecodeFailed(url) }
        var renderedBytes = [UInt8](repeating: 0, count: Self.inputWidth * Self.inputHeight * 4)
        guard let context = CGContext(
            data: &renderedBytes, width: Self.inputWidth, height: Self.inputHeight,
            bitsPerComponent: 8, bytesPerRow: Self.inputWidth * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else { throw Error.imageDecodeFailed(url) }
        context.interpolationQuality = .high
        context.setBlendMode(.copy)
        context.draw(image, in: CGRect(x: 0, y: 0, width: Self.inputWidth, height: Self.inputHeight))
        guard let rendered = context.makeImage() else { throw Error.imageDecodeFailed(url) }
        return rendered
    }

    private static func renderSRGB(image: CGImage, sourceURL: URL) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: inputWidth * inputHeight * 4)
        guard let context = CGContext(
            data: &bytes,
            width: inputWidth,
            height: inputHeight,
            bitsPerComponent: 8,
            bytesPerRow: inputWidth * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else { throw Error.imageDecodeFailed(sourceURL) }
        context.interpolationQuality = .high
        context.setBlendMode(.copy)
        context.draw(image, in: CGRect(x: 0, y: 0, width: inputWidth, height: inputHeight))
        return bytes
    }

    private static func convertRGBToNV12(_ rgba: [UInt8]) -> (y: [UInt8], uv: [UInt8]) {
        var yPlane = [UInt8](repeating: 0, count: inputWidth * inputHeight)
        var uvPlane = [UInt8](repeating: 0, count: inputWidth * inputHeight / 2)
        for y in 0..<inputHeight { for x in 0..<inputWidth {
            let rgb = rgb(rgba, x: x, y: y)
            yPlane[y * inputWidth + x] = videoRangeY(rgb)
        }}
        for y in stride(from: 0, to: inputHeight, by: 2) { for x in stride(from: 0, to: inputWidth, by: 2) {
            var average = (r: 0.0, g: 0.0, b: 0.0)
            for dy in 0..<2 { for dx in 0..<2 {
                let pixel = rgb(rgba, x: x + dx, y: y + dy)
                average.r += pixel.r / 4; average.g += pixel.g / 4; average.b += pixel.b / 4
            }}
            let index = (y / 2) * inputWidth + x
            uvPlane[index] = videoRangeCb(average)
            uvPlane[index + 1] = videoRangeCr(average)
        }}
        return (yPlane, uvPlane)
    }

    private static func rgb(_ rgba: [UInt8], x: Int, y: Int) -> (r: Double, g: Double, b: Double) {
        let offset = (y * inputWidth + x) * 4
        return (Double(rgba[offset]) / 255, Double(rgba[offset + 1]) / 255, Double(rgba[offset + 2]) / 255)
    }

    private static func videoRangeY(_ rgb: (r: Double, g: Double, b: Double)) -> UInt8 {
        byte(16 + 219 * (0.299 * rgb.r + 0.587 * rgb.g + 0.114 * rgb.b))
    }

    private static func videoRangeCb(_ rgb: (r: Double, g: Double, b: Double)) -> UInt8 {
        byte(128 + 224 * (-0.168736 * rgb.r - 0.331264 * rgb.g + 0.5 * rgb.b))
    }

    private static func videoRangeCr(_ rgb: (r: Double, g: Double, b: Double)) -> UInt8 {
        byte(128 + 224 * (0.5 * rgb.r - 0.418688 * rgb.g - 0.081312 * rgb.b))
    }

    private static func byte(_ value: Double) -> UInt8 {
        UInt8(max(0, min(255, value.rounded(.toNearestOrAwayFromZero))))
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func isSHA256(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy { $0.isHexDigit }
    }
}
