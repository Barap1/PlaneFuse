import Foundation
import Metal

/// Retained source-plane textures for camera-space kernels. Camera-backed
/// textures are normally supplied by a lease that also retains their Core Video
/// wrappers until the owning command buffer has completed.
public struct MetalCameraNV12SourceTextures {
    public enum Error: Swift.Error, LocalizedError, Equatable {
        case invalidYPlaneFormat
        case invalidUVPlaneFormat
        case invalidDimensions

        public var errorDescription: String? {
            switch self {
            case .invalidYPlaneFormat:
                return "Camera-space NV12 luma must be an R8Unorm texture."
            case .invalidUVPlaneFormat:
                return "Camera-space NV12 chroma must be an RG8Unorm texture."
            case .invalidDimensions:
                return "Camera-space NV12 planes must have matching luma and half-resolution chroma dimensions."
            }
        }
    }

    public let yPlane: MTLTexture
    public let uvPlane: MTLTexture
    public let width: Int
    public let height: Int

    public init(yPlane: MTLTexture, uvPlane: MTLTexture) throws {
        guard yPlane.pixelFormat == .r8Unorm else { throw Error.invalidYPlaneFormat }
        guard uvPlane.pixelFormat == .rg8Unorm else { throw Error.invalidUVPlaneFormat }
        guard yPlane.width > 0, yPlane.height > 0,
              uvPlane.width == yPlane.width / 2,
              uvPlane.height == yPlane.height / 2 else {
            throw Error.invalidDimensions
        }
        self.yPlane = yPlane
        self.uvPlane = uvPlane
        self.width = yPlane.width
        self.height = yPlane.height
    }
}

/// Pipeline C's direct camera-space MobileNetV2 stem. It composes the accepted
/// camera crop/nearest-resize mapping with the unchanged native-plane stem and
/// writes the same Float32 CHW activation without materializing resized NV12.
public final class MetalMobileNetV2CameraSpaceStem {
    public enum Error: Swift.Error, LocalizedError {
        case noDevice, commandQueueUnavailable, shaderMissing, functionMissing
        case coefficientBufferUnavailable, activationBufferUnavailable, commandBufferUnavailable, encoderUnavailable
        case invalidMapping, invalidOutput, executionFailed

        public var errorDescription: String? {
            switch self {
            case .noDevice: return "No Metal device is available."
            case .commandQueueUnavailable: return "Unable to create a Metal command queue."
            case .shaderMissing: return "The camera-space MobileNetV2 stem shader is unavailable."
            case .functionMissing: return "The camera-space MobileNetV2 stem kernel is unavailable."
            case .coefficientBufferUnavailable: return "Unable to allocate MobileNetV2 stem coefficients."
            case .activationBufferUnavailable: return "Unable to allocate the MobileNetV2 stem activation."
            case .commandBufferUnavailable: return "Unable to create a Metal command buffer."
            case .encoderUnavailable: return "Unable to create a Metal command encoder."
            case .invalidMapping: return "Camera-space mapping does not match the supplied NV12 source textures."
            case .invalidOutput: return "Camera-space MobileNetV2 stem output must hold 48x112x112 Float32 values."
            case .executionFailed: return "Camera-space MobileNetV2 stem command failed."
            }
        }
    }

    public let device: MTLDevice
    public let commandQueue: MTLCommandQueue
    public let pipelineState: MTLComputePipelineState
    private let weightBuffer: MTLBuffer
    private let offsetBuffer: MTLBuffer
    private let biasBuffer: MTLBuffer

    public init(device: MTLDevice? = MTLCreateSystemDefaultDevice(), coefficients: MobileNetV2StemCoefficients) throws {
        guard let device else { throw Error.noDevice }
        guard let queue = device.makeCommandQueue() else { throw Error.commandQueueUnavailable }
        guard let url = Bundle.module.url(forResource: "NV12MobileNetV2CameraSpaceStem", withExtension: "metal"),
              let source = try? String(contentsOf: url) else { throw Error.shaderMissing }
        let library = try device.makeLibrary(source: source, options: nil)
        guard let function = library.makeFunction(name: "cameraSpaceNV12ToMobileNetV2Stem") else { throw Error.functionMissing }
        let normalization = RGBNormalization(mean: [0.5, 0.5, 0.5], standardDeviation: [0.5, 0.5, 0.5])
        let compiled = NativePlaneConv3x3Compiler.compile(
            semantics: .bt601VideoRange, normalization: normalization, stem: coefficients.makeStem()
        )
        guard let weights = Self.makeBuffer(device: device, values: compiled.sourceWeights),
              let offsets = Self.makeBuffer(device: device, values: compiled.sourceOffsets),
              let biases = Self.makeBuffer(device: device, values: compiled.bias) else {
            throw Error.coefficientBufferUnavailable
        }
        self.device = device
        self.commandQueue = queue
        self.pipelineState = try device.makeComputePipelineState(function: function)
        self.weightBuffer = weights
        self.offsetBuffer = offsets
        self.biasBuffer = biases
    }

    public convenience init(device: MTLDevice? = MTLCreateSystemDefaultDevice(), coefficientsURL: URL) throws {
        try self.init(device: device, coefficients: MobileNetV2StemCoefficients.load(from: coefficientsURL))
    }

    public func makeActivationBuffer() throws -> MTLBuffer {
        guard let buffer = device.makeBuffer(
            length: MetalMobileNetV2NativeStem.activationCount * MemoryLayout<Float>.stride,
            options: .storageModeShared
        ) else { throw Error.activationBufferUnavailable }
        return buffer
    }

    /// Convenience for synchronous tests. Production callers should use
    /// ``encode(_:mapping:into:using:)`` in their own ordered command buffer.
    public func execute(_ source: MetalCameraNV12SourceTextures, mapping: CameraSpaceMapping, into activation: MTLBuffer) throws {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { throw Error.commandBufferUnavailable }
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { throw Error.encoderUnavailable }
        try encode(source, mapping: mapping, into: activation, using: encoder)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else { throw Error.executionFailed }
    }

    /// Encodes only the direct native-plane stem. The caller owns encoder end,
    /// command-buffer submission, and source-texture lease lifetime.
    public func encode(
        _ source: MetalCameraNV12SourceTextures,
        mapping: CameraSpaceMapping,
        into activation: MTLBuffer,
        using encoder: MTLComputeCommandEncoder
    ) throws {
        try validate(source: source, mapping: mapping)
        guard activation.length >= MetalMobileNetV2NativeStem.activationCount * MemoryLayout<Float>.stride else {
            throw Error.invalidOutput
        }
        var parameters = CameraSpaceMetalParameters(mapping: mapping)
        encoder.setComputePipelineState(pipelineState)
        encoder.setTexture(source.yPlane, index: 0)
        encoder.setTexture(source.uvPlane, index: 1)
        encoder.setBuffer(activation, offset: 0, index: 0)
        encoder.setBuffer(weightBuffer, offset: 0, index: 1)
        encoder.setBuffer(offsetBuffer, offset: 0, index: 2)
        encoder.setBuffer(biasBuffer, offset: 0, index: 3)
        encoder.setBytes(&parameters, length: MemoryLayout<CameraSpaceMetalParameters>.stride, index: 4)
        encoder.dispatchThreads(
            MTLSize(width: 112, height: 112, depth: 48),
            threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1)
        )
    }

    public func readActivation(from buffer: MTLBuffer) throws -> [Float] {
        guard buffer.length >= MetalMobileNetV2NativeStem.activationCount * MemoryLayout<Float>.stride else {
            throw Error.invalidOutput
        }
        return Array(UnsafeBufferPointer(
            start: buffer.contents().assumingMemoryBound(to: Float.self),
            count: MetalMobileNetV2NativeStem.activationCount
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

    private static func makeBuffer(device: MTLDevice, values: [Double]) -> MTLBuffer? {
        let floats = values.map(Float.init)
        return floats.withUnsafeBytes {
            device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared)
        }
    }
}

struct CameraSpaceMetalParameters {
    var cropOriginX: UInt32
    var cropOriginY: UInt32
    var cropSide: UInt32

    init(mapping: CameraSpaceMapping) {
        self.cropOriginX = UInt32(mapping.cropOriginX)
        self.cropOriginY = UInt32(mapping.cropOriginY)
        self.cropSide = UInt32(mapping.cropSide)
    }
}
