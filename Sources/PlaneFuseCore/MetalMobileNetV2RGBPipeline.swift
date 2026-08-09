import Foundation
import Metal

/// Pipeline B for the real MobileNetV2 boundary. Its end-to-end convenience API
/// uses exactly one command buffer submission containing two ordered encoders:
/// NV12→normalized RGBA, then ordinary RGB Conv+BN+ReLU6.
public final class MetalMobileNetV2RGBPipeline {
    public typealias NV12Textures = MetalRGBBaseline.NV12Textures
    public let device: MTLDevice
    public let commandQueue: MTLCommandQueue
    private let conversionPipeline: MTLComputePipelineState
    private let stemPipeline: MTLComputePipelineState
    private let weights: MTLBuffer
    private let bias: MTLBuffer

    public init(device: MTLDevice? = MTLCreateSystemDefaultDevice(), coefficients: MobileNetV2StemCoefficients) throws {
        guard let device else { throw MetalMobileNetV2NativeStem.Error.noDevice }
        guard let queue = device.makeCommandQueue() else { throw MetalMobileNetV2NativeStem.Error.commandQueueUnavailable }
        guard let url = Bundle.module.url(forResource: "NV12MobileNetV2RGB", withExtension: "metal"),
              let source = try? String(contentsOf: url) else { throw MetalMobileNetV2NativeStem.Error.shaderMissing }
        let library = try device.makeLibrary(source: source, options: nil)
        guard let conversion = library.makeFunction(name: "nv12ToMobileNetV2NormalizedRGBA"),
              let stem = library.makeFunction(name: "mobileNetV2RGBStem") else { throw MetalMobileNetV2NativeStem.Error.functionMissing }
        let folded = Self.foldBatchNorm(coefficients)
        guard let weights = Self.makeBuffer(device: device, values: folded.weights),
              let bias = Self.makeBuffer(device: device, values: folded.bias) else { throw MetalMobileNetV2NativeStem.Error.coefficientBufferUnavailable }
        self.device = device; self.commandQueue = queue
        self.conversionPipeline = try device.makeComputePipelineState(function: conversion)
        self.stemPipeline = try device.makeComputePipelineState(function: stem)
        self.weights = weights; self.bias = bias
    }

    public func makeNormalizedRGBTexture() throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba32Float, width: 224, height: 224, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]; descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else { throw MetalMobileNetV2NativeStem.Error.invalidOutput }
        return texture
    }

    public func makeActivationBuffer() throws -> MTLBuffer {
        guard let buffer = device.makeBuffer(length: MetalMobileNetV2NativeStem.activationCount * MemoryLayout<Float>.stride, options: .storageModeShared) else { throw MetalMobileNetV2NativeStem.Error.activationBufferUnavailable }
        return buffer
    }

    /// One fair B submission: conversion and learned RGB stem are ordered encoders
    /// in a single command buffer, matching C's single native-stem submission.
    public func execute(_ input: NV12Textures, normalizedRGB: MTLTexture, into activation: MTLBuffer) throws {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { throw MetalMobileNetV2NativeStem.Error.commandBufferUnavailable }
        guard let conversion = commandBuffer.makeComputeCommandEncoder() else { throw MetalMobileNetV2NativeStem.Error.encoderUnavailable }
        try encodeNV12Conversion(input, into: normalizedRGB, using: conversion); conversion.endEncoding()
        guard let stem = commandBuffer.makeComputeCommandEncoder() else { throw MetalMobileNetV2NativeStem.Error.encoderUnavailable }
        try encodeRGBStem(normalizedRGB, into: activation, using: stem); stem.endEncoding()
        commandBuffer.commit(); commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else { throw MetalMobileNetV2NativeStem.Error.executionFailed }
    }

    public func encodeNV12Conversion(_ input: NV12Textures, into normalizedRGB: MTLTexture, using encoder: MTLComputeCommandEncoder) throws {
        try validate(input: input, normalizedRGB: normalizedRGB, activation: nil)
        encoder.setComputePipelineState(conversionPipeline); encoder.setTexture(input.yPlane, index: 0); encoder.setTexture(input.uvPlane, index: 1); encoder.setTexture(normalizedRGB, index: 2)
        encoder.dispatchThreads(MTLSize(width: 224, height: 224, depth: 1), threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
    }

    public func encodeRGBStem(_ normalizedRGB: MTLTexture, into activation: MTLBuffer, using encoder: MTLComputeCommandEncoder) throws {
        try validate(input: nil, normalizedRGB: normalizedRGB, activation: activation)
        encoder.setComputePipelineState(stemPipeline); encoder.setTexture(normalizedRGB, index: 0); encoder.setBuffer(activation, offset: 0, index: 0); encoder.setBuffer(weights, offset: 0, index: 1); encoder.setBuffer(bias, offset: 0, index: 2)
        encoder.dispatchThreads(MTLSize(width: 112, height: 112, depth: 48), threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
    }

    public func readActivation(from buffer: MTLBuffer) throws -> [Float] {
        guard buffer.length >= MetalMobileNetV2NativeStem.activationCount * MemoryLayout<Float>.stride else { throw MetalMobileNetV2NativeStem.Error.invalidOutput }
        return Array(UnsafeBufferPointer(start: buffer.contents().assumingMemoryBound(to: Float.self), count: MetalMobileNetV2NativeStem.activationCount))
    }

    /// Reads the exact Float32 RGB values produced by Pipeline B's conversion,
    /// reordered to the CHW input expected by the independent Core ML reference.
    /// This avoids introducing a second CPU YUV conversion into the parity proof.
    public func readNormalizedRGB(from texture: MTLTexture) throws -> [Float] {
        try validate(input: nil, normalizedRGB: texture, activation: nil)
        let width = texture.width
        let height = texture.height
        var rgba = [Float](repeating: 0, count: width * height * 4)
        rgba.withUnsafeMutableBytes { bytes in
            texture.getBytes(bytes.baseAddress!, bytesPerRow: width * 4 * MemoryLayout<Float>.stride,
                              from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        }
        var chw = [Float](repeating: 0, count: width * height * 3)
        let pixels = width * height
        for y in 0..<height { for x in 0..<width {
            let pixel = (y * width + x) * 4
            let planar = y * width + x
            chw[planar] = rgba[pixel]
            chw[pixels + planar] = rgba[pixel + 1]
            chw[2 * pixels + planar] = rgba[pixel + 2]
        }}
        return chw
    }

    private func validate(input: NV12Textures?, normalizedRGB: MTLTexture, activation: MTLBuffer?) throws {
        if let input, (input.width != 224 || input.height != 224 || input.yPlane.pixelFormat != .r8Uint || input.uvPlane.pixelFormat != .rg8Uint) { throw MetalMobileNetV2NativeStem.Error.invalidInput }
        guard normalizedRGB.pixelFormat == .rgba32Float, normalizedRGB.width == 224, normalizedRGB.height == 224 else { throw MetalMobileNetV2NativeStem.Error.invalidOutput }
        if let activation, activation.length < MetalMobileNetV2NativeStem.activationCount * MemoryLayout<Float>.stride { throw MetalMobileNetV2NativeStem.Error.invalidOutput }
    }

    private static func foldBatchNorm(_ c: MobileNetV2StemCoefficients) -> (weights: [Double], bias: [Double]) {
        var weights = c.convolutionWeights; var bias = [Double](repeating: 0, count: 48)
        for output in 0..<48 {
            let scale = c.batchNormScale[output] / sqrt(c.batchNormVariance[output] + c.batchNormEpsilon)
            bias[output] = c.batchNormBias[output] - scale * c.batchNormMean[output]
            for rgb in 0..<3 { for tap in 0..<9 { weights[(output * 3 + rgb) * 9 + tap] *= scale } }
        }
        return (weights, bias)
    }

    private static func makeBuffer(device: MTLDevice, values: [Double]) -> MTLBuffer? {
        let floats = values.map(Float.init)
        return floats.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }
    }
}
