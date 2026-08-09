import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import PlaneFuseCore

private enum LiveError: Error, LocalizedError {
    case usage
    case cameraUnavailable
    case cameraPermissionDenied
    case cameraInputUnavailable
    case cameraOutputUnavailable
    case cameraTimedOut
    case cameraFrameUnavailable
    case unsupportedCameraFrame
    case cameraPlaneLockFailed
    case inferenceOutputUnavailable

    var errorDescription: String? {
        switch self {
        case .usage:
            return "usage: planefuse-live <--help|--sample|--camera>"
        case .cameraUnavailable:
            return "No local camera is available."
        case .cameraPermissionDenied:
            return "Camera access was denied or is restricted."
        case .cameraInputUnavailable:
            return "The camera could not be added to the capture session."
        case .cameraOutputUnavailable:
            return "The NV12 camera output could not be added to the capture session."
        case .cameraTimedOut:
            return "The camera did not deliver a frame before the timeout."
        case .cameraFrameUnavailable:
            return "The camera delivered no usable pixel buffer."
        case .unsupportedCameraFrame:
            return "The camera frame is not a two-plane, even-dimension NV12 video-range buffer."
        case .cameraPlaneLockFailed:
            return "The captured camera frame's native planes could not be locked for reading."
        case .inferenceOutputUnavailable:
            return "The MobileNetV2 tail returned no top-1 label."
        }
    }
}

private struct MobileNetV2AssetPaths {
    let coefficient: String
    let tail: String
    let stemArray: String
    let fullArray: String

    init(environment: [String: String]) {
        coefficient = environment["PF_MOBILENET_COEFFICIENTS"] ?? "models/derived/MobileNetV2StemCoefficients.json"
        tail = environment["PF_MOBILENET_TAIL"] ?? "models/derived/tail-compiled/MobileNetV2Tail.mlmodelc"
        stemArray = environment["PF_MOBILENET_STEM_ARRAY"] ?? "models/derived/stem-array-compiled/MobileNetV2Stem.mlmodelc"
        fullArray = environment["PF_MOBILENET_FULL_ARRAY"] ?? "models/derived/full-array-compiled/MobileNetV2FullArray.mlmodelc"
    }
}

private final class CameraFrameDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let semaphore = DispatchSemaphore(value: 0)
    private(set) var pixelBuffer: CVPixelBuffer?
    private(set) var width = 0
    private(set) var height = 0
    private(set) var pixelFormat = 0
    private(set) var timestamp: CMTime = .invalid

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard pixelBuffer == nil, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        self.pixelBuffer = pixelBuffer
        width = CVPixelBufferGetWidth(pixelBuffer)
        height = CVPixelBufferGetHeight(pixelBuffer)
        pixelFormat = Int(CVPixelBufferGetPixelFormatType(pixelBuffer))
        timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        semaphore.signal()
    }

    func waitForFrame(timeout: TimeInterval) -> Bool {
        semaphore.wait(timeout: .now() + timeout) == .success
    }
}

private struct CameraNV12Resize {
    static let outputWidth = 224
    static let outputHeight = 224

    let cameraWidth: Int
    let cameraHeight: Int
    let pixelFormat: Int
    let cropOriginX: Int
    let cropOriginY: Int
    let cropSide: Int
    let yPlaneBytes: [UInt8]
    let uvPlaneBytes: [UInt8]
}

private struct CameraInferenceMeasurement {
    let bFrontendMilliseconds: Double
    let cFrontendMilliseconds: Double
    let bEndToEndMilliseconds: Double
    let cEndToEndMilliseconds: Double
    let maxActivationAbsoluteDifference: Double
    let top1Agreement: Double
    let bTop1Label: String
    let cTop1Label: String
    let bTop1Confidence: Double
    let cTop1Confidence: Double
}

private func printHelp() {
    print("""
    planefuse-live — honest local camera proof for PlaneFuse

    Usage:
      planefuse-live --sample   Run the local M5 MobileNetV2 B/C workload on the real corpus.
      planefuse-live --camera   Capture, native-plane resize, and infer on one camera NV12 frame.
      planefuse-live --help     Show this help.

    --camera crops the captured NV12 frame to an even-aligned center square, then uses
    nearest source-grid sampling directly on Y and interleaved UV planes to make 224x224
    NV12. It does not use an RGB intermediate during resize.
    """)
}

private func runSample() throws {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    let manifest = MobileNetV2AssetManifest.inspected
    let paths = MobileNetV2AssetPaths(environment: ProcessInfo.processInfo.environment)
    try manifest.validate(at: root)
    let lineage = try MobileNetV2DerivedArtifactManifest.load(from: root.appendingPathComponent(manifest.derivedManifest))
    try lineage.validate(at: root)
    let corpus = try MobileNetV2Corpus(
        manifestURL: root.appendingPathComponent(manifest.validationCorpusManifest), root: root
    )
    let tail = try CoreMLMobileNetV2TailAdapter(
        modelURL: URL(fileURLWithPath: paths.tail), manifest: manifest
    )
    let independentReference = try MobileNetV2Benchmark.IndependentReference(
        stemArray: CoreMLMobileNetV2StemArrayAdapter(
            modelURL: URL(fileURLWithPath: paths.stemArray), lineage: lineage, computeUnits: .cpuOnly
        ),
        fullArray: CoreMLMobileNetV2FullArrayAdapter(
            modelURL: URL(fileURLWithPath: paths.fullArray), lineage: lineage, computeUnits: .cpuOnly
        )
    )
    let benchmark = try MobileNetV2Benchmark(
        configuration: .quick,
        coefficientsURL: URL(fileURLWithPath: paths.coefficient),
        tail: tail,
        corpus: corpus,
        independentReference: independentReference
    )
    let measurement = try benchmark.run()

    print("PlaneFuse Live sample: MobileNetV2 M5 corpus B/C workload")
    print("corpus_frames: \(measurement.validationCorpusSampleIds.joined(separator: ","))")
    print(String(format: "b_frontend_p50_ms: %.4f", measurement.pipelineBFrontend.p50Milliseconds))
    print(String(format: "c_frontend_p50_ms: %.4f", measurement.pipelineCFrontend.p50Milliseconds))
    print(String(format: "b_end_to_end_p50_ms: %.4f", measurement.pipelineBEndToEnd.p50Milliseconds))
    print(String(format: "c_end_to_end_p50_ms: %.4f", measurement.pipelineCEndToEnd.p50Milliseconds))
    print(String(format: "top1_agreement: %.4f", measurement.top1Agreement))
    print(String(format: "activation_max_abs_error: %.8f", measurement.maxActivationAbsoluteDifference))
    print("parity: \(measurement.outputAgreementPass && measurement.independentParityPass ? "PASS" : "FAIL")")
    print("c_rgb_intermediate_bytes: \(measurement.pipelineCRGBIntermediateBytes)")
}

private func runCamera() throws {
    guard AVCaptureDevice.authorizationStatus(for: .video) != .denied,
          AVCaptureDevice.authorizationStatus(for: .video) != .restricted else {
        throw LiveError.cameraPermissionDenied
    }
    if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
        let granted = awaitCameraAccess()
        guard granted else { throw LiveError.cameraPermissionDenied }
    }
    guard let device = AVCaptureDevice.default(for: .video) else { throw LiveError.cameraUnavailable }
    let session = AVCaptureSession()
    let input = try AVCaptureDeviceInput(device: device)
    guard session.canAddInput(input) else { throw LiveError.cameraInputUnavailable }
    session.addInput(input)

    let output = AVCaptureVideoDataOutput()
    output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)]
    output.alwaysDiscardsLateVideoFrames = true
    let delegate = CameraFrameDelegate()
    let queue = DispatchQueue(label: "planefuse-live.camera")
    output.setSampleBufferDelegate(delegate, queue: queue)
    guard session.canAddOutput(output) else { throw LiveError.cameraOutputUnavailable }
    session.addOutput(output)

    session.startRunning()
    defer { session.stopRunning() }
    guard delegate.waitForFrame(timeout: 10) else { throw LiveError.cameraTimedOut }

    guard let pixelBuffer = delegate.pixelBuffer else { throw LiveError.cameraFrameUnavailable }
    let resized = try resizeCameraNV12(pixelBuffer)
    let measurement = try runCameraInference(resized)

    let format = String(format: "0x%08X", resized.pixelFormat)
    print("PlaneFuse Live camera: one actual frame, native-plane B/C MobileNetV2 inference")
    print("camera_dimensions: \(resized.cameraWidth)x\(resized.cameraHeight)")
    print("camera_pixel_format: NV12 video-range (\(format))")
    print("camera_timestamp: \(delegate.timestamp.seconds)")
    print("resize_policy: even-aligned center-square crop origin=(\(resized.cropOriginX),\(resized.cropOriginY)) side=\(resized.cropSide); nearest source-grid resize Y=224x224, UV=112x112 interleaved; output=224x224 NV12; no RGB intermediate during resize")
    print(String(format: "b_frontend_elapsed_ms: %.4f", measurement.bFrontendMilliseconds))
    print(String(format: "c_frontend_elapsed_ms: %.4f", measurement.cFrontendMilliseconds))
    print(String(format: "b_end_to_end_elapsed_ms: %.4f", measurement.bEndToEndMilliseconds))
    print(String(format: "c_end_to_end_elapsed_ms: %.4f", measurement.cEndToEndMilliseconds))
    print(String(format: "bc_activation_max_abs_error: %.8f", measurement.maxActivationAbsoluteDifference))
    print("b_top1_label: \(measurement.bTop1Label)")
    print(String(format: "b_top1_confidence: %.8f", measurement.bTop1Confidence))
    print("c_top1_label: \(measurement.cTop1Label)")
    print(String(format: "c_top1_confidence: %.8f", measurement.cTop1Confidence))
    print(String(format: "top1_agreement: %.4f", measurement.top1Agreement))
    print("c_rgb_intermediate_bytes: 0")
}

/// Resizes the camera's native NV12 planes without reconstructing RGB. The Y grid
/// is sampled at 224x224 and the interleaved UV grid at 112x112, each using
/// `floor(destinationCoordinate * sourceExtent / destinationExtent)`.
private func resizeCameraNV12(_ pixelBuffer: CVPixelBuffer) throws -> CameraNV12Resize {
    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    let pixelFormat = Int(CVPixelBufferGetPixelFormatType(pixelBuffer))
    guard pixelFormat == Int(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange),
          CVPixelBufferGetPlaneCount(pixelBuffer) == 2,
          width.isMultiple(of: 2), height.isMultiple(of: 2) else {
        throw LiveError.unsupportedCameraFrame
    }

    let cropSide = min(width, height) & ~1
    guard cropSide >= 2 else { throw LiveError.unsupportedCameraFrame }
    // NV12 chroma samples represent 2x2 luma blocks, so origins must be even.
    let cropOriginX = ((width - cropSide) / 2) & ~1
    let cropOriginY = ((height - cropSide) / 2) & ~1
    let yWidth = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
    let yHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
    let uvWidth = CVPixelBufferGetWidthOfPlane(pixelBuffer, 1)
    let uvHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer, 1)
    let yBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
    let uvBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)
    guard yWidth == width, yHeight == height,
          uvWidth == width / 2, uvHeight == height / 2,
          yBytesPerRow >= width, uvBytesPerRow >= width else {
        throw LiveError.unsupportedCameraFrame
    }

    guard CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly) == kCVReturnSuccess else {
        throw LiveError.cameraPlaneLockFailed
    }
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
    guard let yBaseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0),
          let uvBaseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1) else {
        throw LiveError.cameraPlaneLockFailed
    }

    let yBase = yBaseAddress.assumingMemoryBound(to: UInt8.self)
    let uvBase = uvBaseAddress.assumingMemoryBound(to: UInt8.self)
    let outputWidth = CameraNV12Resize.outputWidth
    let outputHeight = CameraNV12Resize.outputHeight
    var yPlaneBytes = [UInt8](repeating: 0, count: outputWidth * outputHeight)
    var uvPlaneBytes = [UInt8](repeating: 0, count: outputWidth * outputHeight / 2)

    for destinationY in 0..<outputHeight {
        let sourceY = cropOriginY + destinationY * cropSide / outputHeight
        let sourceRow = yBase.advanced(by: sourceY * yBytesPerRow)
        for destinationX in 0..<outputWidth {
            let sourceX = cropOriginX + destinationX * cropSide / outputWidth
            yPlaneBytes[destinationY * outputWidth + destinationX] = sourceRow[sourceX]
        }
    }

    let sourceUVSide = cropSide / 2
    let outputUVWidth = outputWidth / 2
    let outputUVHeight = outputHeight / 2
    for destinationY in 0..<outputUVHeight {
        let sourceY = cropOriginY / 2 + destinationY * sourceUVSide / outputUVHeight
        let sourceRow = uvBase.advanced(by: sourceY * uvBytesPerRow)
        for destinationX in 0..<outputUVWidth {
            let sourceX = cropOriginX / 2 + destinationX * sourceUVSide / outputUVWidth
            let sourceOffset = sourceX * 2
            let destinationOffset = (destinationY * outputUVWidth + destinationX) * 2
            uvPlaneBytes[destinationOffset] = sourceRow[sourceOffset]
            uvPlaneBytes[destinationOffset + 1] = sourceRow[sourceOffset + 1]
        }
    }

    return CameraNV12Resize(
        cameraWidth: width, cameraHeight: height, pixelFormat: pixelFormat,
        cropOriginX: cropOriginX, cropOriginY: cropOriginY, cropSide: cropSide,
        yPlaneBytes: yPlaneBytes, uvPlaneBytes: uvPlaneBytes
    )
}

/// Runs exactly one input-ready B path and one input-ready C path. Each elapsed
/// end-to-end interval includes that path's same unchanged compiled Core ML tail.
private func runCameraInference(_ frame: CameraNV12Resize) throws -> CameraInferenceMeasurement {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    let manifest = MobileNetV2AssetManifest.inspected
    let paths = MobileNetV2AssetPaths(environment: ProcessInfo.processInfo.environment)
    try manifest.validate(at: root)
    let lineage = try MobileNetV2DerivedArtifactManifest.load(from: root.appendingPathComponent(manifest.derivedManifest))
    try lineage.validate(at: root)

    let tail = try CoreMLMobileNetV2TailAdapter(modelURL: URL(fileURLWithPath: paths.tail), manifest: manifest)
    let coefficients = try MobileNetV2StemCoefficients.load(from: URL(fileURLWithPath: paths.coefficient))
    let factory = try MetalRGBBaseline()
    let baseline = try MetalMobileNetV2RGBPipeline(device: factory.device, coefficients: coefficients)
    let native = try MetalMobileNetV2NativeStem(device: factory.device, coefficients: coefficients)
    let input = try factory.makeNV12Textures(
        width: CameraNV12Resize.outputWidth, height: CameraNV12Resize.outputHeight,
        yPlaneBytes: frame.yPlaneBytes, uvPlaneBytes: frame.uvPlaneBytes
    )
    let normalizedRGB = try baseline.makeNormalizedRGBTexture()
    let bActivation = try baseline.makeActivationBuffer()
    let cActivation = try native.makeActivationBuffer()

    let bStart = ProcessInfo.processInfo.systemUptime
    try baseline.execute(input, normalizedRGB: normalizedRGB, into: bActivation)
    let bFrontendMilliseconds = (ProcessInfo.processInfo.systemUptime - bStart) * 1_000
    let bFeatures = try baseline.readActivation(from: bActivation)
    let bOutput = try tail.predict(stemActivation: bFeatures)
    let bEndToEndMilliseconds = (ProcessInfo.processInfo.systemUptime - bStart) * 1_000

    let cStart = ProcessInfo.processInfo.systemUptime
    try native.execute(input, into: cActivation)
    let cFrontendMilliseconds = (ProcessInfo.processInfo.systemUptime - cStart) * 1_000
    let cFeatures = try native.readActivation(from: cActivation)
    let cOutput = try tail.predict(stemActivation: cFeatures)
    let cEndToEndMilliseconds = (ProcessInfo.processInfo.systemUptime - cStart) * 1_000

    guard let bPrediction = topPrediction(bOutput), let cPrediction = topPrediction(cOutput) else {
        throw LiveError.inferenceOutputUnavailable
    }
    let maxActivationAbsoluteDifference = zip(bFeatures, cFeatures)
        .map { abs(Double($0 - $1)) }
        .max() ?? 0
    return CameraInferenceMeasurement(
        bFrontendMilliseconds: bFrontendMilliseconds, cFrontendMilliseconds: cFrontendMilliseconds,
        bEndToEndMilliseconds: bEndToEndMilliseconds, cEndToEndMilliseconds: cEndToEndMilliseconds,
        maxActivationAbsoluteDifference: maxActivationAbsoluteDifference,
        top1Agreement: bPrediction.label == cPrediction.label ? 1 : 0,
        bTop1Label: bPrediction.label,
        cTop1Label: cPrediction.label,
        bTop1Confidence: bPrediction.confidence,
        cTop1Confidence: cPrediction.confidence
    )
}

private func topPrediction(_ probabilities: [String: Double]) -> (label: String, confidence: Double)? {
    probabilities.max { lhs, rhs in
        lhs.value == rhs.value ? lhs.key > rhs.key : lhs.value < rhs.value
    }.map { (label: $0.key, confidence: $0.value) }
}

private func topLabel(_ probabilities: [String: Double]) -> String? {
    probabilities.max { lhs, rhs in
        lhs.value == rhs.value ? lhs.key > rhs.key : lhs.value < rhs.value
    }?.key
}

private func awaitCameraAccess() -> Bool {
    let semaphore = DispatchSemaphore(value: 0)
    var granted = false
    AVCaptureDevice.requestAccess(for: .video) {
        granted = $0
        semaphore.signal()
    }
    _ = semaphore.wait(timeout: .now() + 30)
    return granted
}

@main
private struct PlaneFuseLive {
    static func main() {
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            switch arguments {
            case ["--help"], []:
                printHelp()
            case ["--sample"]:
                try runSample()
            case ["--camera"]:
                try runCamera()
            default:
                throw LiveError.usage
            }
        } catch {
            fputs("planefuse-live: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
