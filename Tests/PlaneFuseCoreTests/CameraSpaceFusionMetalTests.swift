import Metal
import XCTest
@testable import PlaneFuseCore

final class CameraSpaceFusionMetalTests: XCTestCase {
    func testDirectCameraSpaceBAndCMatchAcceptedTwoStagePath() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("Metal is unavailable.") }
        let coefficients = makeCoefficients()
        let sourceFactory = try MetalRGBBaseline(device: device)
        let conventional = try MetalMobileNetV2RGBPipeline(device: device, coefficients: coefficients)
        let twoStageNative = try MetalMobileNetV2NativeStem(device: device, coefficients: coefficients)
        let directB = try MetalMobileNetV2CameraSpaceRGBPreprocessor(device: device)
        let directC = try MetalMobileNetV2CameraSpaceStem(device: device, coefficients: coefficients)

        // Identity and a center crop exercise the two accepted camera geometries.
        for dimensions in [(width: 224, height: 224), (width: 640, height: 480)] {
            let mapping = try CameraSpaceMapping(sourceWidth: dimensions.width, sourceHeight: dimensions.height)
            let sourceBytes = makeSourceBytes(width: dimensions.width, height: dimensions.height)
            let source = try makeUnormSourceTextures(
                device: device, width: dimensions.width, height: dimensions.height,
                y: sourceBytes.y, uv: sourceBytes.uv
            )
            let staged = try makeAcceptedResizedInput(
                factory: sourceFactory, sourceWidth: dimensions.width,
                y: sourceBytes.y, uv: sourceBytes.uv, mapping: mapping
            )

            let expectedRGB = try conventional.makeNormalizedRGBCHWBuffer()
            try encodeAcceptedCHWConversion(conventional, input: staged, into: expectedRGB)
            let directRGB = try directB.makeNormalizedRGBCHWBuffer()
            try directB.execute(source, mapping: mapping, into: directRGB)
            let rgbError = maxAbsoluteError(
                try conventional.readNormalizedRGB(from: expectedRGB),
                try directB.readNormalizedRGB(from: directRGB)
            )
            XCTAssertLessThanOrEqual(rgbError, 1e-6, "direct B RGB parity for \(dimensions.width)x\(dimensions.height)")

            let expectedActivation = try twoStageNative.makeActivationBuffer()
            try twoStageNative.execute(staged, into: expectedActivation)
            let directActivation = try directC.makeActivationBuffer()
            try directC.execute(source, mapping: mapping, into: directActivation)
            let activationError = maxAbsoluteError(
                try twoStageNative.readActivation(from: expectedActivation),
                try directC.readActivation(from: directActivation)
            )
            XCTAssertLessThanOrEqual(
                activationError, FairABCBenchmark.featureParityTolerance,
                "direct C activation parity for \(dimensions.width)x\(dimensions.height)"
            )

            // B's direct conversion and unchanged CHW stem compose in a single
            // caller-owned submission with no wait between encoders.
            let composedRGB = try directB.makeNormalizedRGBCHWBuffer()
            let composedActivation = try conventional.makeActivationBuffer()
            guard let commandBuffer = directB.commandQueue.makeCommandBuffer(),
                  let conversionEncoder = commandBuffer.makeComputeCommandEncoder() else {
                XCTFail("Unable to create direct B command encoders")
                return
            }
            try directB.encode(source, mapping: mapping, into: composedRGB, using: conversionEncoder)
            conversionEncoder.endEncoding()
            guard let stemEncoder = commandBuffer.makeComputeCommandEncoder() else {
                XCTFail("Unable to create direct B stem encoder")
                return
            }
            try conventional.encodeCHWStem(composedRGB, into: composedActivation, using: stemEncoder)
            stemEncoder.endEncoding()
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            XCTAssertEqual(commandBuffer.status, .completed)
            let composedError = maxAbsoluteError(
                try conventional.readActivation(from: composedActivation),
                try twoStageNative.readActivation(from: expectedActivation)
            )
            XCTAssertLessThanOrEqual(composedError, FairABCBenchmark.featureParityTolerance)
        }
    }

    private func makeCoefficients() -> MobileNetV2StemCoefficients {
        let weights: [Double] = (0..<(48 * 27)).map { index in
            let numerator = (index * 17) % 23 - 11
            return Double(numerator) / 131.0
        }
        let scale: [Double] = (0..<48).map { 0.65 + Double($0 % 7) * 0.08 }
        let bias: [Double] = (0..<48).map { Double(($0 % 9) - 4) / 8.0 }
        let mean: [Double] = (0..<48).map { Double(($0 % 5) - 2) / 17.0 }
        let variance: [Double] = (0..<48).map { 0.7 + Double($0 % 4) / 9.0 }
        return MobileNetV2StemCoefficients(
            convolutionWeights: weights, batchNormScale: scale, batchNormBias: bias,
            batchNormMean: mean, batchNormVariance: variance, batchNormEpsilon: 0
        )
    }

    private func makeSourceBytes(width: Int, height: Int) -> (y: [UInt8], uv: [UInt8]) {
        var y = [UInt8](repeating: 0, count: width * height)
        for row in 0..<height {
            for column in 0..<width {
                let index = row * width + column
                y[index] = (column == 0 || row == 0) ? 0 : (column == width - 1 || row == height - 1) ? 255 : UInt8((index * 37 + 19) & 255)
            }
        }
        var uv = [UInt8](repeating: 0, count: width * height / 2)
        let uvWidth = width / 2
        let uvHeight = height / 2
        for row in 0..<uvHeight {
            for column in 0..<uvWidth {
                let index = (row * uvWidth + column) * 2
                uv[index] = (column == 0 || row == uvHeight - 1) ? 0 : UInt8((index * 11 + 7) & 255)
                uv[index + 1] = (row == 0 || column == uvWidth - 1) ? 255 : UInt8((index * 29 + 3) & 255)
            }
        }
        return (y, uv)
    }

    private func makeUnormSourceTextures(
        device: MTLDevice, width: Int, height: Int, y: [UInt8], uv: [UInt8]
    ) throws -> MetalCameraNV12SourceTextures {
        let yDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm, width: width, height: height, mipmapped: false)
        yDescriptor.usage = [.shaderRead]
        yDescriptor.storageMode = .shared
        let uvDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rg8Unorm, width: width / 2, height: height / 2, mipmapped: false)
        uvDescriptor.usage = [.shaderRead]
        uvDescriptor.storageMode = .shared
        guard let yPlane = device.makeTexture(descriptor: yDescriptor),
              let uvPlane = device.makeTexture(descriptor: uvDescriptor) else {
            throw MetalRGBBaseline.Error.textureCreationFailed
        }
        y.withUnsafeBytes {
            yPlane.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: width)
        }
        uv.withUnsafeBytes {
            uvPlane.replace(region: MTLRegionMake2D(0, 0, width / 2, height / 2), mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: width)
        }
        return try MetalCameraNV12SourceTextures(yPlane: yPlane, uvPlane: uvPlane)
    }

    private func makeAcceptedResizedInput(
        factory: MetalRGBBaseline, sourceWidth: Int,
        y: [UInt8], uv: [UInt8], mapping: CameraSpaceMapping
    ) throws -> MetalRGBBaseline.NV12Textures {
        var resizedY = [UInt8](repeating: 0, count: 224 * 224)
        var resizedUV = [UInt8](repeating: 0, count: 224 * 224 / 2)
        for outputY in 0..<224 {
            for outputX in 0..<224 {
                let coordinate = try mapping.lumaSourceCoordinate(resized: .init(x: outputX, y: outputY))
                resizedY[outputY * 224 + outputX] = y[coordinate.y * sourceWidth + coordinate.x]
            }
        }
        for outputY in 0..<112 {
            for outputX in 0..<112 {
                let coordinate = try mapping.uvSourceCoordinate(resized: .init(x: outputX, y: outputY))
                let sourceOffset = (coordinate.y * (sourceWidth / 2) + coordinate.x) * 2
                let outputOffset = (outputY * 112 + outputX) * 2
                resizedUV[outputOffset] = uv[sourceOffset]
                resizedUV[outputOffset + 1] = uv[sourceOffset + 1]
            }
        }
        return try factory.makeNV12Textures(width: 224, height: 224, yPlaneBytes: resizedY, uvPlaneBytes: resizedUV)
    }

    private func encodeAcceptedCHWConversion(
        _ pipeline: MetalMobileNetV2RGBPipeline,
        input: MetalRGBBaseline.NV12Textures,
        into output: MTLBuffer
    ) throws {
        guard let commandBuffer = pipeline.commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw MetalMobileNetV2CameraSpaceRGBPreprocessor.Error.commandBufferUnavailable
        }
        try pipeline.encodeCHWConversion(input, into: output, using: encoder)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        XCTAssertEqual(commandBuffer.status, .completed)
    }

    private func maxAbsoluteError(_ lhs: [Float], _ rhs: [Float]) -> Float {
        zip(lhs, rhs).reduce(0) { max($0, abs($1.0 - $1.1)) }
    }
}
