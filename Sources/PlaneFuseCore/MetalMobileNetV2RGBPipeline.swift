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
    private let chwConversionPipeline: MTLComputePipelineState
    private let chwStemPipeline: MTLComputePipelineState
    private let weights: MTLBuffer
    private let bias: MTLBuffer
    private let colorParameters: [Float]

    public struct ExecutionTiming: Codable, Equatable {
        public let encodeMilliseconds: Double
        public let gpuWaitMilliseconds: Double
        public let gpuExecutionMilliseconds: Double?
        public let totalMilliseconds: Double
    }

    public init(
        device: MTLDevice? = MTLCreateSystemDefaultDevice(),
        coefficients: MobileNetV2StemCoefficients,
        semantics: NV12Semantics = .bt601VideoRange
    ) throws {
        guard let device else { throw MetalMobileNetV2NativeStem.Error.noDevice }
        guard let queue = device.makeCommandQueue() else { throw MetalMobileNetV2NativeStem.Error.commandQueueUnavailable }
        guard let url = Bundle.module.url(forResource: "NV12MobileNetV2RGB", withExtension: "metal"),
              let source = try? String(contentsOf: url) else { throw MetalMobileNetV2NativeStem.Error.shaderMissing }
        let library = try device.makeLibrary(source: source, options: nil)
        guard let conversion = library.makeFunction(name: "nv12ToMobileNetV2NormalizedRGBA"),
              let stem = library.makeFunction(name: "mobileNetV2RGBStem"),
              let chwConversion = library.makeFunction(name: "nv12ToMobileNetV2NormalizedRGBCHW"),
              let chwStem = library.makeFunction(name: "mobileNetV2RGBCHWStem") else { throw MetalMobileNetV2NativeStem.Error.functionMissing }
        let folded = Self.foldBatchNorm(coefficients)
        guard let weights = Self.makeBuffer(device: device, values: folded.weights),
              let bias = Self.makeBuffer(device: device, values: folded.bias) else { throw MetalMobileNetV2NativeStem.Error.coefficientBufferUnavailable }
        self.device = device; self.commandQueue = queue
        self.conversionPipeline = try device.makeComputePipelineState(function: conversion)
        self.stemPipeline = try device.makeComputePipelineState(function: stem)
        self.chwConversionPipeline = try device.makeComputePipelineState(function: chwConversion)
        self.chwStemPipeline = try device.makeComputePipelineState(function: chwStem)
        self.weights = weights; self.bias = bias
        self.colorParameters = semantics.metalColorParameters
    }

    public func makeNormalizedRGBTexture(pixelFormat: MTLPixelFormat = .rgba32Float) throws -> MTLTexture {
        guard pixelFormat == .rgba32Float || pixelFormat == .rgba16Float else { throw MetalMobileNetV2NativeStem.Error.invalidOutput }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: pixelFormat, width: 224, height: 224, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]; descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else { throw MetalMobileNetV2NativeStem.Error.invalidOutput }
        return texture
    }

    public func makeActivationBuffer() throws -> MTLBuffer {
        guard let buffer = device.makeBuffer(length: MetalMobileNetV2NativeStem.activationCount * MemoryLayout<Float>.stride, options: .storageModeShared) else { throw MetalMobileNetV2NativeStem.Error.activationBufferUnavailable }
        return buffer
    }

    public func makeNormalizedRGBCHWBuffer() throws -> MTLBuffer {
        guard let buffer = device.makeBuffer(length: 224 * 224 * 3 * MemoryLayout<Float>.stride, options: .storageModeShared) else {
            throw MetalMobileNetV2NativeStem.Error.invalidOutput
        }
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

    /// Conventional B2 path: materialized normalized RGB in planar Float32,
    /// avoiding the unused alpha channel while retaining the same tail.
    public func executeCHW(_ input: NV12Textures, normalizedRGB: MTLBuffer, into activation: MTLBuffer) throws {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { throw MetalMobileNetV2NativeStem.Error.commandBufferUnavailable }
        guard let conversion = commandBuffer.makeComputeCommandEncoder() else { throw MetalMobileNetV2NativeStem.Error.encoderUnavailable }
        try encodeCHWConversion(input, into: normalizedRGB, using: conversion); conversion.endEncoding()
        guard let stem = commandBuffer.makeComputeCommandEncoder() else { throw MetalMobileNetV2NativeStem.Error.encoderUnavailable }
        try encodeCHWStem(normalizedRGB, into: activation, using: stem); stem.endEncoding()
        commandBuffer.commit(); commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else { throw MetalMobileNetV2NativeStem.Error.executionFailed }
    }

    /// Exact B2 shared-path submission with timing metadata for the separate
    /// profiler evidence path. The encoded work is identical to `executeCHW`.
    public func executeCHWTimed(_ input: NV12Textures, normalizedRGB: MTLBuffer, into activation: MTLBuffer) throws -> ExecutionTiming {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { throw MetalMobileNetV2NativeStem.Error.commandBufferUnavailable }
        commandBuffer.label = "planefuse.b2.shared"
        let start = ProcessInfo.processInfo.systemUptime
        guard let conversion = commandBuffer.makeComputeCommandEncoder() else { throw MetalMobileNetV2NativeStem.Error.encoderUnavailable }
        conversion.label = "planefuse.b2.rgb"
        try encodeCHWConversion(input, into: normalizedRGB, using: conversion); conversion.endEncoding()
        guard let stem = commandBuffer.makeComputeCommandEncoder() else { throw MetalMobileNetV2NativeStem.Error.encoderUnavailable }
        stem.label = "planefuse.b2.stem"
        try encodeCHWStem(normalizedRGB, into: activation, using: stem); stem.endEncoding()
        let encoded = ProcessInfo.processInfo.systemUptime
        commandBuffer.commit(); commandBuffer.waitUntilCompleted()
        let completed = ProcessInfo.processInfo.systemUptime
        guard commandBuffer.status == .completed else { throw MetalMobileNetV2NativeStem.Error.executionFailed }
        return ExecutionTiming(
            encodeMilliseconds: (encoded - start) * 1_000,
            gpuWaitMilliseconds: (completed - encoded) * 1_000,
            gpuExecutionMilliseconds: commandBuffer.gpuEndTime > commandBuffer.gpuStartTime ? (commandBuffer.gpuEndTime - commandBuffer.gpuStartTime) * 1_000 : nil,
            totalMilliseconds: (completed - start) * 1_000
        )
    }

    public func encodeCHWConversion(_ input: NV12Textures, into normalizedRGB: MTLBuffer, using encoder: MTLComputeCommandEncoder) throws {
        guard input.width == 224, input.height == 224, normalizedRGB.length >= 224 * 224 * 3 * MemoryLayout<Float>.stride else { throw MetalMobileNetV2NativeStem.Error.invalidOutput }
        encoder.setComputePipelineState(chwConversionPipeline); encoder.setTexture(input.yPlane, index: 0); encoder.setTexture(input.uvPlane, index: 1); encoder.setBuffer(normalizedRGB, offset: 0, index: 0)
        colorParameters.withUnsafeBytes { bytes in
            encoder.setBytes(bytes.baseAddress!, length: bytes.count, index: 1)
        }
        encoder.dispatchThreads(MTLSize(width: 224, height: 224, depth: 1), threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
    }

    public func encodeCHWStem(_ normalizedRGB: MTLBuffer, into activation: MTLBuffer, using encoder: MTLComputeCommandEncoder) throws {
        guard normalizedRGB.length >= 224 * 224 * 3 * MemoryLayout<Float>.stride, activation.length >= MetalMobileNetV2NativeStem.activationCount * MemoryLayout<Float>.stride else { throw MetalMobileNetV2NativeStem.Error.invalidOutput }
        encoder.setComputePipelineState(chwStemPipeline); encoder.setBuffer(normalizedRGB, offset: 0, index: 0); encoder.setBuffer(activation, offset: 0, index: 1); encoder.setBuffer(weights, offset: 0, index: 2); encoder.setBuffer(bias, offset: 0, index: 3)
        encoder.dispatchThreads(MTLSize(width: 112, height: 112, depth: 48), threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
    }

    public func readNormalizedRGB(from buffer: MTLBuffer) throws -> [Float] {
        guard buffer.length >= 224 * 224 * 3 * MemoryLayout<Float>.stride else { throw MetalMobileNetV2NativeStem.Error.invalidOutput }
        return Array(UnsafeBufferPointer(start: buffer.contents().assumingMemoryBound(to: Float.self), count: 224 * 224 * 3))
    }

    /// Isolated conversion timing for the R1 component profile. The production
    /// B path remains the one-submission `execute` method above.
    public func executeConversion(_ input: NV12Textures, into normalizedRGB: MTLTexture) throws -> ExecutionTiming {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { throw MetalMobileNetV2NativeStem.Error.commandBufferUnavailable }
        let start = ProcessInfo.processInfo.systemUptime
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { throw MetalMobileNetV2NativeStem.Error.encoderUnavailable }
        try encodeNV12Conversion(input, into: normalizedRGB, using: encoder)
        encoder.endEncoding()
        let encoded = ProcessInfo.processInfo.systemUptime
        commandBuffer.commit()
        let committed = ProcessInfo.processInfo.systemUptime
        commandBuffer.waitUntilCompleted()
        let completed = ProcessInfo.processInfo.systemUptime
        guard commandBuffer.status == .completed else { throw MetalMobileNetV2NativeStem.Error.executionFailed }
        return ExecutionTiming(
            encodeMilliseconds: (encoded - start) * 1_000,
            gpuWaitMilliseconds: (completed - committed) * 1_000,
            gpuExecutionMilliseconds: commandBuffer.gpuEndTime > commandBuffer.gpuStartTime ? (commandBuffer.gpuEndTime - commandBuffer.gpuStartTime) * 1_000 : nil,
            totalMilliseconds: (completed - start) * 1_000
        )
    }

    /// Isolated conventional RGB stem timing for the R1 component profile.
    public func executeRGBStem(_ normalizedRGB: MTLTexture, into activation: MTLBuffer) throws -> ExecutionTiming {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { throw MetalMobileNetV2NativeStem.Error.commandBufferUnavailable }
        let start = ProcessInfo.processInfo.systemUptime
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { throw MetalMobileNetV2NativeStem.Error.encoderUnavailable }
        try encodeRGBStem(normalizedRGB, into: activation, using: encoder)
        encoder.endEncoding()
        let encoded = ProcessInfo.processInfo.systemUptime
        commandBuffer.commit()
        let committed = ProcessInfo.processInfo.systemUptime
        commandBuffer.waitUntilCompleted()
        let completed = ProcessInfo.processInfo.systemUptime
        guard commandBuffer.status == .completed else { throw MetalMobileNetV2NativeStem.Error.executionFailed }
        return ExecutionTiming(
            encodeMilliseconds: (encoded - start) * 1_000,
            gpuWaitMilliseconds: (completed - committed) * 1_000,
            gpuExecutionMilliseconds: commandBuffer.gpuEndTime > commandBuffer.gpuStartTime ? (commandBuffer.gpuEndTime - commandBuffer.gpuStartTime) * 1_000 : nil,
            totalMilliseconds: (completed - start) * 1_000
        )
    }

    public func encodeNV12Conversion(_ input: NV12Textures, into normalizedRGB: MTLTexture, using encoder: MTLComputeCommandEncoder) throws {
        try validate(input: input, normalizedRGB: normalizedRGB, activation: nil)
        encoder.setComputePipelineState(conversionPipeline); encoder.setTexture(input.yPlane, index: 0); encoder.setTexture(input.uvPlane, index: 1); encoder.setTexture(normalizedRGB, index: 2)
        colorParameters.withUnsafeBytes { bytes in
            encoder.setBytes(bytes.baseAddress!, length: bytes.count, index: 0)
        }
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
        if texture.pixelFormat == .rgba32Float {
            rgba.withUnsafeMutableBytes { bytes in
                texture.getBytes(bytes.baseAddress!, bytesPerRow: width * 4 * MemoryLayout<Float>.stride,
                                  from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
            }
        } else if texture.pixelFormat == .rgba16Float {
            var half = [Float16](repeating: 0, count: width * height * 4)
            half.withUnsafeMutableBytes { bytes in
                texture.getBytes(bytes.baseAddress!, bytesPerRow: width * 4 * MemoryLayout<Float16>.stride,
                                  from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
            }
            rgba = half.map(Float.init)
        } else {
            throw MetalMobileNetV2NativeStem.Error.invalidOutput
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
        guard (normalizedRGB.pixelFormat == .rgba32Float || normalizedRGB.pixelFormat == .rgba16Float), normalizedRGB.width == 224, normalizedRGB.height == 224 else { throw MetalMobileNetV2NativeStem.Error.invalidOutput }
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
