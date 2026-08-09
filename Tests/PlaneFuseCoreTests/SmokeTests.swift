import XCTest
@testable import PlaneFuseCore

final class SmokeTests: XCTestCase {
    func testBenchmarkResultUsesNullUntilMeasured() throws {
        let result = BenchmarkResult()
        XCTAssertEqual(result.schemaVersion, 1)
        XCTAssertEqual(result.status, "no_verified_result")
        XCTAssertNil(result.pipelineB)
        XCTAssertNil(result.pipelineC)
        XCTAssertNil(result.correctness)
    }

    func testBenchmarkResultRoundTripsAsJSON() throws {
        let result = BenchmarkResult(environment: EnvironmentSnapshot(architecture: "arm64", operatingSystem: "test"))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("planefuse-result.json")
        try BenchmarkResultWriter.write(result, to: url)
        let decoded = try JSONDecoder().decode(BenchmarkResult.self, from: Data(contentsOf: url))
        XCTAssertEqual(decoded, result)
        try FileManager.default.removeItem(at: url)
    }
}
