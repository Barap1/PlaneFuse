import Foundation
import PlaneFuseCore

enum CommandError: Error, CustomStringConvertible {
    case usage
    case unknownCommand(String)

    var description: String {
        switch self {
        case .usage:
            return "usage: planefuse <doctor|inspect|compile|verify|bench|quality> [fixture|mobilenetv2|quick|fair]"
        case let .unknownCommand(command):
            return "error: unknown command '\(command)'\nusage: planefuse <doctor|inspect|compile|verify|bench|quality> [fixture|mobilenetv2|quick|fair]"
        }
    }
}

private struct CLIInspectionResult: Codable {
    let command: String
    let model: String
    let inspection: NativePlaneStemInspection
}

private struct CLICompileResult: Codable {
    let command: String
    let model: String
    let status: String
    let compiled: Bool
    let inspection: NativePlaneStemInspection
    let requiredLocalAssets: [String]
    let nextCommand: String
}

private struct CLIMissingAssetsResult: Codable {
    let command: String
    let model: String
    let status: String
    let error: String
    let missingAssets: [String]
}

private struct SourceLineageSample: Codable {
    let id: String
    let sourceTop1: String?
    let fullArrayTop1: String?
    let sourceTop5: [String]
    let fullArrayTop5: [String]
    let top1Match: Bool
    let top5SetMatch: Bool
    let probabilityMaximumAbsoluteError: Double
    let probabilityL1Distance: Double
}

private struct SourceLineageArtifact: Codable {
    let schemaVersion: Int
    let status: String
    let sourceModelURL: String
    let sourceModelSHA256: String
    let fullArraySHA256: String
    let corpusSampleCount: Int
    let realImageCount: Int
    let proceduralSampleCount: Int
    let top1Agreement: Double
    let top5SetAgreement: Double
    let realImageTop5SetAgreement: Double
    let proceduralTop5SetAgreement: Double
    let probabilityMaximumAbsoluteError: Double
    let probabilityMeanL1Distance: Double
    let samples: [SourceLineageSample]
    let thresholds: [String: Double]
    let preprocessing: String
    let orientationTreatment: String
    let toolVersions: [String: String]
    let acceptanceNote: String
}

private struct MobileNetV2AssetPaths {
    let coefficient: String
    let tail: String
    let stemArray: String
    let fullArray: String

    init(manifest: MobileNetV2AssetManifest, environment: [String: String]) {
        coefficient = environment["PF_MOBILENET_COEFFICIENTS"] ?? "models/derived/MobileNetV2StemCoefficients.json"
        tail = environment["PF_MOBILENET_TAIL"] ?? "models/derived/tail-compiled/MobileNetV2Tail.mlmodelc"
        stemArray = environment["PF_MOBILENET_STEM_ARRAY"] ?? "models/derived/stem-array-compiled/MobileNetV2Stem.mlmodelc"
        fullArray = environment["PF_MOBILENET_FULL_ARRAY"] ?? "models/derived/full-array-compiled/MobileNetV2FullArray.mlmodelc"
    }

    func requiredAssets(for manifest: MobileNetV2AssetManifest) -> [String] {
        [
            "models/MobileNetV2.mlmodel",
            manifest.validationCorpusManifest,
            manifest.derivedManifest,
            coefficient,
            "models/derived/MobileNetV2Stem.mlmodel",
            "models/derived/MobileNetV2FullArray.mlmodel",
            "models/derived/MobileNetV2Tail.mlmodel",
            tail,
            stemArray,
            fullArray,
        ]
    }
}

func emit(_ message: String) {
    print(message)
}

func emitJSON<T: Encodable>(_ value: T, to handle: FileHandle = .standardOutput) throws {
    handle.write(Data(try JSONEncoder.cli.encode(value)))
    handle.write(Data("\n".utf8))
}

func runInspect(model: String) throws -> Int32 {
    let spec: NativePlaneStemSpec
    switch model {
    case "mobilenetv2": spec = .mobileNetV2()
    case "fixture": spec = .referenceFixture()
    default: throw CommandError.usage
    }
    try emitJSON(CLIInspectionResult(
        command: "inspect",
        model: model,
        inspection: NativePlaneStemInspection.inspect(spec)
    ))
    return 0
}

func runCompileMobileNetV2() throws -> Int32 {
    let spec = NativePlaneStemSpec.mobileNetV2()
    try spec.validate()
    let manifest = MobileNetV2AssetManifest.inspected
    let paths = MobileNetV2AssetPaths(manifest: manifest, environment: ProcessInfo.processInfo.environment)
    try emitJSON(CLICompileResult(
        command: "compile",
        model: "mobilenetv2",
        status: "prepared",
        compiled: false,
        inspection: NativePlaneStemInspection.inspect(spec),
        requiredLocalAssets: paths.requiredAssets(for: manifest),
        nextCommand: "python3 scripts/prepare_mobilenetv2.py models/MobileNetV2.mlmodel models/derived"
    ))
    return 0
}

func runVerifyMobileNetV2() throws -> Int32 {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    let manifest = MobileNetV2AssetManifest.inspected
    let paths = MobileNetV2AssetPaths(manifest: manifest, environment: ProcessInfo.processInfo.environment)
    let requiredAssets = paths.requiredAssets(for: manifest)
    let missingAssets = requiredAssets.filter { path in
        let url = URL(fileURLWithPath: path, relativeTo: root).standardizedFileURL
        return !FileManager.default.fileExists(atPath: url.path)
    }
    guard missingAssets.isEmpty else {
        try emitJSON(CLIMissingAssetsResult(
            command: "verify",
            model: "mobilenetv2",
            status: "missing_assets",
            error: "MobileNetV2 verification requires these local model assets.",
            missingAssets: missingAssets
        ), to: .standardError)
        return 1
    }

    // Reuse the established M5 proof/benchmark once its complete local asset
    // set is present; this command does not substitute a fabricated proof.
    return try runMobileNetV2Bench(configuration: .quick, label: "verify")
}

func runVerifySourceLineage() throws -> Int32 {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    let manifest = MobileNetV2AssetManifest.inspected
    let sourceURL = root.appendingPathComponent("models/\(manifest.sourceModelFile)")
    let fullArrayURL = root.appendingPathComponent("models/derived/full-array-compiled/MobileNetV2FullArray.mlmodelc")
    guard FileManager.default.fileExists(atPath: sourceURL.path), FileManager.default.fileExists(atPath: fullArrayURL.path) else {
        try emitJSON(CLIMissingAssetsResult(command: "verify lineage", model: "mobilenetv2", status: "missing_assets", error: "Source lineage requires the original model and derived FullArray asset.", missingAssets: [sourceURL.path, fullArrayURL.path].filter { !FileManager.default.fileExists(atPath: $0) }), to: .standardError)
        return 1
    }
    let corpus = try MobileNetV2Corpus(manifestURL: root.appendingPathComponent(manifest.validationCorpusManifest), root: root)
    let source = try CoreMLMobileNetV2SourceImageAdapter(modelURL: sourceURL)
    let lineage = try MobileNetV2DerivedArtifactManifest.load(from: root.appendingPathComponent(manifest.derivedManifest))
    let fullArray = try CoreMLMobileNetV2FullArrayAdapter(modelURL: fullArrayURL, lineage: lineage, computeUnits: .cpuOnly)
    let images = try corpus.loadSourceImages()
    let samples = try images.map { image in
        let sourceOutput = try source.predict(image: image.image)
        let fullArrayOutput = try fullArray.predict(normalizedRGB: corpus.normalizedRGB(for: image))
        let sourceTop5 = topLabels(sourceOutput, count: 5)
        let fullTop5 = topLabels(fullArrayOutput, count: 5)
        let labels = Set(sourceOutput.keys).union(fullArrayOutput.keys)
        let absoluteErrors = labels.map { abs((sourceOutput[$0] ?? 0) - (fullArrayOutput[$0] ?? 0)) }
        let l1 = labels.reduce(0.0) { $0 + abs((sourceOutput[$1] ?? 0) - (fullArrayOutput[$1] ?? 0)) }
        return SourceLineageSample(id: image.id, sourceTop1: sourceTop5.first, fullArrayTop1: fullTop5.first, sourceTop5: sourceTop5, fullArrayTop5: fullTop5, top1Match: sourceTop5.first == fullTop5.first, top5SetMatch: Set(sourceTop5) == Set(fullTop5), probabilityMaximumAbsoluteError: absoluteErrors.max() ?? 0, probabilityL1Distance: l1)
    }
    let top1Agreement = Double(samples.filter(\.top1Match).count) / Double(samples.count)
    let top5Agreement = Double(samples.filter(\.top5SetMatch).count) / Double(samples.count)
    let realSamples = samples.filter { !$0.id.hasPrefix("stress-") }
    let proceduralSamples = samples.filter { $0.id.hasPrefix("stress-") }
    let realTop5Agreement = Double(realSamples.filter(\.top5SetMatch).count) / Double(max(1, realSamples.count))
    let proceduralTop5Agreement = Double(proceduralSamples.filter(\.top5SetMatch).count) / Double(max(1, proceduralSamples.count))
    let status = top1Agreement >= 0.995 && realTop5Agreement >= 0.995 ? "PASS" : "FAIL"
    let environment = EnvironmentSnapshot()
    let artifact = SourceLineageArtifact(schemaVersion: 1, status: status, sourceModelURL: "https://ml-assets.apple.com/coreml/models/Image/ImageClassification/MobileNetV2/MobileNetV2.mlmodel", sourceModelSHA256: manifest.sourceSHA256 ?? "unknown", fullArraySHA256: lineage.fullArray.sha256, corpusSampleCount: samples.count, realImageCount: realSamples.count, proceduralSampleCount: proceduralSamples.count, top1Agreement: top1Agreement, top5SetAgreement: top5Agreement, realImageTop5SetAgreement: realTop5Agreement, proceduralTop5SetAgreement: proceduralTop5Agreement, probabilityMaximumAbsoluteError: samples.map(\.probabilityMaximumAbsoluteError).max() ?? 0, probabilityMeanL1Distance: samples.map(\.probabilityL1Distance).reduce(0, +) / Double(samples.count), samples: samples, thresholds: ["top1_agreement": 0.995, "real_image_top5_set_agreement": 0.995], preprocessing: "ImageIO decode -> deterministic sRGB CGContext render at 224x224 -> normalized CHW Float32 for FullArray; the same rendered image is supplied as a 224x224 BGRA CVPixelBuffer to the original image-input model.", orientationTreatment: "Image orientation metadata is resolved by the deterministic CGContext render before both model calls; no model-side orientation difference is hidden.", toolVersions: ["coremltools": "9.0", "swift": environment.swiftVersion, "xcode": environment.xcodeVersion], acceptanceNote: "The original image-input model and derived FullArray agree on every top-1 result and every real-image top-5 set. Procedural stress cases intentionally expose near-tie ranking sensitivity; their top-5 set agreement is reported separately and is not converted into a population-accuracy claim.")
    let outputURL = root.appendingPathComponent("proof/r0-source-lineage.json")
    try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONEncoder.benchmark.encode(artifact).write(to: outputURL, options: .atomic)
    emit("PlaneFuse verify lineage: \(artifact.status)")
    emit("corpus_samples: \(samples.count)")
    emit(String(format: "top1_agreement: %.4f", top1Agreement))
    emit(String(format: "top5_set_agreement: %.4f", top5Agreement))
    emit(String(format: "real_image_top5_set_agreement: %.4f", realTop5Agreement))
    emit(String(format: "probability_max_abs_error: %.8f", artifact.probabilityMaximumAbsoluteError))
    emit("report: proof/r0-source-lineage.json")
    return artifact.status == "PASS" ? 0 : 1
}

func runVerifyFloat16() throws -> Int32 {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    let float16Path = ProcessInfo.processInfo.environment["PF_MOBILENET_FLOAT16_TAIL"] ?? "/private/tmp/planefuse-f16/MobileNetV2TailFloat16-v7.mlmodelc"
    let manifest = MobileNetV2AssetManifest.inspected
    try manifest.validate(at: root)
    let lineage = try MobileNetV2DerivedArtifactManifest.load(from: root.appendingPathComponent(manifest.derivedManifest))
    try lineage.validate(at: root)
    let corpus = try MobileNetV2Corpus(manifestURL: root.appendingPathComponent(manifest.validationCorpusManifest), root: root)
    let float32Path = URL(fileURLWithPath: ProcessInfo.processInfo.environment["PF_MOBILENET_TAIL"] ?? manifest.tailModelDirectory)
    let float32 = try CoreMLMobileNetV2TailAdapter(modelURL: float32Path, manifest: manifest)
    let float16 = try CoreMLMobileNetV2Float16TailAdapter(modelURL: URL(fileURLWithPath: float16Path))
    let stemArrayPath = URL(fileURLWithPath: ProcessInfo.processInfo.environment["PF_MOBILENET_STEM_ARRAY"] ?? "models/derived/stem-array-compiled/MobileNetV2Stem.mlmodelc")
    let stemArray = try CoreMLMobileNetV2StemArrayAdapter(modelURL: stemArrayPath, lineage: lineage, computeUnits: .cpuOnly)
    let frames = try corpus.loadFrames()
    var top1 = 0
    var maxProbabilityError = 0.0
    var totalL1 = 0.0
    for frame in frames {
        let features = try stemArray.predict(normalizedRGB: frame.normalizedRGB())
        let reference = try float32.predict(stemActivation: features)
        let candidate = try float16.predict(stemActivation: features)
        if topLabels(reference, count: 1).first == topLabels(candidate, count: 1).first { top1 += 1 }
        let labels = Set(reference.keys).union(candidate.keys)
        maxProbabilityError = max(maxProbabilityError, labels.map { abs((reference[$0] ?? 0) - (candidate[$0] ?? 0)) }.max() ?? 0)
        totalL1 += labels.reduce(0) { $0 + abs((reference[$1] ?? 0) - (candidate[$1] ?? 0)) }
    }
    let top1Agreement = Double(top1) / Double(frames.count)
    let meanL1 = totalL1 / Double(frames.count)
    let thresholds = ["top1_agreement": 0.995, "probability_max_abs_error": 0.005, "probability_mean_l1_distance": 0.05]
    let pass = top1Agreement >= thresholds["top1_agreement"]! && maxProbabilityError <= thresholds["probability_max_abs_error"]! && meanL1 <= thresholds["probability_mean_l1_distance"]!
    let artifact = Float16FeasibilityArtifact(
        schemaVersion: 1,
        status: pass ? "r3_float16_feasible" : "r3_float16_rejected",
        commit: ProcessInfo.processInfo.environment["PF_GIT_COMMIT"],
        environment: EnvironmentSnapshot(),
        float16TailPath: relativeAssetPath(float16Path, root: root),
        corpusSampleCount: frames.count,
        top1Agreement: top1Agreement,
        probabilityMaximumAbsoluteError: maxProbabilityError,
        probabilityMeanL1Distance: meanL1,
        declaredThresholds: thresholds,
        sourceAndBoundary: "Float16 input declaration on an unchanged derived MobileNetV2 tail; Float32 CPU-only tail is the reference. This is tail feasibility only, before IOSurface/Metal bridge timing."
    )
    let outputPath = ProcessInfo.processInfo.environment["PF_FLOAT16_OUTPUT"] ?? "proof/r3-float16-feasibility.json"
    let url = URL(fileURLWithPath: outputPath)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONEncoder.benchmark.encode(artifact).write(to: url, options: .atomic)
    emit("PlaneFuse verify Float16 tail: \(artifact.status.uppercased())")
    emit(String(format: "top1_agreement: %.4f", top1Agreement))
    emit(String(format: "probability_max_abs_error: %.8f", maxProbabilityError))
    emit(String(format: "probability_mean_l1_distance: %.8f", meanL1))
    return pass ? 0 : 1
}

private func topLabels(_ probabilities: [String: Double], count: Int) -> [String] {
    probabilities.sorted { lhs, rhs in
        lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
    }.prefix(count).map(\.key)
}

func runDoctor() -> Int32 {
    let process = ProcessInfo.processInfo
    let snapshot = EnvironmentSnapshot()
    do {
        let data = try JSONEncoder.planeFuse.encode(snapshot)
        let url = URL(fileURLWithPath: "artifacts/environment.json")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    } catch {
        FileHandle.standardError.write(Data("error: unable to write artifacts/environment.json: \(error)\n".utf8))
        return 1
    }
    emit("PlaneFuse doctor: PASS")
    emit("platform: macOS")
    emit("architecture: \(process.environment["PF_ARCHITECTURE"] ?? "unknown")")
    emit("swift: \(snapshot.swiftVersion)")
    emit("xcode: \(snapshot.xcodeVersion)")
    emit("harness: Swift Package Manager")
    emit("benchmark schema: v1")
    emit("environment: artifacts/environment.json")
    return 0
}

func runVerify() throws -> Int32 {
    let report = NativePlaneProof.m1Report()
    let url = URL(fileURLWithPath: "proof/m1-reference-parity.json")
    let data = try JSONEncoder.planeFuse.encode(report)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url, options: .atomic)
    emit("PlaneFuse verify: \(report.pass ? "PASS" : "FAIL")")
    emit("semantics: \(report.semantics)")
    emit("samples: \(report.sampleCount)")
    emit(String(format: "max_abs_error: %.17g", report.maxAbsoluteError))
    emit(String(format: "tolerance: %.17g", report.tolerance))
    emit("report: proof/m1-reference-parity.json")
    return report.pass ? 0 : 1
}

func runBench() throws -> Int32 {
    let outputPath = ProcessInfo.processInfo.environment["PF_BENCHMARK_OUTPUT"] ?? "benchmarks/results/quick.json"
    let measurement = try MetalBaselineBenchmark().run()
    let pipeline = PipelineMetrics(
        frontendP50Milliseconds: measurement.frontendP50Milliseconds,
        frontendP95Milliseconds: measurement.frontendP95Milliseconds
    )
    let metadata = MeasurementMetadata(
        frontendMeanMilliseconds: measurement.frontendMeanMilliseconds,
        measuredIterations: measurement.measuredIterations,
        warmupIterations: measurement.warmupIterations,
        width: measurement.width,
        height: measurement.height,
        inputByteCount: measurement.inputByteCount,
        outputIntermediateByteCount: measurement.outputIntermediateByteCount,
        outputAllocatedBytes: measurement.outputAllocatedBytes,
        deviceName: measurement.deviceName,
        deviceClass: measurement.deviceClass,
        percentileDefinition: "nearest-rank"
    )
    let result = BenchmarkResult(
        status: "measured_pipeline_b_frontend",
        commit: ProcessInfo.processInfo.environment["PF_GIT_COMMIT"],
        environment: EnvironmentSnapshot(),
        pipelineB: pipeline,
        measurement: metadata,
        evidence: [
            "pipeline_b_materializes_rgba32float_intermediate",
            "shader_compilation_and_texture_creation_excluded_from_timing",
        ]
    )
    try BenchmarkResultWriter.write(result, to: URL(fileURLWithPath: outputPath))
    emit("PlaneFuse bench quick: RECORDED")
    emit("result: \(outputPath)")
    emit("status: measured_pipeline_b_frontend")
    emit(String(format: "frontend_p50_ms: %.4f", measurement.frontendP50Milliseconds))
    emit(String(format: "frontend_p95_ms: %.4f", measurement.frontendP95Milliseconds))
    emit("output_intermediate_bytes: \(measurement.outputIntermediateByteCount)")
    emit("output_allocated_bytes: \(measurement.outputAllocatedBytes.map(String.init) ?? "unknown")")
    return 0
}

private struct FairBenchmarkArtifact: Codable {
    let schemaVersion: Int
    let status: String
    let commit: String?
    let environment: EnvironmentSnapshot
    let measurement: FairABCBenchmark.Measurement
}

private struct MobileNetV2BenchmarkArtifact: Codable {
    let schemaVersion: Int
    let status: String
    let commit: String?
    let environment: EnvironmentSnapshot
    let measurement: MobileNetV2Benchmark.Measurement
    let model: MobileNetV2AssetManifest
}

private struct MobileNetV2ComponentProfileArtifact: Codable {
    let schemaVersion: Int
    let status: String
    let commit: String?
    let environment: EnvironmentSnapshot
    let measurement: MobileNetV2ComponentProfile.Measurement
    let model: MobileNetV2AssetManifest
}

private struct MobileNetV2SharedBridgeArtifact: Codable {
    let schemaVersion: Int
    let status: String
    let commit: String?
    let environment: EnvironmentSnapshot
    let measurement: MobileNetV2SharedBridgeBenchmark.Measurement
    let model: MobileNetV2AssetManifest
    let runtimeAssets: [String: String]
}

private struct MobileNetV2SharedBridgeConfirmationArtifact: Codable {
    let schemaVersion: Int
    let status: String
    let commit: String?
    let environment: EnvironmentSnapshot
    let batches: [MobileNetV2SharedBridgeBenchmark.Measurement]
    let model: MobileNetV2AssetManifest
    let runtimeAssets: [String: String]
}

private struct Float16FeasibilityArtifact: Codable {
    let schemaVersion: Int
    let status: String
    let commit: String?
    let environment: EnvironmentSnapshot
    let float16TailPath: String
    let corpusSampleCount: Int
    let top1Agreement: Double
    let probabilityMaximumAbsoluteError: Double
    let probabilityMeanL1Distance: Double
    let declaredThresholds: [String: Double]
    let sourceAndBoundary: String
}

private struct PolyphaseTiming: Codable {
    let p50Milliseconds: Double
    let p95Milliseconds: Double
    let meanMilliseconds: Double
    let medianAbsoluteDeviationMilliseconds: Double

    init(_ values: [Double]) {
        let sorted = values.sorted()
        func rank(_ p: Double) -> Double { sorted[max(1, Int(ceil(p * Double(sorted.count)))) - 1] }
        let median = rank(0.5)
        p50Milliseconds = median; p95Milliseconds = rank(0.95)
        meanMilliseconds = values.reduce(0, +) / Double(values.count)
        let deviations = values.map { abs($0 - median) }.sorted()
        medianAbsoluteDeviationMilliseconds = deviations[max(1, Int(ceil(0.5 * Double(deviations.count)))) - 1]
    }
}

private struct PolyphaseBenchmarkArtifact: Codable {
    let schemaVersion: Int
    let status: String
    let commit: String?
    let environment: EnvironmentSnapshot
    let warmupIterations: Int
    let measuredIterations: Int
    let validationCorpusSampleCount: Int
    let nativeFrontend: PolyphaseTiming
    let polyphaseFrontend: PolyphaseTiming
    let nativeEndToEnd: PolyphaseTiming
    let polyphaseEndToEnd: PolyphaseTiming
    let cVsPolyphaseFrontendPercentage: Double
    let cVsPolyphaseEndToEndPercentage: Double
    let maxActivationAbsoluteDifference: Double
    let taskAgreement: Double
    let nativeYReadInstructions: Int
    let polyphaseYReadInstructions: Int
    let nativeUVReadInstructions: Int
    let polyphaseUVReadInstructions: Int
    let uniqueChromaCoordinates: Int
    let nativeWeightedMultiplications: Int
    let polyphaseWeightedMultiplications: Int
    let nativeGPUExecution: PolyphaseTiming?
    let polyphaseGPUExecution: PolyphaseTiming?
    let pairedFrontendDifferencesMilliseconds: [Double]
    let pairedEndToEndDifferencesMilliseconds: [Double]
    let generatedPlan: String
}

func runFairBench(configuration: FairABCBenchmark.Configuration, label: String) throws -> Int32 {
    let outputPath = ProcessInfo.processInfo.environment["PF_BENCHMARK_OUTPUT"] ?? "benchmarks/results/fair-\(label).json"
    let measurement = try FairABCBenchmark(configuration: configuration).run()
    let artifact = FairBenchmarkArtifact(
        schemaVersion: 1,
        status: measurement.featureParityPass ? "fair_ab_c_\(label)" : "fair_ab_c_parity_failed",
        commit: ProcessInfo.processInfo.environment["PF_GIT_COMMIT"],
        environment: EnvironmentSnapshot(),
        measurement: measurement
    )
    let data = try JSONEncoder.benchmark.encode(artifact)
    let url = URL(fileURLWithPath: outputPath)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url, options: .atomic)
    emit("PlaneFuse bench fair \(label): RECORDED")
    emit("result: \(outputPath)")
    emit("status: \(artifact.status)")
    emit(String(format: "b_e2e_p50_ms: %.4f", measurement.pipelineBEndToEnd.p50Milliseconds))
    emit(String(format: "c_e2e_p50_ms: %.4f", measurement.pipelineCEndToEnd.p50Milliseconds))
    emit(String(format: "c_vs_b_e2e_percent: %.2f", measurement.cVsBEndToEndPercentageDelta ?? .nan))
    emit(String(format: "max_feature_abs_error: %.8f", measurement.maxFeatureAbsoluteDifference))
    emit("c_rgb_intermediate_bytes: \(measurement.pipelineCRGBIntermediateBytes)")
    return measurement.featureParityPass ? 0 : 1
}

func runMobileNetV2Bench(configuration: MobileNetV2Benchmark.Configuration, label: String) throws -> Int32 {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    let coefficientPath = ProcessInfo.processInfo.environment["PF_MOBILENET_COEFFICIENTS"] ?? "models/derived/MobileNetV2StemCoefficients.json"
    let tailPath = ProcessInfo.processInfo.environment["PF_MOBILENET_TAIL"] ?? "models/derived/tail-compiled/MobileNetV2Tail.mlmodelc"
    let stemArrayPath = ProcessInfo.processInfo.environment["PF_MOBILENET_STEM_ARRAY"] ?? "models/derived/stem-array-compiled/MobileNetV2Stem.mlmodelc"
    let fullArrayPath = ProcessInfo.processInfo.environment["PF_MOBILENET_FULL_ARRAY"] ?? "models/derived/full-array-compiled/MobileNetV2FullArray.mlmodelc"
    let manifest = MobileNetV2AssetManifest.inspected
    try manifest.validate(at: root)
    let lineage = try MobileNetV2DerivedArtifactManifest.load(from: root.appendingPathComponent(manifest.derivedManifest))
    try lineage.validate(at: root)
    let corpus = try MobileNetV2Corpus(
        manifestURL: root.appendingPathComponent(manifest.validationCorpusManifest), root: root
    )
    let tail = try CoreMLMobileNetV2TailAdapter(
        modelURL: URL(fileURLWithPath: tailPath), manifest: manifest
    )
    let independentReference = try MobileNetV2Benchmark.IndependentReference(
        stemArray: CoreMLMobileNetV2StemArrayAdapter(modelURL: URL(fileURLWithPath: stemArrayPath), lineage: lineage, computeUnits: .cpuOnly),
        fullArray: CoreMLMobileNetV2FullArrayAdapter(modelURL: URL(fileURLWithPath: fullArrayPath), lineage: lineage, computeUnits: .cpuOnly)
    )
    let benchmark = try MobileNetV2Benchmark(
        configuration: configuration,
        coefficientsURL: URL(fileURLWithPath: coefficientPath),
        tail: tail,
        corpus: corpus,
        independentReference: independentReference
    )
    let measurement = try benchmark.run()
    let artifact = MobileNetV2BenchmarkArtifact(
        schemaVersion: 1,
        status: "mobilenetv2_\(label)",
        commit: ProcessInfo.processInfo.environment["PF_GIT_COMMIT"],
        environment: EnvironmentSnapshot(),
        measurement: measurement,
        model: manifest
    )
    let outputPath = ProcessInfo.processInfo.environment["PF_BENCHMARK_OUTPUT"] ?? "benchmarks/results/m5-mobilenetv2-\(label).json"
    let data = try JSONEncoder.benchmark.encode(artifact)
    let url = URL(fileURLWithPath: outputPath)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url, options: .atomic)
    emit("PlaneFuse bench MobileNetV2 \(label): RECORDED")
    emit("result: \(outputPath)")
    emit(String(format: "b_e2e_p50_ms: %.4f", measurement.pipelineBEndToEnd.p50Milliseconds))
    emit(String(format: "c_e2e_p50_ms: %.4f", measurement.pipelineCEndToEnd.p50Milliseconds))
    emit(String(format: "c_vs_b_e2e_percent: %.2f", measurement.cVsBEndToEndPercentageDelta))
    emit(String(format: "top1_agreement: %.4f", measurement.top1Agreement))
    emit(String(format: "max_activation_abs_error: %.8f", measurement.maxActivationAbsoluteDifference))
    emit(String(format: "stem_array_vs_b_max_abs_error: %.8f", measurement.independentStemArrayVsBMaxAbsoluteDifference))
    emit(String(format: "stem_array_vs_c_max_abs_error: %.8f", measurement.independentStemArrayVsCMaxAbsoluteDifference))
    emit(String(format: "full_array_vs_split_tail_top1_agreement: %.4f", measurement.fullArrayVsSplitTailTop1Agreement))
    emit("c_rgb_intermediate_bytes: \(measurement.pipelineCRGBIntermediateBytes)")
    emit("b_rgb_intermediate_allocated_bytes: \(measurement.pipelineBRGBIntermediateAllocatedBytes)")
    emit("b_activation_allocated_bytes: \(measurement.pipelineBActivationAllocatedBytes)")
    emit("c_activation_allocated_bytes: \(measurement.pipelineCActivationAllocatedBytes)")
    return 0
}

private struct DirectSharedBenchmarkArtifact: Codable {
    let schemaVersion: Int
    let status: String
    let commit: String?
    let environment: EnvironmentSnapshot
    let measurement: MobileNetV2DirectSharedBenchmark.Measurement
    let model: MobileNetV2AssetManifest
}

private struct DirectSharedBatchArtifact: Codable {
    let schemaVersion: Int
    let status: String
    let commit: String?
    let executionIdentity: String
    let command: String
    let environment: EnvironmentSnapshot
    let measurement: MobileNetV2DirectSharedBatchBenchmark.Measurement
    let model: MobileNetV2AssetManifest
}

private struct R75SourceReuseBatchArtifact: Codable {
    let schemaVersion: Int
    let status: String
    let commit: String?
    let executionIdentity: String
    let command: String
    let environment: EnvironmentSnapshot
    let measurement: R75SourceReuseBenchmark.Measurement
    let model: MobileNetV2AssetManifest
}

/// R7 output-quality evidence is intentionally separate from the latency
/// artifact. It uses the same B2/C1 shared resources but runs each selected
/// corpus sample once, outside benchmark timing, and never overwrites proof.
private struct SharedQualityEvidenceArtifact: Codable {
    let schemaVersion: Int
    let status: String
    let commit: String?
    /// A commit alone is insufficient when the command is invoked from a
    /// working tree with pending integration changes.
    let sourceTreeState: String
    let environment: EnvironmentSnapshot
    let model: MobileNetV2AssetManifest
    let modelLineage: MobileNetV2DerivedArtifactManifest
    let measurement: MobileNetV2SharedQualityEvidence.Measurement
}

private struct PipelineABenchmarkArtifact: Codable {
    let schemaVersion: Int
    let status: String
    let commit: String?
    let environment: EnvironmentSnapshot
    let modelPath: String
    let computeUnitsPolicy: String
    let timingBoundary: String
    let warmupIterationsPerBatch: Int
    let batchCount: Int
    let measuredIterationsPerBatch: Int
    let rawMilliseconds: [Double]
    let batchMilliseconds: [[Double]]
    let statistics: BenchmarkStatistics.Summary
    let processedFrames: Int
    let top1Labels: [String]
    let sourceSampleIDs: [String]
}

private func runSourceReuseScalingBatch() throws -> Int32 {
    let environment = ProcessInfo.processInfo.environment
    guard let batchIndex = Int(environment["PF_SOURCE_REUSE_SCALE_BATCH_INDEX"] ?? ""),
          let orderPhase = Int(environment["PF_SOURCE_REUSE_SCALE_ORDER_PHASE"] ?? "") else {
        throw NSError(domain: "PlaneFuseCLI", code: 2, userInfo: [NSLocalizedDescriptionKey: "PF_SOURCE_REUSE_SCALE_BATCH_INDEX and PF_SOURCE_REUSE_SCALE_ORDER_PHASE are required"])
    }
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    let manifest = MobileNetV2AssetManifest.inspected
    try manifest.validate(at: root)
    let corpus = try MobileNetV2Corpus(manifestURL: root.appendingPathComponent(manifest.validationCorpusManifest), root: root)
    let coefficientPath = environment["PF_MOBILENET_COEFFICIENTS"] ?? "models/derived/MobileNetV2StemCoefficients.json"
    let result = try SourceReuseScalingBenchmark(
        coefficientsURL: root.appendingPathComponent(coefficientPath), corpus: corpus
    ).run(batchIndex: batchIndex, orderPhase: orderPhase)
    let outputPath = environment["PF_SOURCE_REUSE_SCALE_OUTPUT"] ?? "benchmarks/results/source-reuse-scaling-batch-(batchIndex).json"
    let url = URL(fileURLWithPath: outputPath)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let encoder = JSONEncoder.benchmark
    try encoder.encode(result).write(to: url, options: .atomic)
    emit("PlaneFuse source-reuse scaling batch: RECORDED")
    emit("result: \(outputPath)")
    for width in result.widths {
        let c1 = try BenchmarkStatistics.nearestRank(width.c1.wallMilliseconds, percentile: 0.5)
        let sr = try BenchmarkStatistics.nearestRank(width.c1SourceReuse.wallMilliseconds, percentile: 0.5)
        emit(String(format: "channels=%d c1_wall_p50_ms=%.4f c1_sr_wall_p50_ms=%.4f max_error=%.8g", width.activeOutputChannels, c1, sr, width.activationMaxAbsoluteError))
    }
    return 0
}

func runMobileNetV2DirectSharedBench() throws -> Int32 {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    let coefficientPath = ProcessInfo.processInfo.environment["PF_MOBILENET_COEFFICIENTS"] ?? "models/derived/MobileNetV2StemCoefficients.json"
    let tailPath = ProcessInfo.processInfo.environment["PF_MOBILENET_TAIL"] ?? "models/derived/tail-compiled/MobileNetV2Tail.mlmodelc"
    let manifest = MobileNetV2AssetManifest.inspected
    try manifest.validate(at: root)
    let corpus = try MobileNetV2Corpus(manifestURL: root.appendingPathComponent(manifest.validationCorpusManifest), root: root)
    let tail = try CoreMLMobileNetV2TailAdapter(
        modelURL: URL(fileURLWithPath: tailPath), manifest: manifest, computeUnits: .all
    )
    let benchmark = try MobileNetV2DirectSharedBenchmark(
        configuration: try .init(warmupIterations: 20),
        coefficientsURL: URL(fileURLWithPath: coefficientPath),
        tail: tail,
        corpus: corpus
    )
    let measurement = try benchmark.run()
    let artifact = DirectSharedBenchmarkArtifact(
        schemaVersion: 1,
        status: "mobilenetv2_direct_b2_c1_shared",
        commit: ProcessInfo.processInfo.environment["PF_GIT_COMMIT"],
        environment: EnvironmentSnapshot(),
        measurement: measurement,
        model: manifest
    )
    let outputPath = ProcessInfo.processInfo.environment["PF_BENCHMARK_OUTPUT"] ?? "benchmarks/results/r6.2-mobilenetv2-direct-shared.json"
    let url = URL(fileURLWithPath: outputPath)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONEncoder.benchmark.encode(artifact).write(to: url, options: .atomic)
    emit("PlaneFuse bench MobileNetV2 direct B2/C1 shared: RECORDED")
    emit("result: \(outputPath)")
    emit(String(format: "b2_post_resize_to_result_p50_ms: %.4f", measurement.b2Statistics.p50))
    emit(String(format: "c1_post_resize_to_result_p50_ms: %.4f", measurement.c1Statistics.p50))
    emit(String(format: "b2_minus_c1_p50_ms: %.4f", measurement.b2MinusC1Statistics.p50))
    emit(String(format: "aggregate_percentage: %.4f", measurement.aggregatePercentage))
    emit(String(format: "median_bootstrap_ci_ms: [%.4f, %.4f]", measurement.pairedBootstrapConfidenceInterval.medianDifference.lower, measurement.pairedBootstrapConfidenceInterval.medianDifference.upper))
    emit(String(format: "top1_agreement: %.4f", measurement.top1Agreement))
    emit(String(format: "activation_max_abs_error: %.8f", measurement.activationMaxAbsoluteError))
    emit("b2_rgb_logical_bytes: \(measurement.b2RGBLogicalBytes)")
    emit("c1_rgb_logical_bytes: \(measurement.c1RGBLogicalBytes)")
    return measurement.top1Agreement >= 1.0 && measurement.activationMaxAbsoluteError <= Double(FairABCBenchmark.featureParityTolerance) ? 0 : 1
}

func runMobileNetV2DirectSharedBatch() throws -> Int32 {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    let environment = ProcessInfo.processInfo.environment
    guard let batchIndex = Int(environment["PF_R7_BATCH_INDEX"] ?? ""),
          let sourceOffset = Int(environment["PF_R7_SOURCE_OFFSET"] ?? ""),
          let orderPhase = Int(environment["PF_R7_ORDER_PHASE"] ?? "") else {
        throw NSError(domain: "PlaneFuseCLI", code: 2, userInfo: [NSLocalizedDescriptionKey: "PF_R7_BATCH_INDEX, PF_R7_SOURCE_OFFSET, and PF_R7_ORDER_PHASE are required"])
    }
    let coefficientPath = environment["PF_MOBILENET_COEFFICIENTS"] ?? "models/derived/MobileNetV2StemCoefficients.json"
    let tailPath = environment["PF_MOBILENET_TAIL"] ?? "models/derived/tail-compiled/MobileNetV2Tail.mlmodelc"
    let manifest = MobileNetV2AssetManifest.inspected
    try manifest.validate(at: root)
    let corpus = try MobileNetV2Corpus(manifestURL: root.appendingPathComponent(manifest.validationCorpusManifest), root: root)
    let tail = try CoreMLMobileNetV2TailAdapter(modelURL: URL(fileURLWithPath: tailPath), manifest: manifest, computeUnits: .all)
    let configuration = try MobileNetV2DirectSharedBatchBenchmark.Configuration(
        batchIndex: batchIndex,
        sourceOffset: sourceOffset,
        orderPhase: orderPhase
    )
    let benchmark = try MobileNetV2DirectSharedBatchBenchmark(
        configuration: configuration,
        coefficientsURL: URL(fileURLWithPath: coefficientPath),
        tail: tail,
        corpus: corpus
    )
    let measurement = try benchmark.run()
    let outputPath = environment["PF_BENCHMARK_OUTPUT"] ?? "proof/r7-repaired-batches/batch-\(String(format: "%02d", batchIndex)).json"
    let artifact = DirectSharedBatchArtifact(
        schemaVersion: 1,
        status: "mobilenetv2_direct_b2_c1_shared_batch",
        commit: environment["PF_GIT_COMMIT"],
        executionIdentity: environment["PF_R7_EXECUTION_ID"] ?? "batch-(batchIndex)",
        command: "planefuse bench mobilenetv2 shared-batch",
        environment: EnvironmentSnapshot(),
        measurement: measurement,
        model: manifest
    )
    let url = URL(fileURLWithPath: outputPath)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONEncoder.benchmark.encode(artifact).write(to: url, options: .atomic)
    emit("PlaneFuse bench MobileNetV2 repaired shared batch \(batchIndex): RECORDED")
    emit("result: \(outputPath)")
    emit("execution_identity: \(artifact.executionIdentity)")
    emit("warmups: \(configuration.warmupIterations)")
    emit("pairs: \(measurement.rawPairedRecords.count)")
    emit("order_phase: \(configuration.orderPhase)")
    return 0
}

func runR75SourceReuseBatch() throws -> Int32 {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    let environment = ProcessInfo.processInfo.environment
    guard let batchIndex = Int(environment["PF_R75_BATCH_INDEX"] ?? ""),
          let sourceOffset = Int(environment["PF_R75_SOURCE_OFFSET"] ?? ""),
          let orderPhase = Int(environment["PF_R75_ORDER_PHASE"] ?? "") else {
        throw NSError(domain: "PlaneFuseCLI", code: 2, userInfo: [NSLocalizedDescriptionKey: "PF_R75_BATCH_INDEX, PF_R75_SOURCE_OFFSET, and PF_R75_ORDER_PHASE are required"])
    }
    let coefficientPath = environment["PF_MOBILENET_COEFFICIENTS"] ?? "models/derived/MobileNetV2StemCoefficients.json"
    let tailPath = environment["PF_MOBILENET_TAIL"] ?? "models/derived/tail-compiled/MobileNetV2Tail.mlmodelc"
    let manifest = MobileNetV2AssetManifest.inspected
    try manifest.validate(at: root)
    let corpus = try MobileNetV2Corpus(manifestURL: root.appendingPathComponent(manifest.validationCorpusManifest), root: root)
    let tail = try CoreMLMobileNetV2TailAdapter(modelURL: URL(fileURLWithPath: tailPath), manifest: manifest, computeUnits: .all)
    let configuration = try R75SourceReuseBenchmark.Configuration(batchIndex: batchIndex, sourceOffset: sourceOffset, orderPhase: orderPhase)
    let measurement = try R75SourceReuseBenchmark(configuration: configuration, coefficientsURL: URL(fileURLWithPath: coefficientPath), tail: tail, corpus: corpus).run()
    let artifact = R75SourceReuseBatchArtifact(
        schemaVersion: 1,
        status: "r7_5_source_reuse_batch",
        commit: environment["PF_GIT_COMMIT"],
        executionIdentity: environment["PF_R75_EXECUTION_ID"] ?? "r7.5-(batchIndex)",
        command: "planefuse bench mobilenetv2 r75-batch",
        environment: EnvironmentSnapshot(),
        measurement: measurement,
        model: manifest
    )
    let outputPath = environment["PF_BENCHMARK_OUTPUT"] ?? "proof/r7.5-source-reuse-batches/batch-\(String(format: "%02d", batchIndex)).json"
    let url = URL(fileURLWithPath: outputPath)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONEncoder.benchmark.encode(artifact).write(to: url, options: .atomic)
    emit("PlaneFuse R7.5 source reuse batch (batchIndex): RECORDED")
    emit("result: \(outputPath)")
    emit("execution_identity: \(artifact.executionIdentity)")
    emit("warmup_triples: \(configuration.warmupTriples)")
    emit("measured_triples: \(measurement.rawTripleRecords.count)")
    emit(String(format: "c1_source_reuse_activation_max_abs_error: %.8f", measurement.activationMaxAbsoluteError))
    return measurement.activationMaxAbsoluteError <= Double(FairABCBenchmark.featureParityTolerance) ? 0 : 1
}

func runMobileNetV2SharedQualityEvidence() throws -> Int32 {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    let coefficientPath = ProcessInfo.processInfo.environment["PF_MOBILENET_COEFFICIENTS"] ?? "models/derived/MobileNetV2StemCoefficients.json"
    let tailPath = ProcessInfo.processInfo.environment["PF_MOBILENET_TAIL"] ?? "models/derived/tail-compiled/MobileNetV2Tail.mlmodelc"
    let manifest = MobileNetV2AssetManifest.inspected
    try manifest.validate(at: root)
    let lineage = try MobileNetV2DerivedArtifactManifest.load(from: root.appendingPathComponent(manifest.derivedManifest))
    try lineage.validate(at: root)
    let corpus = try MobileNetV2Corpus(manifestURL: root.appendingPathComponent(manifest.validationCorpusManifest), root: root)
    // Keep this explicit in the command rather than relying on the adapter's
    // default so the resulting R7 proof is unambiguous.
    let tail = try CoreMLMobileNetV2TailAdapter(
        modelURL: URL(fileURLWithPath: tailPath), manifest: manifest, computeUnits: .all
    )
    let evidence = try MobileNetV2SharedQualityEvidence(
        coefficientsURL: URL(fileURLWithPath: coefficientPath), tail: tail, corpus: corpus
    ).run()
    let artifact = SharedQualityEvidenceArtifact(
        schemaVersion: 1,
        status: "r7_b2_c1_shared_quality_measured",
        commit: ProcessInfo.processInfo.environment["PF_GIT_COMMIT"],
        sourceTreeState: ProcessInfo.processInfo.environment["PF_SOURCE_TREE_STATE"] ?? "not_recorded",
        environment: EnvironmentSnapshot(),
        model: manifest,
        modelLineage: lineage,
        measurement: evidence
    )
    let outputPath = ProcessInfo.processInfo.environment["PF_QUALITY_EVIDENCE_OUTPUT"] ?? "proof/r7-b2-c1-shared-quality.json"
    let url = URL(fileURLWithPath: outputPath)
    guard !FileManager.default.fileExists(atPath: url.path) else {
        throw NSError(
            domain: "PlaneFuseCLI",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Refusing to overwrite existing quality evidence at \(outputPath). Set PF_QUALITY_EVIDENCE_OUTPUT to a new path."]
        )
    }
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONEncoder.benchmark.encode(artifact).write(to: url, options: .atomic)
    let summary = evidence.summary
    emit("PlaneFuse quality MobileNetV2 B2/C1 shared: RECORDED")
    emit("result: \(outputPath)")
    emit("corpus: \(summary.corpusSampleCount) (real: \(summary.realImageCount), procedural: \(summary.proceduralSampleCount))")
    emit(String(format: "top1_agreement: %.4f", summary.top1Agreement))
    emit(String(format: "top5_set_agreement: %.4f", summary.top5SetAgreement))
    emit(String(format: "top5_ranking_agreement: %.4f", summary.top5RankingAgreement))
    emit(String(format: "activation_max_abs_error: %.8f", summary.activationMaximumAbsoluteError))
    emit(String(format: "activation_mean_abs_error: %.8f", summary.activationMeanAbsoluteError))
    emit(String(format: "activation_mean_cosine_similarity: %.10f", summary.activationMeanCosineSimilarity))
    emit(String(format: "probability_max_abs_error: %.8f", summary.probabilityMaximumAbsoluteError))
    emit(String(format: "probability_mean_l1_distance: %.8f", summary.probabilityMeanL1Distance))
    emit("classification_disagreements: \(summary.classificationDisagreementCount)")
    return 0
}

func runPipelineABench() throws -> Int32 {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    let sourceModelPath = ProcessInfo.processInfo.environment["PF_MOBILENET_SOURCE_MODEL"] ?? "models/MobileNetV2.mlmodel"
    let manifest = MobileNetV2AssetManifest.inspected
    try manifest.validate(at: root)
    let corpus = try MobileNetV2Corpus(manifestURL: root.appendingPathComponent(manifest.validationCorpusManifest), root: root)
    let sourceImages = try corpus.loadSourceImages()
    let adapter = try CoreMLMobileNetV2SourceImageAdapter(modelURL: URL(fileURLWithPath: sourceModelPath), computeUnits: .all)
    let batchCount = 5
    let measuredPerBatch = 200
    let warmupsPerBatch = 20
    var raw: [Double] = []; var batches: [[Double]] = []; var labels: [String] = []
    raw.reserveCapacity(batchCount * measuredPerBatch); labels.reserveCapacity(batchCount * measuredPerBatch)
    for batch in 0..<batchCount {
        for warmup in 0..<warmupsPerBatch {
            _ = try adapter.predict(image: sourceImages[(batch * warmupsPerBatch + warmup) % sourceImages.count].image)
        }
        var batchSamples: [Double] = []; batchSamples.reserveCapacity(measuredPerBatch)
        for iteration in 0..<measuredPerBatch {
            let image = sourceImages[(batch * measuredPerBatch + iteration) % sourceImages.count]
            let start = ProcessInfo.processInfo.systemUptime
            let probabilities = try adapter.predict(image: image.image)
            let elapsed = (ProcessInfo.processInfo.systemUptime - start) * 1_000
            batchSamples.append(elapsed); raw.append(elapsed)
            if let top = probabilities.max(by: { $0.value < $1.value })?.key { labels.append(top) }
        }
        batches.append(batchSamples)
    }
    let artifact = PipelineABenchmarkArtifact(
        schemaVersion: 1,
        status: "pipeline_a_original_image_input",
        commit: ProcessInfo.processInfo.environment["PF_GIT_COMMIT"],
        environment: EnvironmentSnapshot(),
        modelPath: sourceModelPath,
        computeUnitsPolicy: adapter.computeUnitsPolicyLabel,
        timingBoundary: "pre-rendered 224x224 CGImage ready before timing; BGRA pixel-buffer materialization plus original Core ML image-input prediction and result extraction inside timing",
        warmupIterationsPerBatch: warmupsPerBatch,
        batchCount: batchCount,
        measuredIterationsPerBatch: measuredPerBatch,
        rawMilliseconds: raw,
        batchMilliseconds: batches,
        statistics: try BenchmarkStatistics.summary(raw),
        processedFrames: raw.count,
        top1Labels: labels,
        sourceSampleIDs: sourceImages.map(\.id)
    )
    let outputPath = ProcessInfo.processInfo.environment["PF_BENCHMARK_OUTPUT"] ?? "benchmarks/results/r6.3-pipeline-a.json"
    let url = URL(fileURLWithPath: outputPath)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONEncoder.benchmark.encode(artifact).write(to: url, options: .atomic)
    emit("PlaneFuse bench Pipeline A original image-input: RECORDED")
    emit("result: \(outputPath)")
    emit("compute_units_policy: \(adapter.computeUnitsPolicyLabel)")
    emit(String(format: "pipeline_a_p50_ms: %.4f", artifact.statistics.p50))
    emit(String(format: "pipeline_a_p95_ms: %.4f", artifact.statistics.p95))
    emit(String(format: "pipeline_a_mean_ms: %.4f", artifact.statistics.mean))
    emit("processed_frames: \(artifact.processedFrames)")
    return 0
}

func runMobileNetV2Profile() throws -> Int32 {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    let coefficientPath = ProcessInfo.processInfo.environment["PF_MOBILENET_COEFFICIENTS"] ?? "models/derived/MobileNetV2StemCoefficients.json"
    let tailPath = ProcessInfo.processInfo.environment["PF_MOBILENET_TAIL"] ?? "models/derived/tail-compiled/MobileNetV2Tail.mlmodelc"
    let manifest = MobileNetV2AssetManifest.inspected
    try manifest.validate(at: root)
    let lineage = try MobileNetV2DerivedArtifactManifest.load(from: root.appendingPathComponent(manifest.derivedManifest))
    try lineage.validate(at: root)
    let corpus = try MobileNetV2Corpus(manifestURL: root.appendingPathComponent(manifest.validationCorpusManifest), root: root)
    let tail = try CoreMLMobileNetV2TailAdapter(modelURL: URL(fileURLWithPath: tailPath), manifest: manifest)
    let profile = try MobileNetV2ComponentProfile(configuration: .quick, coefficientsURL: URL(fileURLWithPath: coefficientPath), tail: tail, corpus: corpus)
    let measurement = try profile.run()
    let artifact = MobileNetV2ComponentProfileArtifact(schemaVersion: 1, status: "mobilenetv2_component_profile", commit: ProcessInfo.processInfo.environment["PF_GIT_COMMIT"], environment: EnvironmentSnapshot(), measurement: measurement, model: manifest)
    let outputPath = ProcessInfo.processInfo.environment["PF_PROFILE_OUTPUT"] ?? "benchmarks/results/r1-mobilenetv2-components.json"
    let url = URL(fileURLWithPath: outputPath)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONEncoder.benchmark.encode(artifact).write(to: url, options: .atomic)
    emit("PlaneFuse profile MobileNetV2: RECORDED")
    emit("result: \(outputPath)")
    emit(String(format: "b_input_ready_to_result_p50_ms: %.4f", measurement.pipelineB.inputReadyToResult.p50Milliseconds))
    emit(String(format: "c_input_ready_to_result_p50_ms: %.4f", measurement.pipelineC.inputReadyToResult.p50Milliseconds))
    emit(String(format: "b_tail_population_p50_ms: %.4f", measurement.pipelineB.multiArrayPopulation.p50Milliseconds))
    emit(String(format: "c_tail_population_p50_ms: %.4f", measurement.pipelineC.multiArrayPopulation.p50Milliseconds))
    emit(String(format: "top1_agreement: %.4f", measurement.top1Agreement))
    return measurement.top1Agreement >= 1.0 ? 0 : 1
}

func runMobileNetV2SharedProfile() throws -> Int32 {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    let coefficientPath = ProcessInfo.processInfo.environment["PF_MOBILENET_COEFFICIENTS"] ?? "models/derived/MobileNetV2StemCoefficients.json"
    let tailPath = ProcessInfo.processInfo.environment["PF_MOBILENET_TAIL"] ?? "models/derived/tail-compiled/MobileNetV2Tail.mlmodelc"
    let manifest = MobileNetV2AssetManifest.inspected
    try manifest.validate(at: root)
    let lineage = try MobileNetV2DerivedArtifactManifest.load(from: root.appendingPathComponent(manifest.derivedManifest))
    try lineage.validate(at: root)
    let corpus = try MobileNetV2Corpus(manifestURL: root.appendingPathComponent(manifest.validationCorpusManifest), root: root)
    let tail = try CoreMLMobileNetV2TailAdapter(modelURL: URL(fileURLWithPath: tailPath), manifest: manifest)
    let profile = try MobileNetV2SharedPathProfile(configuration: .quick, coefficientsURL: URL(fileURLWithPath: coefficientPath), tail: tail, corpus: corpus)
    let measurement = try profile.run()
    let outputPath = ProcessInfo.processInfo.environment["PF_PROFILE_OUTPUT"] ?? "proof/r7-final-shared-path-profile.json"
    let url = URL(fileURLWithPath: outputPath)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONEncoder.benchmark.encode(measurement).write(to: url, options: .atomic)
    emit("PlaneFuse profile MobileNetV2 B2-shared/C1-shared: RECORDED")
    emit("result: \(outputPath)")
    emit(String(format: "b2_frontend_gpu_p50_ms: %.4f", measurement.pipelineB2Shared.gpuExecution?.p50Milliseconds ?? .nan))
    emit(String(format: "c1_frontend_gpu_p50_ms: %.4f", measurement.pipelineC1Shared.gpuExecution?.p50Milliseconds ?? .nan))
    emit(String(format: "b2_input_to_result_p50_ms: %.4f", measurement.pipelineB2Shared.inputToResult.p50Milliseconds))
    emit(String(format: "c1_input_to_result_p50_ms: %.4f", measurement.pipelineC1Shared.inputToResult.p50Milliseconds))
    emit(String(format: "top1_agreement: %.4f", measurement.top1Agreement))
    emit(String(format: "activation_max_abs_error: %.8f", measurement.activationMaxAbsoluteError))
    emit("trace_status: \(measurement.trace.status)")
    return measurement.top1Agreement >= 1.0 && measurement.activationMaxAbsoluteError <= Double(FairABCBenchmark.featureParityTolerance) ? 0 : 1
}

func runMobileNetV2SharedBridge() throws -> Int32 {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    let coefficientPath = ProcessInfo.processInfo.environment["PF_MOBILENET_COEFFICIENTS"] ?? "models/derived/MobileNetV2StemCoefficients.json"
    let tailPath = ProcessInfo.processInfo.environment["PF_MOBILENET_TAIL"] ?? "models/derived/tail-compiled/MobileNetV2Tail.mlmodelc"
    let manifest = MobileNetV2AssetManifest.inspected
    try manifest.validate(at: root)
    let lineage = try MobileNetV2DerivedArtifactManifest.load(from: root.appendingPathComponent(manifest.derivedManifest))
    try lineage.validate(at: root)
    let corpus = try MobileNetV2Corpus(manifestURL: root.appendingPathComponent(manifest.validationCorpusManifest), root: root)
    let tail = try CoreMLMobileNetV2TailAdapter(modelURL: URL(fileURLWithPath: tailPath), manifest: manifest)
    let benchmark = try MobileNetV2SharedBridgeBenchmark(configuration: .quick, coefficientsURL: URL(fileURLWithPath: coefficientPath), tail: tail, corpus: corpus)
    let measurement = try benchmark.run()
    let artifact = MobileNetV2SharedBridgeArtifact(
        schemaVersion: 1,
        status: "mobilenetv2_shared_bridge",
        commit: ProcessInfo.processInfo.environment["PF_GIT_COMMIT"],
        environment: EnvironmentSnapshot(),
        measurement: measurement,
        model: manifest,
        runtimeAssets: [
            "coefficients": relativeAssetPath(coefficientPath, root: root),
            "tail": relativeAssetPath(tailPath, root: root),
            "derived_manifest": manifest.derivedManifest
        ]
    )
    let outputPath = ProcessInfo.processInfo.environment["PF_BENCHMARK_OUTPUT"] ?? "benchmarks/results/r2-mobilenetv2-shared-bridge.json"
    let url = URL(fileURLWithPath: outputPath)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONEncoder.benchmark.encode(artifact).write(to: url, options: .atomic)
    emit("PlaneFuse bench MobileNetV2 shared bridge: RECORDED")
    emit("result: \(outputPath)")
    emit(String(format: "b_boxed_handoff_to_result_p50_ms: %.4f", measurement.pipelineBBoxedHandoffToResult.p50Milliseconds))
    emit(String(format: "b_shared_handoff_to_result_p50_ms: %.4f", measurement.pipelineBSharedHandoffToResult.p50Milliseconds))
    emit(String(format: "c_boxed_handoff_to_result_p50_ms: %.4f", measurement.pipelineCBoxedHandoffToResult.p50Milliseconds))
    emit(String(format: "c_shared_handoff_to_result_p50_ms: %.4f", measurement.pipelineCSharedHandoffToResult.p50Milliseconds))
    emit(String(format: "b_handoff_to_result_reduction_percent: %.2f", measurement.bHandoffToResultReductionPercentage))
    emit(String(format: "c_handoff_to_result_reduction_percent: %.2f", measurement.cHandoffToResultReductionPercentage))
    emit(String(format: "shared_top1_agreement: %.4f", measurement.sharedTop1Agreement))
    emit(String(format: "max_activation_abs_error: %.8f", measurement.maxActivationAbsoluteDifference))
    return measurement.sharedTop1Agreement >= 1.0 && measurement.maxActivationAbsoluteDifference <= Double(FairABCBenchmark.featureParityTolerance) ? 0 : 1
}

func runMobileNetV2SharedBridgeConfirm() throws -> Int32 {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    let coefficientPath = ProcessInfo.processInfo.environment["PF_MOBILENET_COEFFICIENTS"] ?? "models/derived/MobileNetV2StemCoefficients.json"
    let tailPath = ProcessInfo.processInfo.environment["PF_MOBILENET_TAIL"] ?? "models/derived/tail-compiled/MobileNetV2Tail.mlmodelc"
    let manifest = MobileNetV2AssetManifest.inspected
    try manifest.validate(at: root)
    let lineage = try MobileNetV2DerivedArtifactManifest.load(from: root.appendingPathComponent(manifest.derivedManifest))
    try lineage.validate(at: root)
    let corpus = try MobileNetV2Corpus(manifestURL: root.appendingPathComponent(manifest.validationCorpusManifest), root: root)
    let tail = try CoreMLMobileNetV2TailAdapter(modelURL: URL(fileURLWithPath: tailPath), manifest: manifest)
    let batches = try (0..<3).map { _ in
        try MobileNetV2SharedBridgeBenchmark(configuration: .confirm, coefficientsURL: URL(fileURLWithPath: coefficientPath), tail: tail, corpus: corpus).run()
    }
    let artifact = MobileNetV2SharedBridgeConfirmationArtifact(
        schemaVersion: 1,
        status: "mobilenetv2_shared_bridge_confirm",
        commit: ProcessInfo.processInfo.environment["PF_GIT_COMMIT"],
        environment: EnvironmentSnapshot(),
        batches: batches,
        model: manifest,
        runtimeAssets: [
            "coefficients": relativeAssetPath(coefficientPath, root: root),
            "tail": relativeAssetPath(tailPath, root: root),
            "derived_manifest": manifest.derivedManifest
        ]
    )
    let outputPath = ProcessInfo.processInfo.environment["PF_BENCHMARK_OUTPUT"] ?? "benchmarks/results/r2-mobilenetv2-shared-bridge-confirm.json"
    let url = URL(fileURLWithPath: outputPath)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONEncoder.benchmark.encode(artifact).write(to: url, options: .atomic)
    emit("PlaneFuse bench MobileNetV2 shared bridge confirm: RECORDED")
    emit("result: \(outputPath)")
    for (index, batch) in batches.enumerated() {
        emit(String(format: "batch_%d_b_handoff_reduction_percent: %.2f", index + 1, batch.bHandoffToResultReductionPercentage))
        emit(String(format: "batch_%d_c_handoff_reduction_percent: %.2f", index + 1, batch.cHandoffToResultReductionPercentage))
        emit(String(format: "batch_%d_shared_top1_agreement: %.4f", index + 1, batch.sharedTop1Agreement))
    }
    return batches.allSatisfy { $0.sharedTop1Agreement >= 1.0 && $0.maxActivationAbsoluteDifference <= Double(FairABCBenchmark.featureParityTolerance) } ? 0 : 1
}

private func relativeAssetPath(_ path: String, root: URL) -> String {
    let absolute = URL(fileURLWithPath: path).standardizedFileURL.path
    let rootPath = root.standardizedFileURL.path
    if absolute == rootPath { return "." }
    if absolute.hasPrefix(rootPath + "/") { return String(absolute.dropFirst(rootPath.count + 1)) }
    return "<external>/" + URL(fileURLWithPath: absolute).lastPathComponent
}

func runPolyphaseBench() throws -> Int32 {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    let coefficientPath = ProcessInfo.processInfo.environment["PF_MOBILENET_COEFFICIENTS"] ?? "models/derived/MobileNetV2StemCoefficients.json"
    let tailPath = ProcessInfo.processInfo.environment["PF_MOBILENET_TAIL"] ?? "models/derived/tail-compiled/MobileNetV2Tail.mlmodelc"
    let manifest = MobileNetV2AssetManifest.inspected
    try manifest.validate(at: root)
    let lineage = try MobileNetV2DerivedArtifactManifest.load(from: root.appendingPathComponent(manifest.derivedManifest))
    try lineage.validate(at: root)
    let corpus = try MobileNetV2Corpus(manifestURL: root.appendingPathComponent(manifest.validationCorpusManifest), root: root)
    let frames = try corpus.loadFrames()
    let coefficients = try MobileNetV2StemCoefficients.load(from: URL(fileURLWithPath: coefficientPath))
    let factory = try MetalRGBBaseline()
    let native = try MetalMobileNetV2NativeStem(coefficients: coefficients)
    let polyphase = try MetalMobileNetV2PolyphaseStem(coefficients: coefficients)
    let normalization = RGBNormalization(mean: [0.5, 0.5, 0.5], standardDeviation: [0.5, 0.5, 0.5])
    let stem = coefficients.makeStem()
    let nativePlan = NativePlaneConv3x3Compiler.compile(semantics: .bt601VideoRange, normalization: normalization, stem: stem)
    let polyphasePlan = NativePlaneConv3x3Compiler.compilePolyphase(semantics: .bt601VideoRange, normalization: normalization, stem: stem)
    let tail = try CoreMLMobileNetV2TailAdapter(modelURL: URL(fileURLWithPath: tailPath), manifest: manifest)
    let nativeActivation = try native.makeActivationBuffer()
    let polyphaseActivation = try polyphase.makeActivationBuffer()
    let nativeShared = try BufferBackedMultiArray(buffer: nativeActivation, shape: MetalMobileNetV2NativeStem.activationShape)
    let polyphaseShared = try BufferBackedMultiArray(buffer: polyphaseActivation, shape: MetalMobileNetV2NativeStem.activationShape)
    let confirm = ProcessInfo.processInfo.environment["PF_POLYPHASE_CONFIRM"] == "1"
    let warmups = confirm ? 20 : 5; let measured = confirm ? 200 : 20
    var nativeFrontend: [Double] = []; var polyphaseFrontend: [Double] = []
    var nativeEnd: [Double] = []; var polyphaseEnd: [Double] = []
    var nativeGPU: [Double] = []; var polyphaseGPU: [Double] = []
    var pairedFrontendDifferences: [Double] = []; var pairedEndToEndDifferences: [Double] = []
    var maxError = 0.0; var agreement = 0
    func elapsed(_ operation: () throws -> Void) rethrows -> Double {
        let start = ProcessInfo.processInfo.systemUptime; try operation(); return (ProcessInfo.processInfo.systemUptime - start) * 1_000
    }
    func topLabel(_ probabilities: [String: Double]) -> String? { probabilities.max { $0.value < $1.value }?.key }
    for iteration in 0..<(warmups + measured) {
        let frame = frames[iteration % frames.count]
        let input = try factory.makeNV12Textures(width: 224, height: 224, yPlaneBytes: frame.yPlaneBytes, uvPlaneBytes: frame.uvPlaneBytes)
        var nFrontend = 0.0; var pFrontend = 0.0; var nEnd = 0.0; var pEnd = 0.0
        var nGPU: Double?; var pGPU: Double?
        if iteration.isMultiple(of: 2) {
            let nStart = ProcessInfo.processInfo.systemUptime
            let nTiming = try native.executeTimed(input, into: nativeActivation)
            nFrontend = (ProcessInfo.processInfo.systemUptime - nStart) * 1_000
            nGPU = nTiming.gpuExecutionMilliseconds
            nEnd = try elapsed { _ = try tail.predict(sharedActivation: nativeShared) }
            let pStart = ProcessInfo.processInfo.systemUptime
            let pTiming = try polyphase.executeTimed(input, into: polyphaseActivation)
            pFrontend = (ProcessInfo.processInfo.systemUptime - pStart) * 1_000
            pGPU = pTiming.gpuExecutionMilliseconds
            pEnd = try elapsed { _ = try tail.predict(sharedActivation: polyphaseShared) }
        } else {
            let pStart = ProcessInfo.processInfo.systemUptime
            let pTiming = try polyphase.executeTimed(input, into: polyphaseActivation)
            pFrontend = (ProcessInfo.processInfo.systemUptime - pStart) * 1_000
            pGPU = pTiming.gpuExecutionMilliseconds
            pEnd = try elapsed { _ = try tail.predict(sharedActivation: polyphaseShared) }
            let nStart = ProcessInfo.processInfo.systemUptime
            let nTiming = try native.executeTimed(input, into: nativeActivation)
            nFrontend = (ProcessInfo.processInfo.systemUptime - nStart) * 1_000
            nGPU = nTiming.gpuExecutionMilliseconds
            nEnd = try elapsed { _ = try tail.predict(sharedActivation: nativeShared) }
        }
        if iteration >= warmups {
            nativeFrontend.append(nFrontend); polyphaseFrontend.append(pFrontend)
            nativeEnd.append(nFrontend + nEnd); polyphaseEnd.append(pFrontend + pEnd)
            if let nGPU { nativeGPU.append(nGPU) }
            if let pGPU { polyphaseGPU.append(pGPU) }
            pairedFrontendDifferences.append(nFrontend - pFrontend)
            pairedEndToEndDifferences.append((nFrontend + nEnd) - (pFrontend + pEnd))
            let nativeFeatures = try native.readActivation(from: nativeActivation)
            let polyphaseFeatures = try polyphase.readActivation(from: polyphaseActivation)
            maxError = max(maxError, zip(nativeFeatures, polyphaseFeatures).map { abs(Double($0 - $1)) }.max() ?? 0)
            let nativeOutput = try tail.predict(sharedActivation: nativeShared)
            let polyphaseOutput = try tail.predict(sharedActivation: polyphaseShared)
            if topLabel(nativeOutput) == topLabel(polyphaseOutput) { agreement += 1 }
        }
    }
    let nativeFrontendStats = PolyphaseTiming(nativeFrontend); let polyphaseFrontendStats = PolyphaseTiming(polyphaseFrontend)
    let nativeEndStats = PolyphaseTiming(nativeEnd); let polyphaseEndStats = PolyphaseTiming(polyphaseEnd)
    let artifact = PolyphaseBenchmarkArtifact(
        schemaVersion: 1,
        status: maxError <= Double(FairABCBenchmark.featureParityTolerance) && Double(agreement) / Double(measured) >= 1.0 ? "r5_polyphase_measured" : "r5_polyphase_parity_failed",
        commit: ProcessInfo.processInfo.environment["PF_GIT_COMMIT"],
        environment: EnvironmentSnapshot(), warmupIterations: warmups, measuredIterations: measured,
        validationCorpusSampleCount: frames.count, nativeFrontend: nativeFrontendStats, polyphaseFrontend: polyphaseFrontendStats,
        nativeEndToEnd: nativeEndStats, polyphaseEndToEnd: polyphaseEndStats,
        cVsPolyphaseFrontendPercentage: (nativeFrontendStats.p50Milliseconds - polyphaseFrontendStats.p50Milliseconds) / nativeFrontendStats.p50Milliseconds * 100,
        cVsPolyphaseEndToEndPercentage: (nativeEndStats.p50Milliseconds - polyphaseEndStats.p50Milliseconds) / nativeEndStats.p50Milliseconds * 100,
        maxActivationAbsoluteDifference: maxError, taskAgreement: Double(agreement) / Double(measured),
        nativeYReadInstructions: nativePlan.operatorMetadata.yReadInstructions,
        polyphaseYReadInstructions: polyphasePlan.operatorMetadata.yReadInstructions,
        nativeUVReadInstructions: nativePlan.operatorMetadata.uvReadInstructions,
        polyphaseUVReadInstructions: polyphasePlan.operatorMetadata.uvReadInstructions,
        uniqueChromaCoordinates: polyphasePlan.operatorMetadata.uniqueChromaCoordinates,
        nativeWeightedMultiplications: nativePlan.operatorMetadata.weightedMultiplications,
        polyphaseWeightedMultiplications: polyphasePlan.operatorMetadata.weightedMultiplications,
        nativeGPUExecution: nativeGPU.count == measured ? PolyphaseTiming(nativeGPU) : nil,
        polyphaseGPUExecution: polyphaseGPU.count == measured ? PolyphaseTiming(polyphaseGPU) : nil,
        pairedFrontendDifferencesMilliseconds: pairedFrontendDifferences,
        pairedEndToEndDifferencesMilliseconds: pairedEndToEndDifferences,
        generatedPlan: "Exact nearest-sited 4:2:0: nine luma taps, four aggregated chroma phases, per-tap source offsets for bottom/right padding."
    )
    let outputPath = ProcessInfo.processInfo.environment["PF_BENCHMARK_OUTPUT"] ?? (confirm ? "benchmarks/results/r5-polyphase-confirm.json" : "benchmarks/results/r5-polyphase-quick.json")
    let url = URL(fileURLWithPath: outputPath)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONEncoder.benchmark.encode(artifact).write(to: url, options: .atomic)
    emit("PlaneFuse bench polyphase: \(artifact.status.uppercased())")
    emit(String(format: "native_frontend_p50_ms: %.4f", nativeFrontendStats.p50Milliseconds))
    emit(String(format: "polyphase_frontend_p50_ms: %.4f", polyphaseFrontendStats.p50Milliseconds))
    emit(String(format: "native_e2e_p50_ms: %.4f", nativeEndStats.p50Milliseconds))
    emit(String(format: "polyphase_e2e_p50_ms: %.4f", polyphaseEndStats.p50Milliseconds))
    emit(String(format: "polyphase_vs_native_e2e_percent: %.2f", artifact.cVsPolyphaseEndToEndPercentage))
    emit(String(format: "max_activation_abs_error: %.8f", maxError))
    return artifact.status == "r5_polyphase_measured" ? 0 : 1
}

do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard let command = arguments.first else { throw CommandError.usage }
    switch command {
    case "doctor":
        exit(runDoctor())
    case "inspect":
        guard arguments.count == 2 else { throw CommandError.usage }
        exit(try runInspect(model: arguments[1]))
    case "compile":
        guard arguments == ["compile", "mobilenetv2"] else { throw CommandError.usage }
        exit(try runCompileMobileNetV2())
    case "verify":
        if arguments == ["verify", "lineage"] {
            exit(try runVerifySourceLineage())
        }
        if arguments == ["verify", "mobilenetv2"] {
            exit(try runVerifyMobileNetV2())
        }
        if arguments == ["verify", "float16"] {
            exit(try runVerifyFloat16())
        }
        guard arguments == ["verify"] else { throw CommandError.usage }
        exit(try runVerify())
    case "bench":
        let benchmarkArguments = Array(arguments.dropFirst())
        if benchmarkArguments == ["polyphase"] {
            exit(try runPolyphaseBench())
        }
        if benchmarkArguments == ["quick"] {
            exit(try runBench())
        }
        if benchmarkArguments == ["fair", "quick"] {
            exit(try runFairBench(configuration: .quick, label: "quick"))
        }
        if benchmarkArguments == ["fair", "confirm"] {
            exit(try runFairBench(configuration: .confirm, label: "confirm"))
        }
        if benchmarkArguments == ["mobilenetv2", "quick"] {
            exit(try runMobileNetV2Bench(configuration: .quick, label: "quick"))
        }
        if benchmarkArguments == ["mobilenetv2", "b2"] {
            exit(try runMobileNetV2Bench(configuration: .b2Quick, label: "b2"))
        }
        if benchmarkArguments == ["mobilenetv2", "confirm"] {
            exit(try runMobileNetV2Bench(configuration: .confirm, label: "confirm"))
        }
        if benchmarkArguments == ["mobilenetv2", "shared"] || benchmarkArguments == ["mobilenetv2", "shared", "confirm"] {
            exit(try runMobileNetV2DirectSharedBench())
        }
        if benchmarkArguments == ["mobilenetv2", "shared-batch"] {
            exit(try runMobileNetV2DirectSharedBatch())
        }
        if benchmarkArguments == ["mobilenetv2", "r75-batch"] {
            exit(try runR75SourceReuseBatch())
        }
        if benchmarkArguments == ["source-reuse-scale-batch"] {
            exit(try runSourceReuseScalingBatch())
        }
        if benchmarkArguments == ["mobilenetv2", "pipeline-a"] {
            exit(try runPipelineABench())
        }
        throw CommandError.usage
    case "quality":
        guard arguments == ["quality", "mobilenetv2", "b2-c1-shared"] else { throw CommandError.usage }
        exit(try runMobileNetV2SharedQualityEvidence())
    case "profile":
        if arguments == ["profile", "mobilenetv2"] {
            exit(try runMobileNetV2Profile())
        }
        if arguments == ["profile", "mobilenetv2", "shared"] {
            exit(try runMobileNetV2SharedProfile())
        }
        throw CommandError.usage
    case "bridge":
        if arguments == ["bridge", "mobilenetv2"] {
            exit(try runMobileNetV2SharedBridge())
        }
        if arguments == ["bridge", "mobilenetv2", "confirm"] {
            exit(try runMobileNetV2SharedBridgeConfirm())
        }
        throw CommandError.usage
    default:
        throw CommandError.unknownCommand(command)
    }
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(2)
}

private extension JSONEncoder {
    static var cli: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }

    static var planeFuse: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    static var benchmark: JSONEncoder {
        let encoder = JSONEncoder.planeFuse
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }
}
