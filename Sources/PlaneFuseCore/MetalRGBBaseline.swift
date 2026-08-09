import Foundation
import Metal

/// Pipeline B preprocessing: direct NV12 plane reads followed by BT.601 video-range
/// decode, normalization, and materialization of a full RGBA32Float intermediate.
///
/// The initializer compiles the bundled shader and creates the reusable pipeline state.
/// Calls to ``execute(_:into:)`` only encode and run the conversion work.
public final class MetalRGBBaseline {
    public struct NV12Textures {
        public let yPlane: MTLTexture
        public let uvPlane: MTLTexture

        public var width: Int { yPlane.width }
        public var height: Int { yPlane.height }
    }

    public struct Execution {
        /// GPU time for the command buffer containing only this conversion dispatch,
        /// when the driver provides GPU timestamps.
        public let gpuDuration: TimeInterval?
    }

    public enum Error: Swift.Error, LocalizedError {
        case noDevice
        case commandQueueUnavailable
        case shaderResourceMissing
        case shaderSourceUnreadable
        case functionMissing
        case invalidDimensions(width: Int, height: Int)
        case invalidYPlaneByteCount(expected: Int, actual: Int)
        case invalidUVPlaneByteCount(expected: Int, actual: Int)
        case invalidInputTextures
        case invalidOutputTexture
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
                return "The bundled NV12RGB Metal source is missing."
            case .shaderSourceUnreadable:
                return "The bundled NV12RGB Metal source could not be read."
            case .functionMissing:
                return "The nv12ToNormalizedRGBA kernel is missing."
            case let .invalidDimensions(width, height):
                return "NV12 requires positive even dimensions; received \(width)x\(height)."
            case let .invalidYPlaneByteCount(expected, actual):
                return "Y plane needs \(expected) bytes; received \(actual)."
            case let .invalidUVPlaneByteCount(expected, actual):
                return "UV plane needs \(expected) bytes; received \(actual)."
            case .invalidInputTextures:
                return "Input textures must be matching NV12 R8Uint and RG8Uint planes."
            case .invalidOutputTexture:
                return "Output must be a matching RGBA32Float texture."
            case .textureCreationFailed:
                return "Unable to create a Metal texture."
            case .commandBufferUnavailable:
                return "Unable to create a Metal command buffer."
            case .commandEncoderUnavailable:
                return "Unable to create a Metal command encoder."
            case .commandExecutionFailed:
                return "The Metal NV12 conversion command did not complete successfully."
            }
        }
    }

    public let device: MTLDevice
    public let commandQueue: MTLCommandQueue
    public let pipelineState: MTLComputePipelineState

    public init(device: MTLDevice? = MTLCreateSystemDefaultDevice()) throws {
        guard let device else {
            throw Error.noDevice
        }
        guard let commandQueue = device.makeCommandQueue() else {
            throw Error.commandQueueUnavailable
        }
        guard let shaderURL = Bundle.module.url(forResource: "NV12RGB", withExtension: "metal") else {
            throw Error.shaderResourceMissing
        }
        guard let source = try? String(contentsOf: shaderURL, encoding: .utf8) else {
            throw Error.shaderSourceUnreadable
        }

        let library = try device.makeLibrary(source: source, options: nil)
        guard let function = library.makeFunction(name: "nv12ToNormalizedRGBA") else {
            throw Error.functionMissing
        }

        self.device = device
        self.commandQueue = commandQueue
        self.pipelineState = try device.makeComputePipelineState(function: function)
    }

    public func makeNV12Textures(
        width: Int,
        height: Int,
        yPlaneBytes: [UInt8],
        uvPlaneBytes: [UInt8]
    ) throws -> NV12Textures {
        try validateDimensions(width: width, height: height)
        let yByteCount = width * height
        let uvByteCount = width * height / 2
        guard yPlaneBytes.count == yByteCount else {
            throw Error.invalidYPlaneByteCount(expected: yByteCount, actual: yPlaneBytes.count)
        }
        guard uvPlaneBytes.count == uvByteCount else {
            throw Error.invalidUVPlaneByteCount(expected: uvByteCount, actual: uvPlaneBytes.count)
        }

        let yDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Uint,
            width: width,
            height: height,
            mipmapped: false
        )
        yDescriptor.usage = [.shaderRead]
        yDescriptor.storageMode = .shared
        let uvDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rg8Uint,
            width: width / 2,
            height: height / 2,
            mipmapped: false
        )
        uvDescriptor.usage = [.shaderRead]
        uvDescriptor.storageMode = .shared
        guard let yPlane = device.makeTexture(descriptor: yDescriptor),
              let uvPlane = device.makeTexture(descriptor: uvDescriptor) else {
            throw Error.textureCreationFailed
        }

        yPlaneBytes.withUnsafeBytes { source in
            yPlane.replace(
                region: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0,
                withBytes: source.baseAddress!,
                bytesPerRow: width
            )
        }
        uvPlaneBytes.withUnsafeBytes { source in
            uvPlane.replace(
                region: MTLRegionMake2D(0, 0, width / 2, height / 2),
                mipmapLevel: 0,
                withBytes: source.baseAddress!,
                bytesPerRow: width
            )
        }

        return NV12Textures(yPlane: yPlane, uvPlane: uvPlane)
    }

    public func makeRGBA32FloatTexture(width: Int, height: Int) throws -> MTLTexture {
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

    @discardableResult
    public func execute(_ input: NV12Textures, into output: MTLTexture) throws -> Execution {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            throw Error.commandBufferUnavailable
        }
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw Error.commandEncoderUnavailable
        }

        try encode(input, into: output, using: encoder)
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

    /// Binds and dispatches the NV12-to-normalized-RGBA conversion on a caller-owned
    /// encoder. This method neither ends the encoder nor commits or waits for its
    /// command buffer, allowing Pipeline B to compose this work with its RGB stem.
    public func encode(
        _ input: NV12Textures,
        into output: MTLTexture,
        using encoder: MTLComputeCommandEncoder
    ) throws {
        try validate(input: input, output: output)

        encoder.setComputePipelineState(pipelineState)
        encoder.setTexture(input.yPlane, index: 0)
        encoder.setTexture(input.uvPlane, index: 1)
        encoder.setTexture(output, index: 2)

        let threadsPerThreadgroup = threadgroupSize()
        let threadgroups = MTLSize(
            width: (output.width + threadsPerThreadgroup.width - 1) / threadsPerThreadgroup.width,
            height: (output.height + threadsPerThreadgroup.height - 1) / threadsPerThreadgroup.height,
            depth: 1
        )
        encoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadsPerThreadgroup)
    }

    public func readRGBA32Float(from texture: MTLTexture) throws -> [Float] {
        guard texture.pixelFormat == .rgba32Float else {
            throw Error.invalidOutputTexture
        }

        var pixels = [Float](repeating: 0, count: texture.width * texture.height * 4)
        pixels.withUnsafeMutableBytes { destination in
            texture.getBytes(
                destination.baseAddress!,
                bytesPerRow: texture.width * MemoryLayout<Float>.stride * 4,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height),
                mipmapLevel: 0
            )
        }
        return pixels
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
            throw Error.invalidOutputTexture
        }
    }

    private func threadgroupSize() -> MTLSize {
        let width = min(pipelineState.threadExecutionWidth, pipelineState.maxTotalThreadsPerThreadgroup)
        let height = max(1, pipelineState.maxTotalThreadsPerThreadgroup / width)
        return MTLSize(width: width, height: height, depth: 1)
    }
}
