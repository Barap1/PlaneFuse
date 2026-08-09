import Foundation
import Metal

/// Pipeline B's learned 1x1 RGB stem. It consumes the full normalized RGBA32Float
/// intermediate materialized by ``MetalRGBBaseline`` and writes four feature values
/// per pixel without performing another color conversion or normalization.
public final class MetalRGBNormalStem {
    public struct Execution {
        /// GPU time for the command buffer containing only this reusable RGB-stem
        /// dispatch, when the driver provides GPU timestamps.
        public let gpuDuration: TimeInterval?
    }

    public enum Error: Swift.Error, LocalizedError, Equatable {
        case noDevice
        case commandQueueUnavailable
        case shaderResourceMissing
        case shaderSourceUnreadable
        case functionMissing
        case unsupportedOutputChannelCount(Int)
        case coefficientBufferUnavailable
        case invalidDimensions(width: Int, height: Int)
        case invalidNormalizedRGBTexture
        case invalidFeatureTexture
        case textureCreationFailed
        case commandBufferUnavailable
        case commandEncoderUnavailable
        case commandExecutionFailed

        public var errorDescription: String? {
            switch self {
            case .noDevice:
                return "No Metal device is available."
            case .commandQueueUnavailable:
                return "Unable to create a Metal command queue."
            case .shaderResourceMissing:
                return "The bundled RGBNormalStem Metal source is missing."
            case .shaderSourceUnreadable:
                return "The bundled RGBNormalStem Metal source could not be read."
            case .functionMissing:
                return "The normalizedRGBToStemFeatures kernel is missing."
            case let .unsupportedOutputChannelCount(count):
                return "RGBA32Float RGB stem output requires exactly four channels; received \(count)."
            case .coefficientBufferUnavailable:
                return "Unable to allocate the RGB stem coefficient buffer."
            case let .invalidDimensions(width, height):
                return "RGB stem requires positive dimensions; received \(width)x\(height)."
            case .invalidNormalizedRGBTexture:
                return "Normalized RGB input must be an RGBA32Float texture."
            case .invalidFeatureTexture:
                return "Feature output must be a matching RGBA32Float texture."
            case .textureCreationFailed:
                return "Unable to create a Metal feature texture."
            case .commandBufferUnavailable:
                return "Unable to create a Metal command buffer."
            case .commandEncoderUnavailable:
                return "Unable to create a Metal command encoder."
            case .commandExecutionFailed:
                return "The Metal RGB stem command did not complete successfully."
            }
        }
    }

    public let device: MTLDevice
    public let commandQueue: MTLCommandQueue
    public let pipelineState: MTLComputePipelineState
    /// Original 1x1 RGB weights and bias, packed once and reused by every dispatch.
    public let coefficientBuffer: MTLBuffer
    public let stem: OneByOneStem
    /// The result of the most recently completed dispatch, useful to a caller that
    /// measures a preallocated Pipeline B preprocessing-plus-stem sequence.
    public private(set) var lastExecution: Execution?

    public init(
        device: MTLDevice? = MTLCreateSystemDefaultDevice(),
        stem: OneByOneStem = MetalNativeStem.m1FixtureStem
    ) throws {
        guard stem.outputChannels == 4 else {
            throw Error.unsupportedOutputChannelCount(stem.outputChannels)
        }
        guard let device else {
            throw Error.noDevice
        }
        guard let commandQueue = device.makeCommandQueue() else {
            throw Error.commandQueueUnavailable
        }
        guard let shaderURL = Bundle.module.url(forResource: "RGBNormalStem", withExtension: "metal") else {
            throw Error.shaderResourceMissing
        }
        guard let source = try? String(contentsOf: shaderURL, encoding: .utf8) else {
            throw Error.shaderSourceUnreadable
        }

        let library = try device.makeLibrary(source: source, options: nil)
        guard let function = library.makeFunction(name: "normalizedRGBToStemFeatures") else {
            throw Error.functionMissing
        }

        let coefficients = Self.packedCoefficients(from: stem)
        guard let coefficientBuffer = device.makeBuffer(
            bytes: coefficients,
            length: MemoryLayout<SIMD4<Float>>.stride * coefficients.count,
            options: .storageModeShared
        ) else {
            throw Error.coefficientBufferUnavailable
        }

        self.device = device
        self.commandQueue = commandQueue
        self.pipelineState = try device.makeComputePipelineState(function: function)
        self.coefficientBuffer = coefficientBuffer
        self.stem = stem
    }

    public func makeFeatureTexture(width: Int, height: Int) throws -> MTLTexture {
        try validateDimensions(width: width, height: height)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw Error.textureCreationFailed
        }
        return texture
    }

    /// Encodes and waits for only the reusable RGB-to-feature dispatch. The normalized
    /// input must be the full RGBA32Float intermediate produced by Pipeline B.
    @discardableResult
    public func execute(normalizedRGB: MTLTexture, into output: MTLTexture) throws -> Execution {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            throw Error.commandBufferUnavailable
        }
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw Error.commandEncoderUnavailable
        }

        try encode(normalizedRGB: normalizedRGB, into: output, using: encoder)
        encoder.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else {
            throw Error.commandExecutionFailed
        }

        let duration = commandBuffer.gpuEndTime > commandBuffer.gpuStartTime
            ? commandBuffer.gpuEndTime - commandBuffer.gpuStartTime
            : nil
        let execution = Execution(gpuDuration: duration)
        lastExecution = execution
        return execution
    }

    /// Binds and dispatches the normal RGB stem on a caller-owned encoder. This
    /// method neither ends the encoder nor commits or waits for its command buffer.
    public func encode(
        normalizedRGB: MTLTexture,
        into output: MTLTexture,
        using encoder: MTLComputeCommandEncoder
    ) throws {
        try validate(normalizedRGB: normalizedRGB, output: output)

        encoder.setComputePipelineState(pipelineState)
        encoder.setTexture(normalizedRGB, index: 0)
        encoder.setTexture(output, index: 1)
        encoder.setBuffer(coefficientBuffer, offset: 0, index: 0)

        let threadsPerThreadgroup = threadgroupSize()
        encoder.dispatchThreadgroups(
            MTLSize(
                width: (output.width + threadsPerThreadgroup.width - 1) / threadsPerThreadgroup.width,
                height: (output.height + threadsPerThreadgroup.height - 1) / threadsPerThreadgroup.height,
                depth: 1
            ),
            threadsPerThreadgroup: threadsPerThreadgroup
        )
    }

    private static func packedCoefficients(from stem: OneByOneStem) -> [SIMD4<Float>] {
        var packed = (0..<4).map { output in
            let base = output * 3
            return SIMD4<Float>(
                Float(stem.weights[base]),
                Float(stem.weights[base + 1]),
                Float(stem.weights[base + 2]),
                0
            )
        }
        packed.append(SIMD4<Float>(
            Float(stem.bias[0]),
            Float(stem.bias[1]),
            Float(stem.bias[2]),
            Float(stem.bias[3])
        ))
        return packed
    }

    private func validateDimensions(width: Int, height: Int) throws {
        guard width > 0, height > 0 else {
            throw Error.invalidDimensions(width: width, height: height)
        }
    }

    private func validate(normalizedRGB: MTLTexture, output: MTLTexture) throws {
        try validateDimensions(width: normalizedRGB.width, height: normalizedRGB.height)
        guard normalizedRGB.pixelFormat == .rgba32Float else {
            throw Error.invalidNormalizedRGBTexture
        }
        guard output.pixelFormat == .rgba32Float,
              output.width == normalizedRGB.width,
              output.height == normalizedRGB.height else {
            throw Error.invalidFeatureTexture
        }
    }

    private func threadgroupSize() -> MTLSize {
        let width = min(pipelineState.threadExecutionWidth, pipelineState.maxTotalThreadsPerThreadgroup)
        let height = max(1, pipelineState.maxTotalThreadsPerThreadgroup / width)
        return MTLSize(width: width, height: height, depth: 1)
    }
}
