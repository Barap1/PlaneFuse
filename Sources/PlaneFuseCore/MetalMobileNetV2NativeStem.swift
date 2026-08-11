import Foundation
import Metal

/// Pipeline C's concrete M5 stem. It reads 224x224 NV12 directly and writes the
/// 48x112x112 post-ReLU6 activation in Core ML's CHW multi-array order. The
/// output buffer is required model state, not a hidden RGB intermediate.
public final class MetalMobileNetV2NativeStem {
    public static let inputWidth = 224
    public static let inputHeight = 224
    public static let activationShape = [48, 112, 112]
    public static let activationCount = 48 * 112 * 112

    public struct ExecutionTiming: Codable, Equatable {
        public let encodeMilliseconds: Double
        public let gpuWaitMilliseconds: Double
        public let gpuExecutionMilliseconds: Double?
        public let totalMilliseconds: Double
    }

    public enum Error: LocalizedError {
        case noDevice, commandQueueUnavailable, shaderMissing, functionMissing
        case coefficientBufferUnavailable, activationBufferUnavailable, commandBufferUnavailable, encoderUnavailable
        case invalidInput, invalidOutput, executionFailed

        public var errorDescription: String? {
            switch self {
            case .noDevice: return "No Metal device is available."
            case .commandQueueUnavailable: return "Unable to create a Metal command queue."
            case .shaderMissing: return "The MobileNetV2 native stem shader is unavailable."
            case .functionMissing: return "The nv12ToMobileNetV2Stem kernel is unavailable."
            case .coefficientBufferUnavailable: return "Unable to allocate MobileNetV2 stem coefficients."
            case .activationBufferUnavailable: return "Unable to allocate the MobileNetV2 stem activation."
            case .commandBufferUnavailable: return "Unable to create a Metal command buffer."
            case .encoderUnavailable: return "Unable to create a Metal command encoder."
            case .invalidInput: return "MobileNetV2 native stem requires matching 224x224 NV12 textures."
            case .invalidOutput: return "MobileNetV2 native stem output must hold 48x112x112 Float32 values."
            case .executionFailed: return "MobileNetV2 native stem command failed."
            }
        }
    }

    public let device: MTLDevice
    public let commandQueue: MTLCommandQueue
    public let pipelineState: MTLComputePipelineState
    private let sourceReusePipelineState: MTLComputePipelineState
    private let weightBuffer: MTLBuffer
    private let offsetBuffer: MTLBuffer
    private let biasBuffer: MTLBuffer

    public init(device: MTLDevice? = MTLCreateSystemDefaultDevice(), coefficients: MobileNetV2StemCoefficients) throws {
        guard let device else { throw Error.noDevice }
        guard let queue = device.makeCommandQueue() else { throw Error.commandQueueUnavailable }
        guard let url = Bundle.module.url(forResource: "NV12MobileNetV2Stem", withExtension: "metal"),
              let source = try? String(contentsOf: url) else { throw Error.shaderMissing }
        let library = try device.makeLibrary(source: source, options: nil)
        guard let function = library.makeFunction(name: "nv12ToMobileNetV2Stem"),
              let sourceReuseFunction = library.makeFunction(name: "nv12ToMobileNetV2StemSourceReuse") else { throw Error.functionMissing }
        let normalization = RGBNormalization(mean: [0.5, 0.5, 0.5], standardDeviation: [0.5, 0.5, 0.5])
        let compiled = NativePlaneConv3x3Compiler.compile(
            semantics: .bt601VideoRange, normalization: normalization, stem: coefficients.makeStem()
        )
        guard let weights = Self.makeBuffer(device: device, values: compiled.sourceWeights),
              let offsets = Self.makeBuffer(device: device, values: compiled.sourceOffsets),
              let biases = Self.makeBuffer(device: device, values: compiled.bias) else { throw Error.coefficientBufferUnavailable }
        self.device = device; self.commandQueue = queue
        self.pipelineState = try device.makeComputePipelineState(function: function)
        self.sourceReusePipelineState = try device.makeComputePipelineState(function: sourceReuseFunction)
        self.weightBuffer = weights; self.offsetBuffer = offsets; self.biasBuffer = biases
    }

    public convenience init(device: MTLDevice? = MTLCreateSystemDefaultDevice(), coefficientsURL: URL) throws {
        try self.init(device: device, coefficients: MobileNetV2StemCoefficients.load(from: coefficientsURL))
    }

    public func makeActivationBuffer() throws -> MTLBuffer {
        guard let buffer = device.makeBuffer(length: Self.activationCount * MemoryLayout<Float>.stride, options: .storageModeShared) else {
            throw Error.activationBufferUnavailable
        }
        return buffer
    }

    public func execute(_ input: MetalRGBBaseline.NV12Textures, into activation: MTLBuffer) throws {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { throw Error.commandBufferUnavailable }
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { throw Error.encoderUnavailable }
        try encode(input, into: activation, using: encoder)
        encoder.endEncoding()
        commandBuffer.commit(); commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else { throw Error.executionFailed }
    }

    /// Returns CPU encoding and command-buffer wait regions for the R1 profile.
    public func executeTimed(_ input: MetalRGBBaseline.NV12Textures, into activation: MTLBuffer) throws -> ExecutionTiming {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { throw Error.commandBufferUnavailable }
        commandBuffer.label = "planefuse.c1.shared"
        let start = ProcessInfo.processInfo.systemUptime
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { throw Error.encoderUnavailable }
        encoder.label = "planefuse.c1.native_stem"
        try encode(input, into: activation, using: encoder)
        encoder.endEncoding()
        let encoded = ProcessInfo.processInfo.systemUptime
        commandBuffer.commit()
        let committed = ProcessInfo.processInfo.systemUptime
        commandBuffer.waitUntilCompleted()
        let completed = ProcessInfo.processInfo.systemUptime
        guard commandBuffer.status == .completed else { throw Error.executionFailed }
        return ExecutionTiming(
            encodeMilliseconds: (encoded - start) * 1_000,
            gpuWaitMilliseconds: (completed - committed) * 1_000,
            gpuExecutionMilliseconds: commandBuffer.gpuEndTime > commandBuffer.gpuStartTime ? (commandBuffer.gpuEndTime - commandBuffer.gpuStartTime) * 1_000 : nil,
            totalMilliseconds: (completed - start) * 1_000
        )
    }

    /// R7.5 profiler/experiment path. It preserves the accepted C1 boundary
    /// and tail but uses the preregistered fixed spatial-major source-reuse
    /// schedule. Production C1 `execute` remains the accepted path.
    public func executeSourceReuseTimed(_ input: MetalRGBBaseline.NV12Textures, into activation: MTLBuffer) throws -> ExecutionTiming {
        guard input.width == Self.inputWidth, input.height == Self.inputHeight,
              activation.length >= Self.activationCount * MemoryLayout<Float>.stride else { throw Error.invalidInput }
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { throw Error.commandBufferUnavailable }
        commandBuffer.label = "planefuse.c1-sr.shared"
        let start = ProcessInfo.processInfo.systemUptime
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { throw Error.encoderUnavailable }
        encoder.label = "planefuse.c1-sr.source-reuse"
        try encodeSourceReuse(input, into: activation, using: encoder)
        encoder.endEncoding()
        let encoded = ProcessInfo.processInfo.systemUptime
        commandBuffer.commit(); commandBuffer.waitUntilCompleted()
        let completed = ProcessInfo.processInfo.systemUptime
        guard commandBuffer.status == .completed else { throw Error.executionFailed }
        return ExecutionTiming(
            encodeMilliseconds: (encoded - start) * 1_000,
            gpuWaitMilliseconds: (completed - encoded) * 1_000,
            gpuExecutionMilliseconds: commandBuffer.gpuEndTime > commandBuffer.gpuStartTime ? (commandBuffer.gpuEndTime - commandBuffer.gpuStartTime) * 1_000 : nil,
            totalMilliseconds: (completed - start) * 1_000
        )
    }

    /// Production form of the R7.5 candidate. It has the same accepted C1
    /// boundary as `execute`, but encodes the preregistered source-reuse
    /// schedule without profiler-only timing or labels.
    public func executeSourceReuse(_ input: MetalRGBBaseline.NV12Textures, into activation: MTLBuffer) throws {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { throw Error.commandBufferUnavailable }
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { throw Error.encoderUnavailable }
        try encodeSourceReuse(input, into: activation, using: encoder)
        encoder.endEncoding()
        commandBuffer.commit(); commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else { throw Error.executionFailed }
    }

    /// Encodes only Pipeline C's native stem. The caller owns submission, enabling
    /// an explicit one-submission comparison with Pipeline B.
    public func encode(
        _ input: MetalRGBBaseline.NV12Textures,
        into activation: MTLBuffer,
        using encoder: MTLComputeCommandEncoder
    ) throws {
        guard input.width == Self.inputWidth, input.height == Self.inputHeight,
              input.yPlane.pixelFormat == .r8Uint, input.uvPlane.pixelFormat == .rg8Uint else { throw Error.invalidInput }
        guard activation.length >= Self.activationCount * MemoryLayout<Float>.stride else { throw Error.invalidOutput }
        encoder.setComputePipelineState(pipelineState)
        encoder.setTexture(input.yPlane, index: 0); encoder.setTexture(input.uvPlane, index: 1)
        encoder.setBuffer(activation, offset: 0, index: 0); encoder.setBuffer(weightBuffer, offset: 0, index: 1)
        encoder.setBuffer(offsetBuffer, offset: 0, index: 2); encoder.setBuffer(biasBuffer, offset: 0, index: 3)
        encoder.dispatchThreads(MTLSize(width: 112, height: 112, depth: 48), threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
    }

    private func encodeSourceReuse(
        _ input: MetalRGBBaseline.NV12Textures,
        into activation: MTLBuffer,
        using encoder: MTLComputeCommandEncoder
    ) throws {
        guard input.width == Self.inputWidth, input.height == Self.inputHeight,
              input.yPlane.pixelFormat == .r8Uint, input.uvPlane.pixelFormat == .rg8Uint else { throw Error.invalidInput }
        guard activation.length >= Self.activationCount * MemoryLayout<Float>.stride else { throw Error.invalidOutput }
        encoder.setComputePipelineState(sourceReusePipelineState)
        encoder.setTexture(input.yPlane, index: 0); encoder.setTexture(input.uvPlane, index: 1)
        encoder.setBuffer(activation, offset: 0, index: 0); encoder.setBuffer(weightBuffer, offset: 0, index: 1)
        encoder.setBuffer(offsetBuffer, offset: 0, index: 2); encoder.setBuffer(biasBuffer, offset: 0, index: 3)
        encoder.dispatchThreadgroups(MTLSize(width: 28, height: 28, depth: 1), threadsPerThreadgroup: MTLSize(width: 128, height: 1, depth: 1))
    }

    public func readActivation(from buffer: MTLBuffer) throws -> [Float] {
        guard buffer.length >= Self.activationCount * MemoryLayout<Float>.stride else { throw Error.invalidOutput }
        return Array(UnsafeBufferPointer(start: buffer.contents().assumingMemoryBound(to: Float.self), count: Self.activationCount))
    }

    private static func makeBuffer(device: MTLDevice, values: [Double]) -> MTLBuffer? {
        let floats = values.map(Float.init)
        return floats.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }
    }
}
