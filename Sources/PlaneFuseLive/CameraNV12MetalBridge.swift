import CoreVideo
import Foundation
import Metal

private struct CameraResizeParameters {
    var cropOriginX: UInt32
    var cropOriginY: UInt32
    var cropSide: UInt32
}

struct CameraResizeGeometry {
    let cameraWidth: Int
    let cameraHeight: Int
    let cropOriginX: Int
    let cropOriginY: Int
    let cropSide: Int

    static func make(width: Int, height: Int) throws -> Self {
        guard width > 0, height > 0, width.isMultiple(of: 2), height.isMultiple(of: 2) else {
            throw LiveError.unsupportedCameraFrame
        }
        let cropSide = min(width, height) & ~1
        guard cropSide >= 2 else { throw LiveError.unsupportedCameraFrame }
        return Self(
            cameraWidth: width, cameraHeight: height,
            cropOriginX: ((width - cropSide) / 2) & ~1,
            cropOriginY: ((height - cropSide) / 2) & ~1,
            cropSide: cropSide
        )
    }
}

final class CameraNV12MetalBridge {
    struct OutputTextures {
        let yPlane: MTLTexture
        let uvPlane: MTLTexture
        let geometry: CameraResizeGeometry
    }

    struct Execution {
        let geometry: CameraResizeGeometry
        let gpuMilliseconds: Double?
    }

    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    private let textureCache: CVMetalTextureCache
    private let yPipeline: MTLComputePipelineState
    private let uvPipeline: MTLComputePipelineState

    init(device: MTLDevice) throws {
        self.device = device
        guard let commandQueue = device.makeCommandQueue() else { throw LiveError.cameraOutputUnavailable }
        var cache: CVMetalTextureCache?
        guard CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache) == kCVReturnSuccess,
              let cache else { throw LiveError.cameraOutputUnavailable }
        guard let sourceURL = Bundle.module.url(forResource: "CameraNV12Resize", withExtension: "metal"),
              let source = try? String(contentsOf: sourceURL, encoding: .utf8) else {
            throw LiveError.cameraOutputUnavailable
        }
        let library = try device.makeLibrary(source: source, options: nil)
        guard let yFunction = library.makeFunction(name: "cameraResizeY"),
              let uvFunction = library.makeFunction(name: "cameraResizeUV") else {
            throw LiveError.cameraOutputUnavailable
        }
        self.commandQueue = commandQueue
        self.textureCache = cache
        self.yPipeline = try device.makeComputePipelineState(function: yFunction)
        self.uvPipeline = try device.makeComputePipelineState(function: uvFunction)
    }

    func makeOutputRing(count: Int, geometry: CameraResizeGeometry) throws -> [OutputTextures] {
        guard count > 0 else { throw LiveError.cameraOutputUnavailable }
        return try (0..<count).map { _ in
            let yDescriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .r8Uint, width: 224, height: 224, mipmapped: false
            )
            yDescriptor.usage = [.shaderRead, .shaderWrite]
            yDescriptor.storageMode = .shared
            let uvDescriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rg8Uint, width: 112, height: 112, mipmapped: false
            )
            uvDescriptor.usage = [.shaderRead, .shaderWrite]
            uvDescriptor.storageMode = .shared
            guard let yPlane = device.makeTexture(descriptor: yDescriptor),
                  let uvPlane = device.makeTexture(descriptor: uvDescriptor) else {
                throw LiveError.cameraOutputUnavailable
            }
            return OutputTextures(yPlane: yPlane, uvPlane: uvPlane, geometry: geometry)
        }
    }

    func execute(pixelBuffer: CVPixelBuffer, into output: OutputTextures) throws -> Execution {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
              CVPixelBufferGetPlaneCount(pixelBuffer) == 2,
              width == output.geometry.cameraWidth, height == output.geometry.cameraHeight,
              CVPixelBufferGetWidthOfPlane(pixelBuffer, 0) == width,
              CVPixelBufferGetHeightOfPlane(pixelBuffer, 0) == height,
              CVPixelBufferGetWidthOfPlane(pixelBuffer, 1) == width / 2,
              CVPixelBufferGetHeightOfPlane(pixelBuffer, 1) == height / 2 else {
            throw LiveError.unsupportedCameraFrame
        }
        var yWrapper: CVMetalTexture?
        var uvWrapper: CVMetalTexture?
        guard CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, textureCache, pixelBuffer, nil, .r8Unorm,
            width, height, 0, &yWrapper
        ) == kCVReturnSuccess,
        CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, textureCache, pixelBuffer, nil, .rg8Unorm,
            width / 2, height / 2, 1, &uvWrapper
        ) == kCVReturnSuccess,
        let yTexture = yWrapper.flatMap(CVMetalTextureGetTexture),
        let uvTexture = uvWrapper.flatMap(CVMetalTextureGetTexture),
        let commandBuffer = commandQueue.makeCommandBuffer(),
        let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw LiveError.cameraOutputUnavailable
        }

        var parameters = CameraResizeParameters(
            cropOriginX: UInt32(output.geometry.cropOriginX),
            cropOriginY: UInt32(output.geometry.cropOriginY),
            cropSide: UInt32(output.geometry.cropSide)
        )
        encoder.setComputePipelineState(yPipeline)
        encoder.setTexture(yTexture, index: 0)
        encoder.setTexture(output.yPlane, index: 1)
        encoder.setBytes(&parameters, length: MemoryLayout<CameraResizeParameters>.stride, index: 0)
        encoder.dispatchThreads(
            MTLSize(width: 224, height: 224, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1)
        )
        encoder.setComputePipelineState(uvPipeline)
        encoder.setTexture(uvTexture, index: 0)
        encoder.setTexture(output.uvPlane, index: 1)
        encoder.setBytes(&parameters, length: MemoryLayout<CameraResizeParameters>.stride, index: 0)
        encoder.dispatchThreads(
            MTLSize(width: 112, height: 112, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1)
        )
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else { throw LiveError.cameraOutputUnavailable }
        return Execution(
            geometry: output.geometry,
            gpuMilliseconds: commandBuffer.gpuEndTime > commandBuffer.gpuStartTime
                ? (commandBuffer.gpuEndTime - commandBuffer.gpuStartTime) * 1_000 : nil
        )
    }

    func readPlanes(from output: OutputTextures) throws -> (y: Data, uv: Data) {
        var y = Data(count: output.yPlane.width * output.yPlane.height)
        var uv = Data(count: output.uvPlane.width * output.uvPlane.height * 2)
        y.withUnsafeMutableBytes { bytes in
            output.yPlane.getBytes(
                bytes.baseAddress!,
                bytesPerRow: output.yPlane.width,
                from: MTLRegionMake2D(0, 0, output.yPlane.width, output.yPlane.height),
                mipmapLevel: 0
            )
        }
        uv.withUnsafeMutableBytes { bytes in
            output.uvPlane.getBytes(
                bytes.baseAddress!,
                bytesPerRow: output.uvPlane.width * 2,
                from: MTLRegionMake2D(0, 0, output.uvPlane.width, output.uvPlane.height),
                mipmapLevel: 0
            )
        }
        return (y, uv)
    }
}
