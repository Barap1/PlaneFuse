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

func runVerify() -> Int32 {
    emit("PlaneFuse verify: CONTRACT")
    emit("status: M0 placeholder; numerical/model verification begins in M1")
    return 0
}

func runBench() throws -> Int32 {
    let outputPath = ProcessInfo.processInfo.environment["PF_BENCHMARK_OUTPUT"] ?? "benchmarks/results/quick.json"
    let result = BenchmarkResult()
    try BenchmarkResultWriter.write(result, to: URL(fileURLWithPath: outputPath))
    emit("PlaneFuse bench quick: RECORDED")
    emit("result: \(outputPath)")
    emit("status: no_verified_result")
    return 0
}

do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard let command = arguments.first else { throw CommandError.usage }
    switch command {
    case "doctor":
        exit(runDoctor())
    case "verify":
        exit(runVerify())
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
