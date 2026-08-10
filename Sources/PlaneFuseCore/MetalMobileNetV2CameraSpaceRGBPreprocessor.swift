import Foundation
import Metal

/// Conventional Pipeline B camera-space preprocessing. It materializes the
/// required 224x224 planar normalized Float32 RGB input without retaining a
/// resized NV12 intermediate; callers then encode the unchanged CHW RGB stem.
public final class MetalMobileNetV2CameraSpaceRGBPreprocessor {
    public enum Error: Swift.Error, LocalizedError {
        case noDevice, commandQueueUnavailable, shaderMissing, functionMissing
        case normalizedRGBBufferUnavailable, commandBufferUnavailable, encoderUnavailable
        case invalidMapping, invalidOutput, executionFailed

        public var errorDescription: String? {
            switch self {
            case .noDevice: return "No Metal device is available."
            case .commandQueueUnavailable: return "Unable to create a Metal command queue."
            case .shaderMissing: return "The camera-space NV12 RGB shader is unavailable."
            case .functionMissing: return "The camera-space NV12 RGB kernel is unavailable."
            case .normalizedRGBBufferUnavailable: return "Unable to allocate planar normalized RGB storage."
            case .commandBufferUnavailable: return "Unable to create a Metal command buffer."
            case .encoderUnavailable: return "Unable to create a Metal command encoder."
            case .invalidMapping: return "Camera-space mapping does not match the supplied NV12 source textures."
            case .invalidOutput: return "Planar normalized RGB must hold 3x224x224 Float32 values."
            case .executionFailed: return "Camera-space NV12 RGB command failed."
            }
        }
    }

    public static let normalizedRGBCount = 3 * 224 * 224

    public let device: MTLDevice
    public let commandQueue: MTLCommandQueue
    public let pipelineState: MTLComputePipelineState

    public init(device: MTLDevice? = MTLCreateSystemDefaultDevice()) throws {
        guard let device else { throw Error.noDevice }
        guard let queue = device.makeCommandQueue() else { throw Error.commandQueueUnavailable }
        guard let url = Bundle.module.url(forResource: "CameraSpaceNV12RGB", withExtension: "metal"),
              let source = try? String(contentsOf: url) else { throw Error.shaderMissing }
        let library = try device.makeLibrary(source: source, options: nil)
        guard let function = library.makeFunction(name: "cameraSpaceNV12ToMobileNetV2NormalizedRGBCHW") else {
            throw Error.functionMissing
        }
        self.device = device
        self.commandQueue = queue
        self.pipelineState = try device.makeComputePipelineState(function: function)
    }

    public func makeNormalizedRGBCHWBuffer() throws -> MTLBuffer {
        guard let buffer = device.makeBuffer(
            length: Self.normalizedRGBCount * MemoryLayout<Float>.stride,
            options: .storageModeShared
        ) else { throw Error.normalizedRGBBufferUnavailable }
        return buffer
    }

    /// Convenience for synchronous tests. Production callers should encode this
    /// dispatch and `MetalMobileNetV2RGBPipeline.encodeCHWStem` in one buffer.
    public func execute(_ source: MetalCameraNV12SourceTextures, mapping: CameraSpaceMapping, into normalizedRGB: MTLBuffer) throws {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { throw Error.commandBufferUnavailable }
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { throw Error.encoderUnavailable }
        try encode(source, mapping: mapping, into: normalizedRGB, using: encoder)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else { throw Error.executionFailed }
    }

    /// Encodes only direct camera-space RGB materialization. The caller owns
    /// encoder end, command-buffer submission, and source-texture lease lifetime.
    public func encode(
        _ source: MetalCameraNV12SourceTextures,
        mapping: CameraSpaceMapping,
        into normalizedRGB: MTLBuffer,
        using encoder: MTLComputeCommandEncoder
    ) throws {
        try validate(source: source, mapping: mapping)
        guard normalizedRGB.length >= Self.normalizedRGBCount * MemoryLayout<Float>.stride else {
            throw Error.invalidOutput
        }
        var parameters = CameraSpaceMetalParameters(mapping: mapping)
        encoder.setComputePipelineState(pipelineState)
        encoder.setTexture(source.yPlane, index: 0)
        encoder.setTexture(source.uvPlane, index: 1)
        encoder.setBuffer(normalizedRGB, offset: 0, index: 0)
        encoder.setBytes(&parameters, length: MemoryLayout<CameraSpaceMetalParameters>.stride, index: 1)
        encoder.dispatchThreads(
            MTLSize(width: 224, height: 224, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1)
        )
    }

    public func readNormalizedRGB(from buffer: MTLBuffer) throws -> [Float] {
        guard buffer.length >= Self.normalizedRGBCount * MemoryLayout<Float>.stride else { throw Error.invalidOutput }
        return Array(UnsafeBufferPointer(
            start: buffer.contents().assumingMemoryBound(to: Float.self), count: Self.normalizedRGBCount
        ))
    }

    private func validate(source: MetalCameraNV12SourceTextures, mapping: CameraSpaceMapping) throws {
        guard source.width == mapping.sourceWidth,
              source.height == mapping.sourceHeight,
              mapping.cropOriginX >= 0, mapping.cropOriginY >= 0, mapping.cropSide >= 2,
              mapping.cropOriginX <= Int(UInt32.max), mapping.cropOriginY <= Int(UInt32.max),
              mapping.cropSide <= Int(UInt32.max) else {
            throw Error.invalidMapping
        }
    }
}
