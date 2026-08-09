import Foundation

/// Core ML's `same` convolution placement for the inspected MobileNetV2 stem.
/// For 224 input, 3x3 kernel, and stride 2, total padding is one pixel; it is
/// applied after the final row/column, so the first tap samples `2 * output`.
public enum Conv3x3Stride2PaddingMode: String, Codable, Equatable {
    case sameBottomRight

    public func inputCoordinate(output: Int, kernelTap: Int) -> Int {
        output * 2 + kernelTap
    }
}

/// The first MobileNetV2 learned operation after image preprocessing: a 3x3,
/// stride-2 RGB convolution, followed by channel-wise batch normalization and
/// ReLU6. This type intentionally supports only `same` zero padding; changing
/// padding changes the meaning of the folded source offsets at image edges.
public struct Conv3x3Stride2BatchNormReLU6Stem: Equatable {
    public let outputChannels: Int
    /// OIHW order: [output, input-RGB, y, x].
    public let convolutionWeights: [Double]
    public let convolutionBias: [Double]
    public let batchNormScale: [Double]
    public let batchNormBias: [Double]
    public let batchNormMean: [Double]
    public let batchNormVariance: [Double]
    public let batchNormEpsilon: Double
    public let paddingMode: Conv3x3Stride2PaddingMode

    public init(
        outputChannels: Int,
        convolutionWeights: [Double],
        convolutionBias: [Double],
        batchNormScale: [Double],
        batchNormBias: [Double],
        batchNormMean: [Double],
        batchNormVariance: [Double],
        batchNormEpsilon: Double,
        paddingMode: Conv3x3Stride2PaddingMode = .sameBottomRight
    ) {
        precondition(outputChannels > 0)
        precondition(convolutionWeights.count == outputChannels * 3 * 3 * 3)
        precondition([convolutionBias, batchNormScale, batchNormBias, batchNormMean, batchNormVariance]
            .allSatisfy { $0.count == outputChannels })
        precondition(batchNormVariance.allSatisfy { $0 > 0 })
        // The inspected Apple MobileNetV2 stem stores epsilon as exactly zero.
        precondition(batchNormEpsilon >= 0)
        self.outputChannels = outputChannels
        self.convolutionWeights = convolutionWeights
        self.convolutionBias = convolutionBias
        self.batchNormScale = batchNormScale
        self.batchNormBias = batchNormBias
        self.batchNormMean = batchNormMean
        self.batchNormVariance = batchNormVariance
        self.batchNormEpsilon = batchNormEpsilon
        self.paddingMode = paddingMode
    }

    public func outputSize(inputWidth: Int, inputHeight: Int) -> (width: Int, height: Int) {
        ((inputWidth + 1) / 2, (inputHeight + 1) / 2)
    }
}

/// Native-source coefficients for a `Conv3x3Stride2BatchNormReLU6Stem`.
/// `sourceOffsets` are per output/tap rather than one global bias so that RGB
/// zero padding remains exact: offsets are applied only to in-bounds samples.
public struct NativePlaneConv3x3Stride2Stem: Equatable {
    public let outputChannels: Int
    /// [output, y, x, decoded-Y/Cb/Cr].
    public let sourceWeights: [Double]
    /// [output, y, x], applied only when the corresponding input sample exists.
    public let sourceOffsets: [Double]
    /// BatchNorm-folded convolution bias, applied once per output feature.
    public let bias: [Double]
    public let paddingMode: Conv3x3Stride2PaddingMode

    public var operatorMetadata: NativePlaneOperatorMetadata {
        NativePlaneOperatorMetadata(
            yReadInstructions: 9, uvReadInstructions: 9,
            uniqueChromaCoordinates: 4, weightedMultiplications: 27
        )
    }

    public func evaluate(
        yPlane: [UInt8], uvPlane: [UInt8], width: Int, height: Int,
        semantics: NV12Semantics
    ) -> [Double] {
        precondition(width > 0 && height > 0 && width.isMultiple(of: 2) && height.isMultiple(of: 2))
        precondition(yPlane.count == width * height && uvPlane.count == width * height / 2)
        let output = ((width + 1) / 2, (height + 1) / 2)
        var values = [Double](repeating: 0, count: output.0 * output.1 * outputChannels)
        for oy in 0..<output.1 {
            for ox in 0..<output.0 {
                for channel in 0..<outputChannels {
                    var value = bias[channel]
                    for ky in 0..<3 {
                        for kx in 0..<3 {
                            let inputX = paddingMode.inputCoordinate(output: ox, kernelTap: kx)
                            let inputY = paddingMode.inputCoordinate(output: oy, kernelTap: ky)
                            guard inputX >= 0, inputX < width, inputY >= 0, inputY < height else { continue }
                            let inputIndex = inputY * width + inputX
                            let uvIndex = (inputY / 2) * (width / 2) + (inputX / 2)
                            let source = semantics.decodeSource(
                                y: yPlane[inputIndex], cb: uvPlane[uvIndex * 2], cr: uvPlane[uvIndex * 2 + 1]
                            )
                            let tap = (channel * 9) + ky * 3 + kx
                            value += sourceOffsets[tap]
                            let base = tap * 3
                            value += (0..<3).reduce(0) { $0 + sourceWeights[base + $1] * source[$1] }
                        }
                    }
                    values[(channel * output.1 + oy) * output.0 + ox] = min(6, max(0, value))
                }
            }
        }
        return values
    }
}

public enum NativePlaneConv3x3Compiler {
    public static func compile(
        semantics: NV12Semantics,
        normalization: RGBNormalization,
        stem: Conv3x3Stride2BatchNormReLU6Stem
    ) -> NativePlaneConv3x3Stride2Stem {
        var sourceWeights = [Double](repeating: 0, count: stem.outputChannels * 9 * 3)
        var sourceOffsets = [Double](repeating: 0, count: stem.outputChannels * 9)
        var bias = [Double](repeating: 0, count: stem.outputChannels)
        for output in 0..<stem.outputChannels {
            let scale = stem.batchNormScale[output] / sqrt(stem.batchNormVariance[output] + stem.batchNormEpsilon)
            bias[output] = stem.batchNormBias[output] + scale * (stem.convolutionBias[output] - stem.batchNormMean[output])
            for tap in 0..<9 {
                for rgb in 0..<3 {
                    let foldedWeight = stem.convolutionWeights[(output * 3 + rgb) * 9 + tap] * scale /
                        normalization.standardDeviation[rgb]
                    sourceOffsets[output * 9 + tap] -= foldedWeight * normalization.mean[rgb]
                    for source in 0..<3 {
                        sourceWeights[(output * 9 + tap) * 3 + source] += foldedWeight * semantics.rgbFromSource[rgb][source]
                    }
                }
            }
        }
        return NativePlaneConv3x3Stride2Stem(
            outputChannels: stem.outputChannels, sourceWeights: sourceWeights,
            sourceOffsets: sourceOffsets, bias: bias, paddingMode: stem.paddingMode
        )
    }

    /// Compiles the exact nearest-sited 4:2:0 geometry into nine luma taps and
    /// four aggregated chroma phases. The source offsets remain per tap so
    /// bottom/right padding semantics are not folded across invalid samples.
    public static func compilePolyphase(
        semantics: NV12Semantics,
        normalization: RGBNormalization,
        stem: Conv3x3Stride2BatchNormReLU6Stem
    ) -> NativePlanePolyphaseConv3x3Stride2Stem {
        let base = compile(semantics: semantics, normalization: normalization, stem: stem)
        var luma = [Double](repeating: 0, count: stem.outputChannels * 9)
        var chroma = [Double](repeating: 0, count: stem.outputChannels * 4 * 2)
        for output in 0..<stem.outputChannels {
            for tap in 0..<9 {
                luma[output * 9 + tap] = base.sourceWeights[(output * 9 + tap) * 3]
                let phase = (tap / 3 / 2) * 2 + (tap % 3 / 2)
                chroma[(output * 4 + phase) * 2] += base.sourceWeights[(output * 9 + tap) * 3 + 1]
                chroma[(output * 4 + phase) * 2 + 1] += base.sourceWeights[(output * 9 + tap) * 3 + 2]
            }
        }
        return NativePlanePolyphaseConv3x3Stride2Stem(
            outputChannels: stem.outputChannels,
            lumaWeights: luma,
            chromaWeights: chroma,
            sourceOffsets: base.sourceOffsets,
            bias: base.bias,
            paddingMode: stem.paddingMode
        )
    }
}

public struct NativePlanePolyphaseConv3x3Stride2Stem: Equatable {
    public let outputChannels: Int
    public let lumaWeights: [Double]
    /// [output, chroma phase (y,x), Cb/Cr].
    public let chromaWeights: [Double]
    /// [output, y, x], retained per tap for exact padding behavior.
    public let sourceOffsets: [Double]
    public let bias: [Double]
    public let paddingMode: Conv3x3Stride2PaddingMode

    public var operatorMetadata: NativePlaneOperatorMetadata {
        NativePlaneOperatorMetadata(
            yReadInstructions: lumaWeights.count / outputChannels,
            uvReadInstructions: chromaWeights.count / (outputChannels * 2),
            uniqueChromaCoordinates: chromaWeights.count / (outputChannels * 2),
            weightedMultiplications: lumaWeights.count / outputChannels + chromaWeights.count / outputChannels
        )
    }

    public func evaluate(
        yPlane: [UInt8], uvPlane: [UInt8], width: Int, height: Int,
        semantics: NV12Semantics
    ) -> [Double] {
        precondition(width > 0 && height > 0 && width.isMultiple(of: 2) && height.isMultiple(of: 2))
        let outputWidth = (width + 1) / 2
        let outputHeight = (height + 1) / 2
        var values = [Double](repeating: 0, count: outputWidth * outputHeight * outputChannels)
        for oy in 0..<outputHeight {
            for ox in 0..<outputWidth {
                for channel in 0..<outputChannels {
                    var value = bias[channel]
                    for ky in 0..<3 {
                        for kx in 0..<3 {
                            let x = paddingMode.inputCoordinate(output: ox, kernelTap: kx)
                            let y = paddingMode.inputCoordinate(output: oy, kernelTap: ky)
                            guard x >= 0, x < width, y >= 0, y < height else { continue }
                            let tap = channel * 9 + ky * 3 + kx
                            let pixel = y * width + x
                            let source = semantics.decodeSource(y: yPlane[pixel], cb: uvPlane[((y / 2) * (width / 2) + x / 2) * 2], cr: uvPlane[((y / 2) * (width / 2) + x / 2) * 2 + 1])
                            value += sourceOffsets[tap] + lumaWeights[channel * 9 + ky * 3 + kx] * source[0]
                        }
                    }
                    for chromaY in 0..<2 {
                        for chromaX in 0..<2 {
                            let x = ox * 2 + chromaX * 2
                            let y = oy * 2 + chromaY * 2
                            guard x < width, y < height else { continue }
                            let uv = (y / 2) * (width / 2) + x / 2
                            let phase = chromaY * 2 + chromaX
                            let base = (channel * 4 + phase) * 2
                            let source = semantics.decodeSource(y: 128, cb: uvPlane[uv * 2], cr: uvPlane[uv * 2 + 1])
                            value += chromaWeights[base] * source[1] + chromaWeights[base + 1] * source[2]
                        }
                    }
                    values[(channel * outputHeight + oy) * outputWidth + ox] = min(6, max(0, value))
                }
            }
        }
        return values
    }
}

/// Operator counts generated from the source-domain coefficient representation.
/// These are static instruction counts per output feature, not measured timing.
public struct NativePlaneOperatorMetadata: Equatable {
    public let yReadInstructions: Int
    public let uvReadInstructions: Int
    public let uniqueChromaCoordinates: Int
    public let weightedMultiplications: Int
}

public enum ReferenceConv3x3Stem {
    public static func evaluate(
        yPlane: [UInt8], uvPlane: [UInt8], width: Int, height: Int,
        semantics: NV12Semantics, normalization: RGBNormalization,
        stem: Conv3x3Stride2BatchNormReLU6Stem
    ) -> [Double] {
        let output = stem.outputSize(inputWidth: width, inputHeight: height)
        var values = [Double](repeating: 0, count: output.width * output.height * stem.outputChannels)
        for channel in 0..<stem.outputChannels {
            let scale = stem.batchNormScale[channel] / sqrt(stem.batchNormVariance[channel] + stem.batchNormEpsilon)
            for oy in 0..<output.height {
                for ox in 0..<output.width {
                    var value = stem.convolutionBias[channel]
                    for ky in 0..<3 { for kx in 0..<3 {
                        let x = stem.paddingMode.inputCoordinate(output: ox, kernelTap: kx)
                        let y = stem.paddingMode.inputCoordinate(output: oy, kernelTap: ky)
                        guard x >= 0, x < width, y >= 0, y < height else { continue }
                        let pixel = y * width + x; let uv = (y / 2) * (width / 2) + (x / 2)
                        let normalized = normalization.apply(to: semantics.decodeRGB(y: yPlane[pixel], cb: uvPlane[uv * 2], cr: uvPlane[uv * 2 + 1]))
                        for rgb in 0..<3 { value += stem.convolutionWeights[(channel * 3 + rgb) * 9 + ky * 3 + kx] * normalized[rgb] }
                    }}
                    value = stem.batchNormBias[channel] + scale * (value - stem.batchNormMean[channel])
                    values[(channel * output.height + oy) * output.width + ox] = min(6, max(0, value))
                }
            }
        }
        return values
    }
}
