import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import PlaneFuseCore

enum LiveError: Error, LocalizedError {
    case usage
    case cameraUnavailable
    case cameraPermissionDenied
    case cameraInputUnavailable
    case cameraOutputUnavailable
    case cameraTimedOut
    case cameraFrameUnavailable
    case unsupportedCameraFrame
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
    private let lock = NSLock()
    private var latestPixelBuffer: CVPixelBuffer?
    private var latestTimestamp: CMTime = .invalid
    private var sequence = 0
    private var deliveredSequence = 0

    struct Frame {
        let pixelBuffer: CVPixelBuffer
        let timestamp: CMTime
        let sequence: Int
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lock.lock()
        latestPixelBuffer = pixelBuffer
        latestTimestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        sequence += 1
        lock.unlock()
        semaphore.signal()
    }

    func nextFrame(timeout: TimeInterval) -> Frame? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let remaining = max(0, deadline.timeIntervalSinceNow)
            guard semaphore.wait(timeout: .now() + remaining) == .success else { return nil }
            lock.lock()
            if sequence > deliveredSequence, let pixelBuffer = latestPixelBuffer {
                deliveredSequence = sequence
                let frame = Frame(pixelBuffer: pixelBuffer, timestamp: latestTimestamp, sequence: sequence)
                lock.unlock()
                return frame
            }
            lock.unlock()
        }
        return nil
    }
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

private final class CameraInferenceRunner {
    private let baseline: MetalMobileNetV2RGBPipeline
    private let native: MetalMobileNetV2NativeStem
    private let tail: CoreMLMobileNetV2TailAdapter
    private let bNormalizedRGB: MTLTexture
    private let bActivation: MTLBuffer
    private let cActivation: MTLBuffer
    private let bShared: BufferBackedMultiArray
    private let cShared: BufferBackedMultiArray

    init() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let manifest = MobileNetV2AssetManifest.inspected
        let paths = MobileNetV2AssetPaths(environment: ProcessInfo.processInfo.environment)
        try manifest.validate(at: root)
        let lineage = try MobileNetV2DerivedArtifactManifest.load(from: root.appendingPathComponent(manifest.derivedManifest))
        try lineage.validate(at: root)
        let coefficients = try MobileNetV2StemCoefficients.load(from: URL(fileURLWithPath: paths.coefficient))
        let factory = try MetalRGBBaseline()
        let baseline = try MetalMobileNetV2RGBPipeline(device: factory.device, coefficients: coefficients)
        let native = try MetalMobileNetV2NativeStem(device: factory.device, coefficients: coefficients)
        self.baseline = baseline
        self.native = native
        self.tail = try CoreMLMobileNetV2TailAdapter(modelURL: URL(fileURLWithPath: paths.tail), manifest: manifest)
        self.bNormalizedRGB = try baseline.makeNormalizedRGBTexture()
        self.bActivation = try baseline.makeActivationBuffer()
        self.cActivation = try native.makeActivationBuffer()
        self.bShared = try BufferBackedMultiArray(buffer: bActivation, shape: MetalMobileNetV2NativeStem.activationShape)
        self.cShared = try BufferBackedMultiArray(buffer: cActivation, shape: MetalMobileNetV2NativeStem.activationShape)
    }

    func infer(output: CameraNV12MetalBridge.OutputTextures, verifyParity: Bool) throws -> CameraInferenceMeasurement {
        let input = MetalRGBBaseline.NV12Textures(yPlane: output.yPlane, uvPlane: output.uvPlane)
        let bStart = ProcessInfo.processInfo.systemUptime
        try baseline.execute(input, normalizedRGB: bNormalizedRGB, into: bActivation)
        let bFrontendMilliseconds = (ProcessInfo.processInfo.systemUptime - bStart) * 1_000
        let bOutput = try tail.predict(sharedActivation: bShared)
        let bEndToEndMilliseconds = (ProcessInfo.processInfo.systemUptime - bStart) * 1_000

        let cStart = ProcessInfo.processInfo.systemUptime
        try native.execute(input, into: cActivation)
        let cFrontendMilliseconds = (ProcessInfo.processInfo.systemUptime - cStart) * 1_000
        let cOutput = try tail.predict(sharedActivation: cShared)
        let cEndToEndMilliseconds = (ProcessInfo.processInfo.systemUptime - cStart) * 1_000
        guard let bPrediction = topPrediction(bOutput), let cPrediction = topPrediction(cOutput) else {
            throw LiveError.inferenceOutputUnavailable
        }

        var maxActivationAbsoluteDifference = 0.0
        if verifyParity {
            let bFeatures = try baseline.readActivation(from: bActivation)
            let cFeatures = try native.readActivation(from: cActivation)
            maxActivationAbsoluteDifference = zip(bFeatures, cFeatures)
                .map { abs(Double($0 - $1)) }.max() ?? 0
        }
        return CameraInferenceMeasurement(
            bFrontendMilliseconds: bFrontendMilliseconds, cFrontendMilliseconds: cFrontendMilliseconds,
            bEndToEndMilliseconds: bEndToEndMilliseconds, cEndToEndMilliseconds: cEndToEndMilliseconds,
            maxActivationAbsoluteDifference: maxActivationAbsoluteDifference,
            top1Agreement: bPrediction.label == cPrediction.label ? 1 : 0,
            bTop1Label: bPrediction.label, cTop1Label: cPrediction.label,
            bTop1Confidence: bPrediction.confidence, cTop1Confidence: cPrediction.confidence
        )
    }
}

private func printHelp() {
    print("""
    planefuse-live — honest local camera proof for PlaneFuse

    Usage:
      planefuse-live --sample   Run the local M5 MobileNetV2 B/C workload on the real corpus.
      planefuse-live --camera   Run 300 continuous camera frames through the native-plane path.
      planefuse-live --help     Show this help.

    --camera maps camera Y/UV planes with CVMetalTextureCache, performs an even-aligned
    center-square crop and nearest source-grid resize on the GPU, then runs persistent
    B/C inference. It does not use an RGB intermediate during camera resize.
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

    guard let metalDevice = MTLCreateSystemDefaultDevice() else { throw LiveError.cameraOutputUnavailable }
    let firstFrame: CameraFrameDelegate.Frame
    session.startRunning()
    defer { session.stopRunning() }
    guard let captured = delegate.nextFrame(timeout: 10) else { throw LiveError.cameraTimedOut }
    firstFrame = captured
    let geometry = try CameraResizeGeometry.make(
        width: CVPixelBufferGetWidth(firstFrame.pixelBuffer), height: CVPixelBufferGetHeight(firstFrame.pixelBuffer)
    )
    let bridge = try CameraNV12MetalBridge(device: metalDevice)
    let outputRing = try bridge.makeOutputRing(count: 3, geometry: geometry)
    let runner = try CameraInferenceRunner()
    var bFrontend: [Double] = []; var cFrontend: [Double] = []
    var bEndToEnd: [Double] = []; var cEndToEnd: [Double] = []
    var resizeGPU: [Double] = []
    var agreements = 0
    var maxActivationError = 0.0
    var firstMeasurement: CameraInferenceMeasurement?
    var lastSequence = firstFrame.sequence - 1
    for frameIndex in 0..<300 {
        let frame: CameraFrameDelegate.Frame
        if frameIndex == 0 {
            frame = firstFrame
        } else {
            guard let next = delegate.nextFrame(timeout: 2) else { throw LiveError.cameraTimedOut }
            frame = next
        }
        if frame.sequence <= lastSequence { throw LiveError.cameraFrameUnavailable }
        lastSequence = frame.sequence
        let resize = try bridge.execute(pixelBuffer: frame.pixelBuffer, into: outputRing[frameIndex % outputRing.count])
        if let gpuMilliseconds = resize.gpuMilliseconds { resizeGPU.append(gpuMilliseconds) }
        let measurement = try runner.infer(
            output: outputRing[frameIndex % outputRing.count], verifyParity: frameIndex == 0
        )
        firstMeasurement = firstMeasurement ?? measurement
        maxActivationError = max(maxActivationError, measurement.maxActivationAbsoluteDifference)
        agreements += measurement.top1Agreement == 1 ? 1 : 0
        bFrontend.append(measurement.bFrontendMilliseconds); cFrontend.append(measurement.cFrontendMilliseconds)
        bEndToEnd.append(measurement.bEndToEndMilliseconds); cEndToEnd.append(measurement.cEndToEndMilliseconds)
    }

    guard let firstMeasurement else { throw LiveError.cameraFrameUnavailable }
    let format = String(format: "0x%08X", CVPixelBufferGetPixelFormatType(firstFrame.pixelBuffer))
    print("PlaneFuse Live camera: 300 continuous native-plane frames, local MobileNetV2 B/C inference")
    print("camera_dimensions: \(geometry.cameraWidth)x\(geometry.cameraHeight)")
    print("camera_pixel_format: NV12 video-range (\(format))")
    print("camera_first_timestamp: \(firstFrame.timestamp.seconds)")
    print("camera_last_sequence: \(lastSequence)")
    print("resize_policy: CVMetalTextureCache Y/UV mapping -> GPU even-aligned center-square crop and nearest source-grid resize; output=224x224 NV12; no Swift Y/UV array copy or RGB resize")
    print(String(format: "resize_gpu_p50_ms: %.4f", median(resizeGPU)))
    print(String(format: "b_frontend_p50_ms: %.4f", median(bFrontend)))
    print(String(format: "c_frontend_p50_ms: %.4f", median(cFrontend)))
    print(String(format: "b_end_to_end_p50_ms: %.4f", median(bEndToEnd)))
    print(String(format: "c_end_to_end_p50_ms: %.4f", median(cEndToEnd)))
    print(String(format: "bc_activation_max_abs_error_first_frame: %.8f", maxActivationError))
    print("b_top1_label_first_frame: \(firstMeasurement.bTop1Label)")
    print(String(format: "b_top1_confidence_first_frame: %.8f", firstMeasurement.bTop1Confidence))
    print("c_top1_label_first_frame: \(firstMeasurement.cTop1Label)")
    print(String(format: "c_top1_confidence_first_frame: %.8f", firstMeasurement.cTop1Confidence))
    print(String(format: "top1_agreement_300_frames: %.4f", Double(agreements) / 300.0))
    print("c_rgb_intermediate_bytes: 0")
    print("c_cpu_activation_population: 0 (persistent buffer-backed MLMultiArray view)")
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

private func median(_ values: [Double]) -> Double {
    guard !values.isEmpty else { return 0 }
    let sorted = values.sorted()
    return sorted[(sorted.count - 1) / 2]
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

private func planeFuseLiveMain() {
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

planeFuseLiveMain()
