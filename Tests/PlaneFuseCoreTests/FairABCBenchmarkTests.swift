import Metal
import XCTest
@testable import PlaneFuseCore

final class FairABCBenchmarkTests: XCTestCase {
    func testQuickConfigurationMatchesFairBenchmarkContract() {
        let configuration = FairABCBenchmark.Configuration.quick

        XCTAssertEqual(configuration.width, 640)
        XCTAssertEqual(configuration.height, 480)
        XCTAssertEqual(configuration.warmupIterations, 10)
        XCTAssertEqual(configuration.measuredIterations, 30)
        XCTAssertEqual(
            FairABCBenchmark.nearestRankPercentileDefinition,
            "nearest-rank: sorted[ceil(p * n) - 1]"
        )
        XCTAssertEqual(FairABCBenchmark.percentageDeltaFormula, "(B - C) / B * 100")
    }

    func testSmallFairBenchmarkPreallocatesAndChecksFeatureParity() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal-specific test skipped: no Metal device is available.")
        }

        let configuration = FairABCBenchmark.Configuration(
            warmupIterations: 1,
            measuredIterations: 4,
            width: 64,
            height: 48
        )
        let measurement = try FairABCBenchmark(configuration: configuration).run(device: device)

        XCTAssertEqual(measurement.measuredIterations, configuration.measuredIterations)
        XCTAssertEqual(measurement.warmupIterations, configuration.warmupIterations)
        XCTAssertEqual(measurement.width, configuration.width)
        XCTAssertEqual(measurement.height, configuration.height)
        XCTAssertEqual(
            measurement.pipelineBRGBIntermediateBytes,
            configuration.width * configuration.height * 4 * MemoryLayout<Float>.stride
        )
        XCTAssertGreaterThan(measurement.pipelineBRGBIntermediateAllocatedBytes, 0)
        XCTAssertEqual(measurement.pipelineCRGBIntermediateBytes, 0)
        XCTAssertGreaterThan(measurement.pipelineCFeatureAllocatedBytes, 0)
        XCTAssertLessThanOrEqual(
            measurement.maxFeatureAbsoluteDifference,
            FairABCBenchmark.featureParityTolerance
        )
        XCTAssertTrue(measurement.featureParityPass)
        XCTAssertEqual(measurement.pipelineCFrontend, measurement.pipelineCEndToEnd)
        XCTAssertGreaterThanOrEqual(measurement.pipelineBFrontend.p50Milliseconds, 0)
        XCTAssertGreaterThanOrEqual(
            measurement.pipelineBFrontend.p95Milliseconds,
            measurement.pipelineBFrontend.p50Milliseconds
        )
        XCTAssertGreaterThanOrEqual(measurement.pipelineBEndToEnd.p50Milliseconds, 0)
        XCTAssertGreaterThanOrEqual(
            measurement.pipelineBEndToEnd.p95Milliseconds,
            measurement.pipelineBEndToEnd.p50Milliseconds
        )
        XCTAssertGreaterThanOrEqual(measurement.pipelineCFrontend.p50Milliseconds, 0)
        XCTAssertGreaterThanOrEqual(
            measurement.pipelineCFrontend.p95Milliseconds,
            measurement.pipelineCFrontend.p50Milliseconds
        )
        XCTAssertNotNil(measurement.cVsBFrontendPercentageDelta)
        XCTAssertNotNil(measurement.cVsBEndToEndPercentageDelta)
        XCTAssertEqual(measurement.percentageDeltaFormula, FairABCBenchmark.percentageDeltaFormula)
        XCTAssertFalse(measurement.deviceName.isEmpty)
        XCTAssertFalse(measurement.deviceClass.isEmpty)
    }
}
