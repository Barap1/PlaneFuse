import CoreML
import Metal
import XCTest
@testable import PlaneFuseCore

final class MobileNetV2PretrainedParityTests: XCTestCase {
    func testOriginalDerivedArrayModelsAgreeWithSplitTailAndNativeStemsOnRealCorpus() throws {
        let coefficientURL = URL(fileURLWithPath: "models/derived/MobileNetV2StemCoefficients.json")
        let stemURL = URL(fileURLWithPath: "models/derived/stem-array-compiled/MobileNetV2Stem.mlmodelc")
        let fullURL = URL(fileURLWithPath: "models/derived/full-array-compiled/MobileNetV2FullArray.mlmodelc")
        let tailURL = URL(fileURLWithPath: "models/derived/tail-compiled/MobileNetV2Tail.mlmodelc")
        guard [coefficientURL, stemURL, fullURL, tailURL].allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) else {
            throw XCTSkip("Run scripts/prepare_mobilenetv2.py and compile StemArray/FullArray local artifacts.")
        }
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal is unavailable.")
        }

        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let lineage = try MobileNetV2DerivedArtifactManifest.load(from: root.appendingPathComponent("models/derived/manifest.json"))
        try lineage.validate(at: root)
        let corpus = try MobileNetV2Corpus(manifestURL: root.appendingPathComponent("proof/m5-validation-corpus.json"), root: root)
        let coefficients = try MobileNetV2StemCoefficients.load(from: coefficientURL)
        let factory = try MetalRGBBaseline(device: device)
        let rgb = try MetalMobileNetV2RGBPipeline(device: device, coefficients: coefficients)
        let native = try MetalMobileNetV2NativeStem(device: device, coefficients: coefficients)
        let normalizedRGB = try rgb.makeNormalizedRGBTexture()
        let bOutput = try rgb.makeActivationBuffer()
        let cOutput = try native.makeActivationBuffer()
        let stemArray = try CoreMLMobileNetV2StemArrayAdapter(modelURL: stemURL, lineage: lineage, computeUnits: .cpuOnly)
        let fullArray = try CoreMLMobileNetV2FullArrayAdapter(modelURL: fullURL, lineage: lineage, computeUnits: .cpuOnly)
        let tail = try CoreMLMobileNetV2TailAdapter(modelURL: tailURL, manifest: .inspected)

        var maxStemArrayVsB = 0.0
        var maxStemArrayVsC = 0.0
        var fullArraySplitTailMatches = 0
        var disagreements: [String] = []
        for frame in try corpus.loadFrames() {
            let input = try factory.makeNV12Textures(width: 224, height: 224, yPlaneBytes: frame.yPlaneBytes, uvPlaneBytes: frame.uvPlaneBytes)
            try rgb.execute(input, normalizedRGB: normalizedRGB, into: bOutput)
            try native.execute(input, into: cOutput)
            let sourcePreprocessed = try rgb.readNormalizedRGB(from: normalizedRGB)
            let stemFeatures = try stemArray.predict(normalizedRGB: sourcePreprocessed)
            let bFeatures = try rgb.readActivation(from: bOutput)
            let cFeatures = try native.readActivation(from: cOutput)
            maxStemArrayVsB = max(maxStemArrayVsB, Self.maxAbs(stemFeatures, bFeatures))
            maxStemArrayVsC = max(maxStemArrayVsC, Self.maxAbs(stemFeatures, cFeatures))
            let fullLabel = Self.topLabel(try fullArray.predict(normalizedRGB: sourcePreprocessed))
            let splitLabel = Self.topLabel(try tail.predict(stemActivation: stemFeatures))
            if fullLabel == splitLabel { fullArraySplitTailMatches += 1 }
            else { disagreements.append("\(frame.id): full=\(fullLabel ?? "nil") split=\(splitLabel ?? "nil")") }
        }
        XCTAssertLessThanOrEqual(maxStemArrayVsB, MobileNetV2OutputAgreement.referenceStemParityTolerance)
        XCTAssertLessThanOrEqual(maxStemArrayVsC, MobileNetV2OutputAgreement.referenceStemParityTolerance)
        let agreement = Double(fullArraySplitTailMatches) / Double(corpus.manifest.samples.count)
        print("FullArray/split-tail top-1 agreement: \(fullArraySplitTailMatches)/\(corpus.manifest.samples.count) = \(agreement)")
        if !disagreements.isEmpty { print("FullArray/split-tail disagreements: \(disagreements.joined(separator: ", "))") }
        XCTAssertGreaterThanOrEqual(agreement, MobileNetV2OutputAgreement.requiredTop1Agreement)
    }

    private static func maxAbs(_ lhs: [Float], _ rhs: [Float]) -> Double {
        guard lhs.count == rhs.count else { return .infinity }
        return zip(lhs, rhs).map { abs(Double($0 - $1)) }.max() ?? 0
    }

    private static func topLabel(_ probabilities: [String: Double]) -> String? {
        probabilities.max { $0.value < $1.value }?.key
    }
}
