import Foundation

public struct EnvironmentSnapshot: Codable, Equatable {
    public let architecture: String
    public let operatingSystem: String
    public let swiftVersion: String
    public let xcodeVersion: String
    public let buildConfiguration: String

    public init(
        architecture: String = ProcessInfo.processInfo.environment["PF_ARCHITECTURE"] ?? "unknown",
        operatingSystem: String = ProcessInfo.processInfo.operatingSystemVersionString,
        swiftVersion: String = ProcessInfo.processInfo.environment["PF_SWIFT_VERSION"] ?? "unknown",
        xcodeVersion: String = ProcessInfo.processInfo.environment["PF_XCODE_VERSION"] ?? "unknown",
        buildConfiguration: String = ProcessInfo.processInfo.environment["PF_BUILD_CONFIGURATION"] ?? "debug"
    ) {
        self.architecture = architecture
        self.operatingSystem = operatingSystem
        self.swiftVersion = swiftVersion
        self.xcodeVersion = xcodeVersion
        self.buildConfiguration = buildConfiguration
    }
}

public struct BenchmarkResult: Codable, Equatable {
    public let schemaVersion: Int
    public let status: String
    public let commit: String?
    public let environment: EnvironmentSnapshot
    public let pipelineB: PipelineMetrics?
    public let pipelineC: PipelineMetrics?
    public let correctness: CorrectnessMetrics?
    public let evidence: [String]

    public init(
        status: String = "no_verified_result",
        commit: String? = nil,
        environment: EnvironmentSnapshot = EnvironmentSnapshot(),
        pipelineB: PipelineMetrics? = nil,
        pipelineC: PipelineMetrics? = nil,
        correctness: CorrectnessMetrics? = nil,
        evidence: [String] = []
    ) {
        self.schemaVersion = 1
        self.status = status
        self.commit = commit
        self.environment = environment
        self.pipelineB = pipelineB
        self.pipelineC = pipelineC
        self.correctness = correctness
        self.evidence = evidence
    }
}

public struct PipelineMetrics: Codable, Equatable {
    public let frontendP50Milliseconds: Double?
    public let frontendP95Milliseconds: Double?
    public let endToEndP50Milliseconds: Double?
    public let endToEndP95Milliseconds: Double?

    public init(
        frontendP50Milliseconds: Double? = nil,
        frontendP95Milliseconds: Double? = nil,
        endToEndP50Milliseconds: Double? = nil,
        endToEndP95Milliseconds: Double? = nil
    ) {
        self.frontendP50Milliseconds = frontendP50Milliseconds
        self.frontendP95Milliseconds = frontendP95Milliseconds
        self.endToEndP50Milliseconds = endToEndP50Milliseconds
        self.endToEndP95Milliseconds = endToEndP95Milliseconds
    }
}

public struct CorrectnessMetrics: Codable, Equatable {
    public let pass: Bool
    public let metric: String
    public let value: Double?

    public init(pass: Bool, metric: String, value: Double? = nil) {
        self.pass = pass
        self.metric = metric
        self.value = value
    }
}

public enum BenchmarkResultWriter {
    public static func write(_ result: BenchmarkResult, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(result)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
