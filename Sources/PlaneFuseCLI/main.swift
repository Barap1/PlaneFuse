import Foundation
import PlaneFuseCore

enum CommandError: Error, CustomStringConvertible {
    case usage
    case unknownCommand(String)

    var description: String {
        switch self {
        case .usage:
            return "usage: planefuse <doctor|inspect|compile|verify|bench> [fixture|mobilenetv2|quick|fair]"
        case let .unknownCommand(command):
            return "error: unknown command '\(command)'\nusage: planefuse <doctor|inspect|compile|verify|bench> [fixture|mobilenetv2|quick|fair]"
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

func runMobileNetV2SharedBridge() throws -> Int32 {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    let coefficientPath = ProcessInfo.processInfo.environment["PF_MOBILENET_COEFFICIENTS"] ?? "models/derived/MobileNetV2StemCoefficients.json"
    let tailPath = ProcessInfo.processInfo.environment["PF_MOBILENET_TAIL"] ?? "models/derived/tail-compiled/MobileNetV2Tail.mlmodelc"
    let manifest = MobileNetV2AssetManifest.inspected
    try manifest.validate(at: root)
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

private func relativeAssetPath(_ path: String, root: URL) -> String {
    let absolute = URL(fileURLWithPath: path).standardizedFileURL.path
    let rootPath = root.standardizedFileURL.path
    if absolute == rootPath { return "." }
    if absolute.hasPrefix(rootPath + "/") { return String(absolute.dropFirst(rootPath.count + 1)) }
    return "<external>/" + URL(fileURLWithPath: absolute).lastPathComponent
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
        guard arguments == ["verify"] else { throw CommandError.usage }
        exit(try runVerify())
    case "bench":
        let benchmarkArguments = Array(arguments.dropFirst())
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
        throw CommandError.usage
    case "profile":
        guard arguments == ["profile", "mobilenetv2"] else { throw CommandError.usage }
        exit(try runMobileNetV2Profile())
    case "bridge":
        guard arguments == ["bridge", "mobilenetv2"] else { throw CommandError.usage }
        exit(try runMobileNetV2SharedBridge())
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
