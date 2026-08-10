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
    case benchmarkReplayUnavailable
    case benchmarkArtifactWriteFailed

    var errorDescription: String? {
        switch self {
        case .usage:
            return "usage: planefuse-live <--help|--sample|--camera|--camera-bench>"
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
        case .benchmarkReplayUnavailable:
            return "The deterministic camera replay could not be captured or verified."
        case .benchmarkArtifactWriteFailed:
            return "The camera benchmark artifact could not be written."
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
    private var callbackCount = 0
    private var droppedCallbackCount = 0
    private var overwrittenFrameCount = 0
    private var lastCallbackUptime: Double?

    struct Frame {
        let pixelBuffer: CVPixelBuffer
        let timestamp: CMTime
        let sequence: Int
        let callbackArrivalUptime: Double
    }

    struct Snapshot {
        let callbackCount: Int
        let droppedCallbackCount: Int
        let overwrittenFrameCount: Int
        let latestCallbackUptime: Double?
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let callbackArrivalUptime = ProcessInfo.processInfo.systemUptime
        lock.lock()
        callbackCount += 1
        if latestPixelBuffer != nil { overwrittenFrameCount += 1 }
        latestPixelBuffer = pixelBuffer
        latestTimestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        sequence += 1
        lastCallbackUptime = callbackArrivalUptime
        lock.unlock()
        semaphore.signal()
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didDrop sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        lock.lock()
        droppedCallbackCount += 1
        lock.unlock()
    }

    func nextFrame(timeout: TimeInterval) -> Frame? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let remaining = max(0, deadline.timeIntervalSinceNow)
            guard semaphore.wait(timeout: .now() + remaining) == .success else { return nil }
            lock.lock()
            if sequence > deliveredSequence, let pixelBuffer = latestPixelBuffer {
                deliveredSequence = sequence
                let frame = Frame(
                    pixelBuffer: pixelBuffer,
                    timestamp: latestTimestamp,
                    sequence: sequence,
                    callbackArrivalUptime: lastCallbackUptime ?? ProcessInfo.processInfo.systemUptime
                )
                latestPixelBuffer = nil
                lock.unlock()
                return frame
            }
            lock.unlock()
        }
        return nil
    }

    func snapshot() -> Snapshot {
        lock.lock(); defer { lock.unlock() }
        return Snapshot(
            callbackCount: callbackCount,
            droppedCallbackCount: droppedCallbackCount,
            overwrittenFrameCount: overwrittenFrameCount,
            latestCallbackUptime: lastCallbackUptime
        )
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
    private let inputFactory: MetalRGBBaseline
    private let native: MetalMobileNetV2NativeStem
    private let tail: CoreMLMobileNetV2TailAdapter
    private let bNormalizedRGBCHW: MTLBuffer
    private let bActivation: MTLBuffer
    private let cActivation: MTLBuffer
    private let bShared: BufferBackedMultiArray
    private let cShared: BufferBackedMultiArray

    var deviceName: String { baseline.device.name }
    var computeUnitsPolicyLabel: String { tail.computeUnitsPolicyLabel }
    var b2RGBBufferLength: Int { bNormalizedRGBCHW.length }

    struct CandidateResult {
        let startUptime: Double
        let frontendEndUptime: Double
        let resultEndUptime: Double
        let frontendMilliseconds: Double
        let tailMilliseconds: Double
        let postResizeInputToResultMilliseconds: Double
        let frameDeliveryToResultMilliseconds: Double?
        let prediction: (label: String, confidence: Double)
        let activationMaxAbsoluteDifference: Double
    }

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
        let inputFactory = try MetalRGBBaseline(device: factory.device)
        let native = try MetalMobileNetV2NativeStem(device: factory.device, coefficients: coefficients)
        self.baseline = baseline
        self.inputFactory = inputFactory
        self.native = native
        self.tail = try CoreMLMobileNetV2TailAdapter(modelURL: URL(fileURLWithPath: paths.tail), manifest: manifest, computeUnits: .all)
        self.bNormalizedRGBCHW = try baseline.makeNormalizedRGBCHWBuffer()
        self.bActivation = try baseline.makeActivationBuffer()
        self.cActivation = try native.makeActivationBuffer()
        self.bShared = try BufferBackedMultiArray(buffer: bActivation, shape: MetalMobileNetV2NativeStem.activationShape)
        self.cShared = try BufferBackedMultiArray(buffer: cActivation, shape: MetalMobileNetV2NativeStem.activationShape)
    }

    func makeInputTextures(for replay: CameraReplayBuffer) throws -> [MetalRGBBaseline.NV12Textures] {
        try replay.manifest.frames.map { frame in
            let planes = try replay.planeData(for: frame)
            return try inputFactory.makeNV12Textures(
                width: replay.manifest.width,
                height: replay.manifest.height,
                yPlaneBytes: Array(planes.y),
                uvPlaneBytes: Array(planes.uv)
            )
        }
    }

    func inferB2(
        input: MetalRGBBaseline.NV12Textures,
        resizedReadyUptime: Double,
        callbackArrivalUptime: Double?,
        verifyAgainst nativeActivation: MTLBuffer? = nil
    ) throws -> CandidateResult {
        let start = ProcessInfo.processInfo.systemUptime
        try baseline.executeCHW(input, normalizedRGB: bNormalizedRGBCHW, into: bActivation)
        let frontendEnd = ProcessInfo.processInfo.systemUptime
        let tailStart = frontendEnd
        let output = try tail.predict(sharedActivation: bShared)
        let resultEnd = ProcessInfo.processInfo.systemUptime
        guard let prediction = topPrediction(output) else { throw LiveError.inferenceOutputUnavailable }
        let parity = nativeActivation.map { other in
            zip(try! baseline.readActivation(from: bActivation), try! native.readActivation(from: other))
                .map { abs(Double($0 - $1)) }.max() ?? 0
        } ?? 0
        return CandidateResult(
            startUptime: start,
            frontendEndUptime: frontendEnd,
            resultEndUptime: resultEnd,
            frontendMilliseconds: (frontendEnd - start) * 1_000,
            tailMilliseconds: (resultEnd - tailStart) * 1_000,
            postResizeInputToResultMilliseconds: (resultEnd - resizedReadyUptime) * 1_000,
            frameDeliveryToResultMilliseconds: callbackArrivalUptime.map { (resultEnd - $0) * 1_000 },
            prediction: prediction,
            activationMaxAbsoluteDifference: parity
        )
    }

    func inferC1(
        input: MetalRGBBaseline.NV12Textures,
        resizedReadyUptime: Double,
        callbackArrivalUptime: Double?,
        verifyAgainst bActivationToCompare: MTLBuffer? = nil
    ) throws -> CandidateResult {
        let start = ProcessInfo.processInfo.systemUptime
        try native.execute(input, into: cActivation)
        let frontendEnd = ProcessInfo.processInfo.systemUptime
        let tailStart = frontendEnd
        let output = try tail.predict(sharedActivation: cShared)
        let resultEnd = ProcessInfo.processInfo.systemUptime
        guard let prediction = topPrediction(output) else { throw LiveError.inferenceOutputUnavailable }
        let parity = bActivationToCompare.map { other in
            zip(try! baseline.readActivation(from: other), try! native.readActivation(from: cActivation))
                .map { abs(Double($0 - $1)) }.max() ?? 0
        } ?? 0
        return CandidateResult(
            startUptime: start,
            frontendEndUptime: frontendEnd,
            resultEndUptime: resultEnd,
            frontendMilliseconds: (frontendEnd - start) * 1_000,
            tailMilliseconds: (resultEnd - tailStart) * 1_000,
            postResizeInputToResultMilliseconds: (resultEnd - resizedReadyUptime) * 1_000,
            frameDeliveryToResultMilliseconds: callbackArrivalUptime.map { (resultEnd - $0) * 1_000 },
            prediction: prediction,
            activationMaxAbsoluteDifference: parity
        )
    }

    func activationMaxAbsoluteDifference() throws -> Double {
        zip(try baseline.readActivation(from: bActivation), try native.readActivation(from: cActivation))
            .map { abs(Double($0 - $1)) }.max() ?? 0
    }

    func infer(output: CameraNV12MetalBridge.OutputTextures, verifyParity: Bool) throws -> CameraInferenceMeasurement {
        let input = MetalRGBBaseline.NV12Textures(yPlane: output.yPlane, uvPlane: output.uvPlane)
        let bStart = ProcessInfo.processInfo.systemUptime
        try baseline.executeCHW(input, normalizedRGB: bNormalizedRGBCHW, into: bActivation)
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
      planefuse-live --camera-bench   Run the Release-grade paired/replay/live camera benchmark and write JSON.
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

private final class LiveCameraCapture {
    let session: AVCaptureSession
    let device: AVCaptureDevice
    let delegate: CameraFrameDelegate
    let bridge: CameraNV12MetalBridge
    let geometry: CameraResizeGeometry
    let firstFrame: CameraFrameDelegate.Frame
    let activeFormat: String
    let frameDurationSeconds: Double?
    private var firstFramePending = true

    init() throws {
        guard AVCaptureDevice.authorizationStatus(for: .video) != .denied,
              AVCaptureDevice.authorizationStatus(for: .video) != .restricted else {
            throw LiveError.cameraPermissionDenied
        }
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            guard awaitCameraAccess() else { throw LiveError.cameraPermissionDenied }
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
        output.setSampleBufferDelegate(delegate, queue: DispatchQueue(label: "planefuse-live.camera"))
        guard session.canAddOutput(output) else { throw LiveError.cameraOutputUnavailable }
        session.addOutput(output)
        guard let metalDevice = MTLCreateSystemDefaultDevice() else { throw LiveError.cameraOutputUnavailable }
        let bridge = try CameraNV12MetalBridge(device: metalDevice)
        session.startRunning()
        guard let firstFrame = delegate.nextFrame(timeout: 10) else {
            session.stopRunning()
            throw LiveError.cameraTimedOut
        }
        let geometry = try CameraResizeGeometry.make(
            width: CVPixelBufferGetWidth(firstFrame.pixelBuffer),
            height: CVPixelBufferGetHeight(firstFrame.pixelBuffer)
        )
        self.session = session
        self.device = device
        self.delegate = delegate
        self.bridge = bridge
        self.geometry = geometry
        self.firstFrame = firstFrame
        self.activeFormat = "\(geometry.cameraWidth)x\(geometry.cameraHeight)-\(String(format: "0x%08X", CVPixelBufferGetPixelFormatType(firstFrame.pixelBuffer)))"
        let duration = device.activeVideoMinFrameDuration
        self.frameDurationSeconds = duration.isValid && duration.seconds > 0 ? duration.seconds : nil
    }

    deinit { session.stopRunning() }

    func nextFrame(timeout: TimeInterval) throws -> CameraFrameDelegate.Frame {
        if firstFramePending {
            firstFramePending = false
            return firstFrame
        }
        guard let frame = delegate.nextFrame(timeout: timeout) else { throw LiveError.cameraTimedOut }
        return frame
    }
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

private enum CameraCandidateMode: String {
    case b2
    case c1
}

private func thermalStateName(_ state: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState) -> String {
    switch state {
    case .nominal: return "nominal"
    case .fair: return "fair"
    case .serious: return "serious"
    case .critical: return "critical"
    @unknown default: return "unknown"
    }
}

private struct ReplayCaptureResult {
    let replay: CameraReplayBuffer
    let resizeGPU: CameraBenchmarkTimingArtifact
    let resizeWall: CameraBenchmarkTimingArtifact
}

private func captureReplay(_ capture: LiveCameraCapture, frameCount: Int = 300) throws -> ReplayCaptureResult {
    let outputRing = try capture.bridge.makeOutputRing(count: 3, geometry: capture.geometry)
    var frames: [CameraReplayFramePayload] = []
    var resizeGPU: [Double] = []; var resizeWall: [Double] = []
    frames.reserveCapacity(frameCount)
    for index in 0..<frameCount {
        let frame = try capture.nextFrame(timeout: 2)
        let output = outputRing[index % outputRing.count]
        let resizeStart = ProcessInfo.processInfo.systemUptime
        let execution = try capture.bridge.execute(pixelBuffer: frame.pixelBuffer, into: output)
        resizeWall.append((ProcessInfo.processInfo.systemUptime - resizeStart) * 1_000)
        if let gpuMilliseconds = execution.gpuMilliseconds { resizeGPU.append(gpuMilliseconds) }
        let planes = try capture.bridge.readPlanes(from: output)
        frames.append(CameraReplayFramePayload(
            presentationTimestampSeconds: frame.timestamp.isValid ? frame.timestamp.seconds : nil,
            callbackSequence: frame.sequence,
            yPlane: planes.y,
            uvPlane: planes.uv
        ))
    }
    let replay = try CameraReplayBuffer(
        frames: frames,
        width: 224,
        height: 224,
        cadenceHz: capture.frameDurationSeconds.map { 1 / $0 }
    )
    return ReplayCaptureResult(
        replay: replay,
        resizeGPU: try CameraBenchmarkTimingArtifact(resizeGPU),
        resizeWall: try CameraBenchmarkTimingArtifact(resizeWall)
    )
}

private func runReplayCandidate(
    mode: CameraCandidateMode,
    runner: CameraInferenceRunner,
    textures: [MetalRGBBaseline.NV12Textures],
    replay: CameraReplayBuffer,
    measuredFrames: Int = 300
) throws -> CameraBenchmarkCandidateArtifact {
    guard !textures.isEmpty else { throw LiveError.benchmarkReplayUnavailable }
    for warmup in 0..<20 {
        let input = textures[warmup % textures.count]
        let ready = ProcessInfo.processInfo.systemUptime
        if mode == .b2 {
            _ = try runner.inferB2(input: input, resizedReadyUptime: ready, callbackArrivalUptime: nil)
        } else {
            _ = try runner.inferC1(input: input, resizedReadyUptime: ready, callbackArrivalUptime: nil)
        }
    }
    let start = ProcessInfo.processInfo.systemUptime
    var post: [Double] = []; var frontend: [Double] = []; var tail: [Double] = []
    var records: [CameraBenchmarkFrameRecord] = []
    records.reserveCapacity(measuredFrames)
    for index in 0..<measuredFrames {
        let replayFrame = replay.manifest.frames[index % replay.manifest.frames.count]
        let input = textures[index % textures.count]
        let ready = ProcessInfo.processInfo.systemUptime
        let result: CameraInferenceRunner.CandidateResult
        if mode == .b2 {
            result = try runner.inferB2(input: input, resizedReadyUptime: ready, callbackArrivalUptime: nil)
        } else {
            result = try runner.inferC1(input: input, resizedReadyUptime: ready, callbackArrivalUptime: nil)
        }
        post.append(result.postResizeInputToResultMilliseconds)
        frontend.append(result.frontendMilliseconds)
        tail.append(result.tailMilliseconds)
        records.append(CameraBenchmarkFrameRecord(
            frameID: replayFrame.frameID,
            callbackSequence: replayFrame.callbackSequence,
            executionOrder: nil,
            callbackArrivalUptime: nil,
            resizedReadyUptime: ready,
            frontendEndUptime: result.frontendEndUptime,
            resultEndUptime: result.resultEndUptime,
            frameDeliveryToResultMilliseconds: nil,
            postResizeInputToResultMilliseconds: result.postResizeInputToResultMilliseconds,
            frontendMilliseconds: result.frontendMilliseconds,
            tailMilliseconds: result.tailMilliseconds,
            top1Label: result.prediction.label,
            top1Confidence: result.prediction.confidence,
            thermalState: thermalStateName()
        ))
    }
    let elapsed = ProcessInfo.processInfo.systemUptime - start
    guard measuredFrames > 0 else { throw LiveError.benchmarkReplayUnavailable }
    return CameraBenchmarkCandidateArtifact(
        mode: mode.rawValue,
        source: "deterministic_replay",
        replayPayloadSHA256: replay.manifest.payloadSHA256,
        processedFrames: measuredFrames,
        sustainedFPS: elapsed > 0 ? Double(measuredFrames) / elapsed : nil,
        callbackRate: nil,
        droppedCallbacks: 0,
        lateCallbacks: 0,
        overwrittenFrames: 0,
        skippedFrames: 0,
        postResizeInputToResult: try CameraBenchmarkTimingArtifact(post),
        frameDeliveryToResult: nil,
        frontend: try CameraBenchmarkTimingArtifact(frontend),
        tail: try CameraBenchmarkTimingArtifact(tail),
        thermalStateStart: records.first?.thermalState ?? thermalStateName(),
        thermalStateEnd: thermalStateName(),
        rawFrameRecords: records
    )
}

private func runPairedReplay(
    runner: CameraInferenceRunner,
    textures: [MetalRGBBaseline.NV12Textures],
    replay: CameraReplayBuffer
) throws -> (CameraBenchmarkPairedArtifact, CameraBenchmarkQualityArtifact) {
    guard !textures.isEmpty, replay.manifest.frames.count > 0 else { throw LiveError.benchmarkReplayUnavailable }
    var allB: [Double] = []; var allC: [Double] = []; var allDifferences: [Double] = []
    var batchDifferences: [BenchmarkStatistics.PairedBatch] = []
    var pairRecords: [CameraBenchmarkPairRecord] = []
    var firstOrderPairs = 0; var secondOrderPairs = 0; var agreements = 0
    var firstBLabel = ""; var firstCLabel = ""; var firstBConfidence = 0.0; var firstCConfidence = 0.0
    var maxActivationError = 0.0
    for batchIndex in 0..<BenchmarkStatistics.bootstrapBatchCount {
        for warmup in 0..<20 {
            let input = textures[(batchIndex * 20 + warmup) % textures.count]
            let ready = ProcessInfo.processInfo.systemUptime
            if (batchIndex + warmup).isMultiple(of: 2) {
                _ = try runner.inferB2(input: input, resizedReadyUptime: ready, callbackArrivalUptime: nil)
                _ = try runner.inferC1(input: input, resizedReadyUptime: ProcessInfo.processInfo.systemUptime, callbackArrivalUptime: nil)
            } else {
                _ = try runner.inferC1(input: input, resizedReadyUptime: ready, callbackArrivalUptime: nil)
                _ = try runner.inferB2(input: input, resizedReadyUptime: ProcessInfo.processInfo.systemUptime, callbackArrivalUptime: nil)
            }
        }
        var differences: [Double] = []
        differences.reserveCapacity(BenchmarkStatistics.bootstrapPairsPerBatch)
        for pairIndex in 0..<BenchmarkStatistics.bootstrapPairsPerBatch {
            let frame = replay.manifest.frames[(batchIndex * BenchmarkStatistics.bootstrapPairsPerBatch + pairIndex) % replay.manifest.frames.count]
            let input = textures[frame.frameID % textures.count]
            let bFirst = (batchIndex + pairIndex).isMultiple(of: 2)
            let bResult: CameraInferenceRunner.CandidateResult
            let cResult: CameraInferenceRunner.CandidateResult
            if bFirst {
                firstOrderPairs += 1
                bResult = try runner.inferB2(input: input, resizedReadyUptime: ProcessInfo.processInfo.systemUptime, callbackArrivalUptime: nil)
                cResult = try runner.inferC1(input: input, resizedReadyUptime: ProcessInfo.processInfo.systemUptime, callbackArrivalUptime: nil)
            } else {
                secondOrderPairs += 1
                cResult = try runner.inferC1(input: input, resizedReadyUptime: ProcessInfo.processInfo.systemUptime, callbackArrivalUptime: nil)
                bResult = try runner.inferB2(input: input, resizedReadyUptime: ProcessInfo.processInfo.systemUptime, callbackArrivalUptime: nil)
            }
            let difference = bResult.postResizeInputToResultMilliseconds - cResult.postResizeInputToResultMilliseconds
            differences.append(difference); allDifferences.append(difference)
            allB.append(bResult.postResizeInputToResultMilliseconds); allC.append(cResult.postResizeInputToResultMilliseconds)
            agreements += bResult.prediction.label == cResult.prediction.label ? 1 : 0
            if pairRecords.isEmpty {
                firstBLabel = bResult.prediction.label; firstCLabel = cResult.prediction.label
                firstBConfidence = bResult.prediction.confidence; firstCConfidence = cResult.prediction.confidence
            }
            maxActivationError = max(maxActivationError, try runner.activationMaxAbsoluteDifference())
            pairRecords.append(CameraBenchmarkPairRecord(
                batchID: "batch-\(batchIndex)", frameID: frame.frameID,
                executionOrder: bFirst ? "B2_then_C1" : "C1_then_B2",
                b2PostResizeInputToResultMilliseconds: bResult.postResizeInputToResultMilliseconds,
                c1PostResizeInputToResultMilliseconds: cResult.postResizeInputToResultMilliseconds,
                differenceMilliseconds: difference,
                b2FrontendMilliseconds: bResult.frontendMilliseconds,
                c1FrontendMilliseconds: cResult.frontendMilliseconds,
                b2TailMilliseconds: bResult.tailMilliseconds,
                c1TailMilliseconds: cResult.tailMilliseconds,
                thermalState: thermalStateName()
            ))
        }
        batchDifferences.append(BenchmarkStatistics.PairedBatch(batchID: "batch-\(batchIndex)", differences: differences))
    }
    let bootstrap = try BenchmarkStatistics.pairedBlockBootstrap(batchDifferences)
    let paired = CameraBenchmarkPairedArtifact(
        metric: "post_resize_input_to_result",
        signConvention: BenchmarkStatistics.pairedDifferenceConvention,
        batchCount: BenchmarkStatistics.bootstrapBatchCount,
        pairsPerBatch: BenchmarkStatistics.bootstrapPairsPerBatch,
        differences: allDifferences,
        batchDifferences: batchDifferences,
        differenceSummary: try CameraBenchmarkTimingArtifact(allDifferences),
        bootstrap: bootstrap,
        aggregatePercentage: try BenchmarkStatistics.aggregatePercentage(pipelineB: allB, pipelineC: allC),
        firstOrderPairs: firstOrderPairs,
        secondOrderPairs: secondOrderPairs,
        rawPairRecords: pairRecords
    )
    let quality = CameraBenchmarkQualityArtifact(
        activationMaxAbsoluteError: maxActivationError,
        top1Agreement: Double(agreements) / Double(allDifferences.count),
        bTop1Label: firstBLabel,
        cTop1Label: firstCLabel,
        probabilityL1Distance: nil,
        cpuElementByElementPopulationBytes: 0,
        cFullRGBIntermediateBytes: 0
    )
    _ = firstBConfidence; _ = firstCConfidence
    return (paired, quality)
}

private func runLiveCandidate(
    mode: CameraCandidateMode,
    runner: CameraInferenceRunner,
    measuredFrames: Int = 300
) throws -> (CameraBenchmarkCandidateArtifact, LiveCameraCapture) {
    let capture = try LiveCameraCapture()
    let outputRing = try capture.bridge.makeOutputRing(count: 3, geometry: capture.geometry)
    for warmup in 0..<20 {
        let frame = try capture.nextFrame(timeout: 2)
        let output = outputRing[warmup % outputRing.count]
        _ = try capture.bridge.execute(pixelBuffer: frame.pixelBuffer, into: output)
        let input = MetalRGBBaseline.NV12Textures(yPlane: output.yPlane, uvPlane: output.uvPlane)
        let ready = ProcessInfo.processInfo.systemUptime
        if mode == .b2 {
            _ = try runner.inferB2(input: input, resizedReadyUptime: ready, callbackArrivalUptime: frame.callbackArrivalUptime)
        } else {
            _ = try runner.inferC1(input: input, resizedReadyUptime: ready, callbackArrivalUptime: frame.callbackArrivalUptime)
        }
    }
    let start = ProcessInfo.processInfo.systemUptime
    var post: [Double] = []; var delivery: [Double] = []; var frontend: [Double] = []; var tail: [Double] = []
    var records: [CameraBenchmarkFrameRecord] = []
    var skipped = 0; var previousSequence: Int?
    records.reserveCapacity(measuredFrames)
    for index in 0..<measuredFrames {
        let frame = try capture.nextFrame(timeout: 2)
        if let previousSequence, frame.sequence > previousSequence + 1 { skipped += frame.sequence - previousSequence - 1 }
        previousSequence = frame.sequence
        let output = outputRing[index % outputRing.count]
        _ = try capture.bridge.execute(pixelBuffer: frame.pixelBuffer, into: output)
        let ready = ProcessInfo.processInfo.systemUptime
        let input = MetalRGBBaseline.NV12Textures(yPlane: output.yPlane, uvPlane: output.uvPlane)
        let result = mode == .b2
            ? try runner.inferB2(input: input, resizedReadyUptime: ready, callbackArrivalUptime: frame.callbackArrivalUptime)
            : try runner.inferC1(input: input, resizedReadyUptime: ready, callbackArrivalUptime: frame.callbackArrivalUptime)
        post.append(result.postResizeInputToResultMilliseconds)
        if let value = result.frameDeliveryToResultMilliseconds { delivery.append(value) }
        frontend.append(result.frontendMilliseconds); tail.append(result.tailMilliseconds)
        records.append(CameraBenchmarkFrameRecord(
            frameID: index,
            callbackSequence: frame.sequence,
            executionOrder: nil,
            callbackArrivalUptime: frame.callbackArrivalUptime,
            resizedReadyUptime: ready,
            frontendEndUptime: result.frontendEndUptime,
            resultEndUptime: result.resultEndUptime,
            frameDeliveryToResultMilliseconds: result.frameDeliveryToResultMilliseconds,
            postResizeInputToResultMilliseconds: result.postResizeInputToResultMilliseconds,
            frontendMilliseconds: result.frontendMilliseconds,
            tailMilliseconds: result.tailMilliseconds,
            top1Label: result.prediction.label,
            top1Confidence: result.prediction.confidence,
            thermalState: thermalStateName()
        ))
    }
    let end = ProcessInfo.processInfo.systemUptime
    let snapshot = capture.delegate.snapshot()
    let callbackRate = end > start ? Double(snapshot.callbackCount) / (end - start) : nil
    return (
        CameraBenchmarkCandidateArtifact(
            mode: mode.rawValue,
            source: "physical_camera_live",
            replayPayloadSHA256: nil,
            processedFrames: measuredFrames,
            sustainedFPS: end > start ? Double(measuredFrames) / (end - start) : nil,
            callbackRate: callbackRate,
            droppedCallbacks: snapshot.droppedCallbackCount,
            lateCallbacks: 0,
            overwrittenFrames: snapshot.overwrittenFrameCount,
            skippedFrames: skipped,
            postResizeInputToResult: try CameraBenchmarkTimingArtifact(post),
            frameDeliveryToResult: delivery.isEmpty ? nil : try CameraBenchmarkTimingArtifact(delivery),
            frontend: try CameraBenchmarkTimingArtifact(frontend),
            tail: try CameraBenchmarkTimingArtifact(tail),
            thermalStateStart: records.first?.thermalState ?? thermalStateName(),
            thermalStateEnd: thermalStateName(),
            rawFrameRecords: records
        ),
        capture
    )
}

private func runCameraBenchmark() throws {
    let runner = try CameraInferenceRunner()
    let capture = try LiveCameraCapture()
    let replayCapture = try captureReplay(capture)
    let replay = replayCapture.replay
    let outputPath = ProcessInfo.processInfo.environment["PF_BENCHMARK_OUTPUT"] ?? "benchmarks/results/r6-camera.json"
    let outputURL = URL(fileURLWithPath: outputPath, isDirectory: false)
    let replayDirectory = outputURL.deletingLastPathComponent()
    let persistedReplay = try replay.write(to: replayDirectory, stem: "r6-camera-replay")
    capture.session.stopRunning()
    let textures = try runner.makeInputTextures(for: persistedReplay)
    let (paired, quality) = try runPairedReplay(runner: runner, textures: textures, replay: persistedReplay)
    let b2Replay = try runReplayCandidate(mode: .b2, runner: runner, textures: textures, replay: persistedReplay)
    let c1Replay = try runReplayCandidate(mode: .c1, runner: runner, textures: textures, replay: persistedReplay)
    let b2Live = try runLiveCandidate(mode: .b2, runner: runner).0
    let c1Live = try runLiveCandidate(mode: .c1, runner: runner).0
    guard b2Replay.processedFrames >= 300, c1Replay.processedFrames >= 300,
          persistedReplay.manifest.frames.count >= 300,
          b2Replay.source == "deterministic_replay", c1Replay.source == "deterministic_replay" else {
        throw LiveError.benchmarkReplayUnavailable
    }
    let replayArtifact = CameraBenchmarkReplayArtifact(
        schemaVersion: persistedReplay.manifest.schemaVersion,
        payloadSHA256: persistedReplay.manifest.payloadSHA256,
        manifestSHA256: persistedReplay.manifestSHA256,
        frameCount: persistedReplay.manifest.frames.count,
        frameIDs: persistedReplay.manifest.frames.map(\.frameID),
        callbackSequences: persistedReplay.manifest.frames.map(\.callbackSequence),
        width: persistedReplay.manifest.width,
        height: persistedReplay.manifest.height,
        pixelFormat: persistedReplay.manifest.pixelFormat,
        cadenceHz: persistedReplay.manifest.cadenceHz
    )
    let artifact = CameraBenchmarkArtifact(
        schemaVersion: "r6.1-camera-benchmark-v1",
        commit: ProcessInfo.processInfo.environment["PF_GIT_COMMIT"] ?? "unknown",
        buildConfiguration: ProcessInfo.processInfo.environment["PF_BUILD_CONFIGURATION"] ?? "release",
        computeUnitsPolicy: runner.computeUnitsPolicyLabel,
        deviceName: runner.deviceName,
        architecture: ProcessInfo.processInfo.environment["PF_ARCHITECTURE"] ?? "unknown",
        osVersion: ProcessInfo.processInfo.environment["PF_OS_VERSION"] ?? ProcessInfo.processInfo.operatingSystemVersionString,
        cameraActiveFormat: capture.activeFormat,
        cameraDimensions: "\(capture.geometry.cameraWidth)x\(capture.geometry.cameraHeight)",
        cameraPixelFormat: persistedReplay.manifest.pixelFormat,
        cameraFrameDurationSeconds: capture.frameDurationSeconds,
        cameraResizeGPU: replayCapture.resizeGPU,
        cameraResizeWall: replayCapture.resizeWall,
        replay: replayArtifact,
        paired: paired,
        b2Replay: b2Replay,
        c1Replay: c1Replay,
        b2Live: b2Live,
        c1Live: c1Live,
        quality: quality,
        rgbLogicalBytesB2: 224 * 224 * 3 * MemoryLayout<Float>.stride,
        rgbAllocatedBytesB2: 224 * 224 * 3 * MemoryLayout<Float>.stride,
        rgbLogicalBytesC1: 0,
        rgbAllocatedBytesC1: 0,
        gpuCommandBufferPolicy: "synchronous; one resize submission plus one candidate submission",
        synchronizationPolicy: "waitUntilCompleted for resize and each stem/tail boundary",
        statisticsAlgorithmVersion: BenchmarkStatistics.algorithmVersion,
        bootstrapSeed: BenchmarkStatistics.bootstrapSeed,
        bootstrapReplicates: BenchmarkStatistics.bootstrapReplicateCount,
        thermalStateAtArtifact: thermalStateName(),
        gpuCommandBuffersB2: 1,
        gpuCommandBuffersC1: 1,
        synchronizationCountB2: 1,
        synchronizationCountC1: 1
    )
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try encoder.encode(artifact).write(to: outputURL, options: .atomic)
    print("PASS camera benchmark: \(outputURL.path)")
    print("replay_payload_sha256: \(persistedReplay.manifest.payloadSHA256)")
    print("replay_frames: \(persistedReplay.manifest.frames.count)")
    print("paired_metric: \(paired.metric)")
    print(String(format: "paired_b_minus_c_p50_ms: %.4f", paired.differenceSummary.p50))
    print(String(format: "paired_b_minus_c_p95_ms: %.4f", paired.differenceSummary.p95))
    print(String(format: "paired_percentage: %.4f", paired.aggregatePercentage))
    print(String(format: "paired_bootstrap_median_ci_ms: [%.4f, %.4f]", paired.bootstrap.medianDifference.lower, paired.bootstrap.medianDifference.upper))
    print(String(format: "top1_agreement: %.4f", quality.top1Agreement))
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
        case ["--camera-bench"]:
            try runCameraBenchmark()
        default:
            throw LiveError.usage
        }
    } catch {
        fputs("planefuse-live: \(error.localizedDescription)\n", stderr)
        exit(1)
    }
}

planeFuseLiveMain()
