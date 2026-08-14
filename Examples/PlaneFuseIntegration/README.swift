import Foundation
import Metal
import PlaneFuseCore

final class MobileNetV2CameraAdapter {
    private let runtime: PlaneFuseMobileNetV2Runtime

    init(device: MTLDevice, root: URL) throws {
        runtime = try PlaneFuseMobileNetV2Runtime(
            device: device,
            coefficientsURL: root.appendingPathComponent("models/derived/MobileNetV2StemCoefficients.json"),
            tailModelURL: root.appendingPathComponent("models/derived/tail-compiled/MobileNetV2Tail.mlmodelc"),
            semantics: .bt601VideoRange
        )
    }

    func classify(resizedNV12: MetalRGBBaseline.NV12Textures) throws -> String? {
        try runtime.predict(nv12Textures: resizedNV12).topLabel
    }
}
