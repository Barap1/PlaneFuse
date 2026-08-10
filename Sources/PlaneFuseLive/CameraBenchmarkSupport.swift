import CryptoKit
import Foundation
import PlaneFuseCore

struct CameraReplayFrameManifest: Codable, Equatable {
    let frameID: Int
    let presentationTimestampSeconds: Double?
    let callbackSequence: Int
    let yOffset: Int
    let yLength: Int
    let uvOffset: Int
    let uvLength: Int
}

struct CameraReplayManifest: Codable, Equatable {
    let schemaVersion: String
    let width: Int
    let height: Int
    let pixelFormat: String
    let cadenceHz: Double?
    let payloadSHA256: String
    let frames: [CameraReplayFrameManifest]
}

struct CameraReplayFramePayload {
    let presentationTimestampSeconds: Double?
    let callbackSequence: Int
    let yPlane: Data
    let uvPlane: Data
}

struct CameraReplayBuffer {
    let manifest: CameraReplayManifest
    let payload: Data
    let payloadURL: URL?
    let manifestURL: URL?

    init(frames: [CameraReplayFramePayload], width: Int = 224, height: Int = 224, cadenceHz: Double?) throws {
        guard !frames.isEmpty else { throw LiveError.cameraFrameUnavailable }
        let expectedY = width * height
        let expectedUV = width * height / 2
        var payload = Data()
        var records: [CameraReplayFrameManifest] = []
        records.reserveCapacity(frames.count)
        for (frameID, frame) in frames.enumerated() {
            guard frame.yPlane.count == expectedY, frame.uvPlane.count == expectedUV else {
                throw LiveError.unsupportedCameraFrame
            }
            let yOffset = payload.count
            payload.append(frame.yPlane)
            let uvOffset = payload.count
            payload.append(frame.uvPlane)
            records.append(CameraReplayFrameManifest(
                frameID: frameID,
                presentationTimestampSeconds: frame.presentationTimestampSeconds,
                callbackSequence: frame.callbackSequence,
                yOffset: yOffset,
                yLength: frame.yPlane.count,
                uvOffset: uvOffset,
                uvLength: frame.uvPlane.count
            ))
        }
        self.payload = payload
        self.manifest = CameraReplayManifest(
            schemaVersion: "r6.1-camera-replay-v1",
            width: width,
            height: height,
            pixelFormat: "420YpCbCr8BiPlanarVideoRange",
            cadenceHz: cadenceHz,
            payloadSHA256: Self.sha256(payload),
            frames: records
        )
        self.payloadURL = nil
        self.manifestURL = nil
    }

    private init(manifest: CameraReplayManifest, payload: Data, payloadURL: URL, manifestURL: URL) {
        self.manifest = manifest
        self.payload = payload
        self.payloadURL = payloadURL
        self.manifestURL = manifestURL
    }

    func write(to directory: URL, stem: String) throws -> CameraReplayBuffer {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let payloadURL = directory.appendingPathComponent("\(stem).bin")
        let manifestURL = directory.appendingPathComponent("\(stem).manifest.json")
        try payload.write(to: payloadURL, options: .atomic)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)
        return CameraReplayBuffer(manifest: manifest, payload: payload, payloadURL: payloadURL, manifestURL: manifestURL)
    }

    static func load(payloadURL: URL, manifestURL: URL) throws -> CameraReplayBuffer {
        let payload = try Data(contentsOf: payloadURL)
        let manifest = try JSONDecoder().decode(CameraReplayManifest.self, from: Data(contentsOf: manifestURL))
        guard Self.sha256(payload) == manifest.payloadSHA256 else { throw LiveError.cameraFrameUnavailable }
        return CameraReplayBuffer(manifest: manifest, payload: payload, payloadURL: payloadURL, manifestURL: manifestURL)
    }

    func frame(at index: Int) throws -> CameraReplayFrameManifest {
        guard manifest.frames.indices.contains(index) else { throw LiveError.cameraFrameUnavailable }
        return manifest.frames[index]
    }

    func planeData(for frame: CameraReplayFrameManifest) throws -> (y: Data, uv: Data) {
        guard frame.yOffset >= 0, frame.uvOffset >= 0,
              frame.yOffset + frame.yLength <= payload.count,
              frame.uvOffset + frame.uvLength <= payload.count else {
            throw LiveError.cameraFrameUnavailable
        }
        return (
            y: payload.subdata(in: frame.yOffset..<(frame.yOffset + frame.yLength)),
            uv: payload.subdata(in: frame.uvOffset..<(frame.uvOffset + frame.uvLength))
        )
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    var manifestSHA256: String? {
        guard let manifestURL, let data = try? Data(contentsOf: manifestURL) else { return nil }
        return Self.sha256(data)
    }
}

struct CameraBenchmarkTimingArtifact: Codable {
    let count: Int
    let p50: Double
    let p95: Double
    let mean: Double
    let mad: Double
    let rawMilliseconds: [Double]

    init(_ samples: [Double]) throws {
        let summary = try BenchmarkStatistics.summary(samples)
        self.count = samples.count
        self.p50 = summary.p50
        self.p95 = summary.p95
        self.mean = summary.mean
        self.mad = summary.medianAbsoluteDeviation
        self.rawMilliseconds = samples
    }
}

struct CameraBenchmarkReplayArtifact: Codable {
    let schemaVersion: String
    let payloadSHA256: String
    let manifestSHA256: String?
    let frameCount: Int
    let frameIDs: [Int]
    let callbackSequences: [Int]
    let width: Int
    let height: Int
    let pixelFormat: String
    let cadenceHz: Double?
}

struct CameraBenchmarkCandidateArtifact: Codable {
    let mode: String
    let source: String
    let replayPayloadSHA256: String?
    let processedFrames: Int
    let sustainedFPS: Double?
    let callbackRate: Double?
    let droppedCallbacks: Int
    let lateCallbacks: Int
    let overwrittenFrames: Int
    let skippedFrames: Int
    let postResizeInputToResult: CameraBenchmarkTimingArtifact
    let frameDeliveryToResult: CameraBenchmarkTimingArtifact?
    let frontend: CameraBenchmarkTimingArtifact
    let tail: CameraBenchmarkTimingArtifact
    let thermalStateStart: String
    let thermalStateEnd: String
    let rawFrameRecords: [CameraBenchmarkFrameRecord]
}

struct CameraBenchmarkFrameRecord: Codable {
    let frameID: Int
    let callbackSequence: Int
    let executionOrder: String?
    let callbackArrivalUptime: Double?
    let resizedReadyUptime: Double
    let frontendEndUptime: Double
    let resultEndUptime: Double
    let frameDeliveryToResultMilliseconds: Double?
    let postResizeInputToResultMilliseconds: Double
    let frontendMilliseconds: Double
    let tailMilliseconds: Double
    let top1Label: String
    let top1Confidence: Double
    let thermalState: String
}

struct CameraBenchmarkPairedArtifact: Codable {
    let metric: String
    let signConvention: String
    let batchCount: Int
    let pairsPerBatch: Int
    let differences: [Double]
    let batchDifferences: [BenchmarkStatistics.PairedBatch]
    let differenceSummary: CameraBenchmarkTimingArtifact
    let bootstrap: BenchmarkStatistics.PairedBootstrapResult
    let aggregatePercentage: Double
    let firstOrderPairs: Int
    let secondOrderPairs: Int
    let rawPairRecords: [CameraBenchmarkPairRecord]
}

struct CameraBenchmarkPairRecord: Codable {
    let batchID: String
    let frameID: Int
    let executionOrder: String
    let b2PostResizeInputToResultMilliseconds: Double
    let c1PostResizeInputToResultMilliseconds: Double
    let differenceMilliseconds: Double
    let b2FrontendMilliseconds: Double
    let c1FrontendMilliseconds: Double
    let b2TailMilliseconds: Double
    let c1TailMilliseconds: Double
    let thermalState: String
}

struct CameraBenchmarkQualityArtifact: Codable {
    let activationMaxAbsoluteError: Double
    let top1Agreement: Double
    let bTop1Label: String
    let cTop1Label: String
    let probabilityL1Distance: Double?
    let cpuElementByElementPopulationBytes: Int
    let cFullRGBIntermediateBytes: Int
}

struct CameraBenchmarkArtifact: Codable {
    let schemaVersion: String
    let commit: String
    let buildConfiguration: String
    let computeUnitsPolicy: String
    let deviceName: String
    let architecture: String
    let osVersion: String
    let cameraActiveFormat: String
    let cameraDimensions: String
    let cameraPixelFormat: String
    let cameraFrameDurationSeconds: Double?
    let cameraResizeGPU: CameraBenchmarkTimingArtifact
    let cameraResizeWall: CameraBenchmarkTimingArtifact
    let replay: CameraBenchmarkReplayArtifact
    let paired: CameraBenchmarkPairedArtifact
    let b2Replay: CameraBenchmarkCandidateArtifact
    let c1Replay: CameraBenchmarkCandidateArtifact
    let b2Live: CameraBenchmarkCandidateArtifact?
    let c1Live: CameraBenchmarkCandidateArtifact?
    let quality: CameraBenchmarkQualityArtifact
    let rgbLogicalBytesB2: Int
    let rgbAllocatedBytesB2: Int
    let rgbLogicalBytesC1: Int
    let rgbAllocatedBytesC1: Int
    let gpuCommandBufferPolicy: String
    let synchronizationPolicy: String
    let statisticsAlgorithmVersion: String
    let bootstrapSeed: UInt64
    let bootstrapReplicates: Int
    let thermalStateAtArtifact: String
    let gpuCommandBuffersB2: Int
    let gpuCommandBuffersC1: Int
    let synchronizationCountB2: Int
    let synchronizationCountC1: Int
}
