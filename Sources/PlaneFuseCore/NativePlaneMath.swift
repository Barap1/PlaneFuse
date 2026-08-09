import Foundation

/// The deliberately narrow M1 source contract: 8-bit bi-planar NV12 with
/// BT.601 video-range decoding and one sample per output pixel.
public struct NV12Semantics: Equatable, Codable {
    public let name: String
    public let yOffset: Double
    public let yScale: Double
    public let chromaOffset: Double
    public let chromaScale: Double
    /// Rows are R, G, B; columns are decoded Y, Cb, Cr.
    public let rgbFromSource: [[Double]]

    public static let bt601VideoRange = NV12Semantics(
        name: "nv12-bt601-video-range",
        yOffset: 16,
        yScale: 219,
        chromaOffset: 128,
        chromaScale: 224,
        rgbFromSource: [
            [1.0, 0.0, 1.4020000000000000],
            [1.0, -0.3441360000000000, -0.7141360000000000],
            [1.0, 1.7720000000000000, 0.0],
        ]
    )

    public init(
        name: String,
        yOffset: Double,
        yScale: Double,
        chromaOffset: Double,
        chromaScale: Double,
        rgbFromSource: [[Double]]
    ) {
        precondition(rgbFromSource.count == 3 && rgbFromSource.allSatisfy { $0.count == 3 })
        self.name = name
        self.yOffset = yOffset
        self.yScale = yScale
        self.chromaOffset = chromaOffset
        self.chromaScale = chromaScale
        self.rgbFromSource = rgbFromSource
    }

    public func decodeSource(y: UInt8, cb: UInt8, cr: UInt8) -> [Double] {
        [
            (Double(y) - yOffset) / yScale,
            (Double(cb) - chromaOffset) / chromaScale,
            (Double(cr) - chromaOffset) / chromaScale,
        ]
    }

    public func decodeRGB(y: UInt8, cb: UInt8, cr: UInt8) -> [Double] {
        decodeRGB(source: decodeSource(y: y, cb: cb, cr: cr))
    }

    public func decodeRGB(source: [Double]) -> [Double] {
        precondition(source.count == 3)
        return rgbFromSource.map { row in
            zip(row, source).reduce(0) { $0 + ($1.0 * $1.1) }
        }
    }
}

public struct RGBNormalization: Equatable, Codable {
    public let mean: [Double]
    public let standardDeviation: [Double]

    public init(mean: [Double], standardDeviation: [Double]) {
        precondition(mean.count == 3 && standardDeviation.count == 3)
        precondition(standardDeviation.allSatisfy { $0 > 0 })
        self.mean = mean
        self.standardDeviation = standardDeviation
    }

    public func apply(to rgb: [Double]) -> [Double] {
        precondition(rgb.count == 3)
        return zip(zip(rgb, mean), standardDeviation).map { (($0.0 - $0.1) / $1) }
    }
}

public struct OneByOneStem: Equatable, Codable {
    public let outputChannels: Int
    /// Row-major weights with shape [outputChannels, 3].
    public let weights: [Double]
    public let bias: [Double]

    public init(weights: [Double], bias: [Double]) {
        precondition(weights.count == bias.count * 3 && !bias.isEmpty)
        self.outputChannels = bias.count
        self.weights = weights
        self.bias = bias
    }

    public func apply(to normalizedRGB: [Double]) -> [Double] {
        precondition(normalizedRGB.count == 3)
        return (0..<outputChannels).map { output in
            let base = output * 3
            return bias[output] + (0..<3).reduce(0) { partial, channel in
                partial + weights[base + channel] * normalizedRGB[channel]
            }
        }
    }
}

public struct NativePlaneStem: Equatable, Codable {
    public let outputChannels: Int
    /// Row-major coefficients with shape [outputChannels, decoded Y/Cb/Cr].
    public let sourceWeights: [Double]
    public let sourceBias: [Double]

    public init(sourceWeights: [Double], sourceBias: [Double]) {
        precondition(sourceWeights.count == sourceBias.count * 3 && !sourceBias.isEmpty)
        self.outputChannels = sourceBias.count
        self.sourceWeights = sourceWeights
        self.sourceBias = sourceBias
    }

    public func apply(to source: [Double]) -> [Double] {
        precondition(source.count == 3)
        return (0..<outputChannels).map { output in
            let base = output * 3
            return sourceBias[output] + (0..<3).reduce(0) { partial, component in
                partial + sourceWeights[base + component] * source[component]
            }
        }
    }
}

public enum NativePlaneStemCompiler {
    public static func compile(
        semantics: NV12Semantics,
        normalization: RGBNormalization,
        stem: OneByOneStem
    ) -> NativePlaneStem {
        var sourceWeights = Array(repeating: 0.0, count: stem.outputChannels * 3)
        var sourceBias = stem.bias

        for output in 0..<stem.outputChannels {
            let weightBase = output * 3
            for rgbChannel in 0..<3 {
                let normalizedWeight = stem.weights[weightBase + rgbChannel] / normalization.standardDeviation[rgbChannel]
                sourceBias[output] -= normalizedWeight * normalization.mean[rgbChannel]
                for sourceComponent in 0..<3 {
                    sourceWeights[weightBase + sourceComponent] += normalizedWeight * semantics.rgbFromSource[rgbChannel][sourceComponent]
                }
            }
        }

        return NativePlaneStem(sourceWeights: sourceWeights, sourceBias: sourceBias)
    }
}

public enum ReferenceStem {
    public static func evaluate(
        y: UInt8,
        cb: UInt8,
        cr: UInt8,
        semantics: NV12Semantics,
        normalization: RGBNormalization,
        stem: OneByOneStem
    ) -> [Double] {
        let rgb = semantics.decodeRGB(y: y, cb: cb, cr: cr)
        return stem.apply(to: normalization.apply(to: rgb))
    }
}

public enum Parity {
    public static func maxAbsoluteDifference(_ lhs: [Double], _ rhs: [Double]) -> Double {
        precondition(lhs.count == rhs.count)
        return zip(lhs, rhs).map { abs($0 - $1) }.max() ?? 0
    }
}

public struct M1ParityReport: Codable, Equatable {
    public let schemaVersion: Int
    public let semantics: String
    public let sampleCount: Int
    public let maxAbsoluteError: Double
    public let tolerance: Double
    public let pass: Bool

    public init(
        semantics: String,
        sampleCount: Int,
        maxAbsoluteError: Double,
        tolerance: Double
    ) {
        self.schemaVersion = 1
        self.semantics = semantics
        self.sampleCount = sampleCount
        self.maxAbsoluteError = maxAbsoluteError
        self.tolerance = tolerance
        self.pass = maxAbsoluteError <= tolerance
    }
}

public enum NativePlaneProof {
    public static func m1Report(sampleCount: Int = 512, tolerance: Double = 1e-12) -> M1ParityReport {
        let semantics = NV12Semantics.bt601VideoRange
        let normalization = RGBNormalization(
            mean: [0.485, 0.456, 0.406],
            standardDeviation: [0.229, 0.224, 0.225]
        )
        let stem = OneByOneStem(
            weights: [
                0.25, -0.50, 0.75,
                -0.20, 0.40, 0.10,
                0.90, 0.05, -0.30,
                0.12, 0.33, 0.27,
            ],
            bias: [0.10, -0.20, 0.30, 0.05]
        )
        let compiled = NativePlaneStemCompiler.compile(
            semantics: semantics,
            normalization: normalization,
            stem: stem
        )

        var generator = DeterministicByteGenerator(seed: 0x504C414E)
        var maximumError = 0.0
        for _ in 0..<sampleCount {
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

        return M1ParityReport(
            semantics: semantics.name,
            sampleCount: sampleCount,
            maxAbsoluteError: maximumError,
            tolerance: tolerance
        )
    }
}

private struct DeterministicByteGenerator {
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
