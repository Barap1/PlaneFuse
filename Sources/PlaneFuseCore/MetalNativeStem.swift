import Foundation
import Metal

/// Pipeline C native-plane stem: reads NV12 source planes and directly writes the
/// first four stem features without materializing RGB or normalized-RGB textures.
public final class MetalNativeStem {
    public typealias NV12Textures = MetalRGBBaseline.NV12Textures

    public struct Execution {
        /// GPU time for the command buffer containing only this reusable native-stem
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
        case invalidInputTextures
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
                return "The bundled NV12NativeStem Metal source is missing."
            case .shaderSourceUnreadable:
                return "The bundled NV12NativeStem Metal source could not be read."
            case .functionMissing:
                return "The nv12ToNativeStemFeatures kernel is missing."
            case let .unsupportedOutputChannelCount(count):
                return "RGBA32Float native stem output requires exactly four channels; received \(count)."
            case .coefficientBufferUnavailable:
                return "Unable to allocate the native stem coefficient buffer."
            case let .invalidDimensions(width, height):
                return "NV12 requires positive even dimensions; received \(width)x\(height)."
            case .invalidInputTextures:
                return "Input textures must be matching NV12 R8Uint and RG8Uint planes."
            case .invalidFeatureTexture:
                return "Feature output must be a matching RGBA32Float texture."
            case .textureCreationFailed:
                return "Unable to create a Metal feature texture."
            case .commandBufferUnavailable:
                return "Unable to create a Metal command buffer."
            case .commandEncoderUnavailable:
                return "Unable to create a Metal command encoder."
            case .commandExecutionFailed:
                return "The Metal native stem command did not complete successfully."
            }
        }
    }

    /// The deterministic M1 fixture configuration used by the initial Pipeline C.
    public static let m1FixtureNormalization = RGBNormalization(
        mean: [0.485, 0.456, 0.406],
        standardDeviation: [0.229, 0.224, 0.225]
    )

    /// The four-output 1x1 stem from the M1 reference parity fixture.
    public static let m1FixtureStem = OneByOneStem(
        weights: [
            0.25, -0.50, 0.75,
            -0.20, 0.40, 0.10,
            0.90, 0.05, -0.30,
            0.12, 0.33, 0.27,
        ],
        bias: [0.10, -0.20, 0.30, 0.05]
    )

    public let device: MTLDevice
    public let commandQueue: MTLCommandQueue
    public let pipelineState: MTLComputePipelineState
    /// Compiled once during initialization and reused by every execution dispatch.
    public let coefficientBuffer: MTLBuffer
    public let compiledStem: NativePlaneStem

    public init(
        device: MTLDevice? = MTLCreateSystemDefaultDevice(),
        stem: OneByOneStem = MetalNativeStem.m1FixtureStem,
        semantics: NV12Semantics = .bt601VideoRange,
        normalization: RGBNormalization = MetalNativeStem.m1FixtureNormalization
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
        guard let shaderURL = Bundle.module.url(forResource: "NV12NativeStem", withExtension: "metal") else {
            throw Error.shaderResourceMissing
        }
        guard let source = try? String(contentsOf: shaderURL, encoding: .utf8) else {
            throw Error.shaderSourceUnreadable
        }

        let library = try device.makeLibrary(source: source, options: nil)
        guard let function = library.makeFunction(name: "nv12ToNativeStemFeatures") else {
            throw Error.functionMissing
        }

        let compiledStem = NativePlaneStemCompiler.compile(
            semantics: semantics,
            normalization: normalization,
            stem: stem
        )
        let coefficients = Self.packedCoefficients(from: compiledStem)
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
        self.compiledStem = compiledStem
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

    /// Encodes and waits for exactly the reusable Pipeline C dispatch. Inputs,
    /// output texture, pipeline, queue, and coefficient buffer are externally
    /// visible so a later benchmark can isolate this region without setup costs.
    @discardableResult
    public func execute(_ input: NV12Textures, into output: MTLTexture) throws -> Execution {
        try validate(input: input, output: output)
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            throw Error.commandBufferUnavailable
        }
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw Error.commandEncoderUnavailable
        }

        encoder.setComputePipelineState(pipelineState)
        encoder.setTexture(input.yPlane, index: 0)
        encoder.setTexture(input.uvPlane, index: 1)
        encoder.setTexture(output, index: 2)
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
        encoder.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else {
            throw Error.commandExecutionFailed
        }

        let duration = commandBuffer.gpuEndTime > commandBuffer.gpuStartTime
            ? commandBuffer.gpuEndTime - commandBuffer.gpuStartTime
            : nil
        return Execution(gpuDuration: duration)
    }

    private static func packedCoefficients(from compiledStem: NativePlaneStem) -> [SIMD4<Float>] {
        var packed = (0..<4).map { output in
            let base = output * 3
            return SIMD4<Float>(
                Float(compiledStem.sourceWeights[base]),
                Float(compiledStem.sourceWeights[base + 1]),
                Float(compiledStem.sourceWeights[base + 2]),
                0
            )
        }
        packed.append(SIMD4<Float>(
            Float(compiledStem.sourceBias[0]),
            Float(compiledStem.sourceBias[1]),
            Float(compiledStem.sourceBias[2]),
            Float(compiledStem.sourceBias[3])
        ))
        return packed
    }

    private func validateDimensions(width: Int, height: Int) throws {
        guard width > 0, height > 0, width.isMultiple(of: 2), height.isMultiple(of: 2) else {
            throw Error.invalidDimensions(width: width, height: height)
        }
    }

    private func validate(input: NV12Textures, output: MTLTexture) throws {
        try validateDimensions(width: input.width, height: input.height)
        guard input.yPlane.pixelFormat == .r8Uint,
              input.uvPlane.pixelFormat == .rg8Uint,
              input.uvPlane.width == input.width / 2,
              input.uvPlane.height == input.height / 2 else {
            throw Error.invalidInputTextures
        }
        guard output.pixelFormat == .rgba32Float,
              output.width == input.width,
              output.height == input.height else {
            throw Error.invalidFeatureTexture
        }
    }

    private func threadgroupSize() -> MTLSize {
        let width = min(pipelineState.threadExecutionWidth, pipelineState.maxTotalThreadsPerThreadgroup)
        let height = max(1, pipelineState.maxTotalThreadsPerThreadgroup / width)
        return MTLSize(width: width, height: height, depth: 1)
    }
}
