import Foundation
import Metal

/// R5 Experiment A implementation generated from the exact nearest-sited
/// polyphase compiler. It is kept separate from the accepted native stem until
/// parity and model-boundary timing are both measured.
public final class MetalMobileNetV2PolyphaseStem {
    public let device: MTLDevice
    public let commandQueue: MTLCommandQueue
    private let pipelineState: MTLComputePipelineState
    private let lumaWeights: MTLBuffer
    private let chromaWeights: MTLBuffer
    private let sourceOffsets: MTLBuffer
    private let bias: MTLBuffer

    public init(device: MTLDevice? = MTLCreateSystemDefaultDevice(), coefficients: MobileNetV2StemCoefficients) throws {
        guard let device else { throw MetalMobileNetV2NativeStem.Error.noDevice }
        guard let queue = device.makeCommandQueue() else { throw MetalMobileNetV2NativeStem.Error.commandQueueUnavailable }
        guard let url = Bundle.module.url(forResource: "NV12MobileNetV2Stem", withExtension: "metal"),
              let source = try? String(contentsOf: url) else { throw MetalMobileNetV2NativeStem.Error.shaderMissing }
        let library = try device.makeLibrary(source: source, options: nil)
        guard let function = library.makeFunction(name: "nv12ToMobileNetV2StemPolyphase") else { throw MetalMobileNetV2NativeStem.Error.functionMissing }
        let plan = NativePlaneConv3x3Compiler.compilePolyphase(
            semantics: .bt601VideoRange,
            normalization: RGBNormalization(mean: [0.5, 0.5, 0.5], standardDeviation: [0.5, 0.5, 0.5]),
            stem: coefficients.makeStem()
        )
        guard let luma = Self.makeBuffer(device: device, values: plan.lumaWeights),
              let chroma = Self.makeBuffer(device: device, values: plan.chromaWeights),
              let offsets = Self.makeBuffer(device: device, values: plan.sourceOffsets),
              let biases = Self.makeBuffer(device: device, values: plan.bias) else { throw MetalMobileNetV2NativeStem.Error.coefficientBufferUnavailable }
        self.device = device; self.commandQueue = queue
        self.pipelineState = try device.makeComputePipelineState(function: function)
        self.lumaWeights = luma; self.chromaWeights = chroma; self.sourceOffsets = offsets; self.bias = biases
    }

    public func makeActivationBuffer() throws -> MTLBuffer {
        guard let buffer = device.makeBuffer(length: MetalMobileNetV2NativeStem.activationCount * MemoryLayout<Float>.stride, options: .storageModeShared) else {
            throw MetalMobileNetV2NativeStem.Error.activationBufferUnavailable
        }
        return buffer
    }

    public func execute(_ input: MetalRGBBaseline.NV12Textures, into activation: MTLBuffer) throws {
        guard input.width == 224, input.height == 224, activation.length >= MetalMobileNetV2NativeStem.activationCount * MemoryLayout<Float>.stride else {
            throw MetalMobileNetV2NativeStem.Error.invalidInput
        }
        guard let commandBuffer = commandQueue.makeCommandBuffer(), let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw MetalMobileNetV2NativeStem.Error.commandBufferUnavailable
        }
        encoder.setComputePipelineState(pipelineState)
        encoder.setTexture(input.yPlane, index: 0); encoder.setTexture(input.uvPlane, index: 1)
        encoder.setBuffer(activation, offset: 0, index: 0); encoder.setBuffer(lumaWeights, offset: 0, index: 1)
        encoder.setBuffer(chromaWeights, offset: 0, index: 2); encoder.setBuffer(sourceOffsets, offset: 0, index: 3); encoder.setBuffer(bias, offset: 0, index: 4)
        encoder.dispatchThreads(MTLSize(width: 112, height: 112, depth: 48), threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
        encoder.endEncoding(); commandBuffer.commit(); commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else { throw MetalMobileNetV2NativeStem.Error.executionFailed }
    }

    public func readActivation(from buffer: MTLBuffer) throws -> [Float] {
        guard buffer.length >= MetalMobileNetV2NativeStem.activationCount * MemoryLayout<Float>.stride else { throw MetalMobileNetV2NativeStem.Error.invalidOutput }
        return Array(UnsafeBufferPointer(start: buffer.contents().assumingMemoryBound(to: Float.self), count: MetalMobileNetV2NativeStem.activationCount))
    }

    private static func makeBuffer(device: MTLDevice, values: [Double]) -> MTLBuffer? {
        let floats = values.map(Float.init)
        return floats.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }
    }
}
