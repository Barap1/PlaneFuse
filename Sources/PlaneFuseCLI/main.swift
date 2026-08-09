import Foundation
import PlaneFuseCore

enum CommandError: Error, CustomStringConvertible {
    case usage
    case unknownCommand(String)

    var description: String {
        switch self {
        case .usage:
            return "usage: planefuse <doctor|verify|bench> [quick]"
        case let .unknownCommand(command):
            return "error: unknown command '\(command)'\nusage: planefuse <doctor|verify|bench> [quick]"
        }
    }
}

func emit(_ message: String) {
    print(message)
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

do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard let command = arguments.first else { throw CommandError.usage }
    switch command {
    case "doctor":
        exit(runDoctor())
    case "verify":
        exit(try runVerify())
    case "bench":
        guard arguments.dropFirst().first == "quick" else { throw CommandError.usage }
        exit(try runBench())
    default:
        throw CommandError.unknownCommand(command)
    }
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(2)
}

private extension JSONEncoder {
    static var planeFuse: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
