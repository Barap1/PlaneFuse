import Metal
import XCTest
@testable import PlaneFuseCore

final class MetalBaselineBenchmarkTests: XCTestCase {
    func testQuickConfigurationAndFixtureSizingAreDeterministic() {
        let configuration = MetalBaselineBenchmark.Configuration.quick
        let first = MetalBaselineBenchmark.deterministicNV12Fixture(
            width: configuration.width,
            height: configuration.height
        )
        let second = MetalBaselineBenchmark.deterministicNV12Fixture(
            width: configuration.width,
            height: configuration.height
        )

        XCTAssertEqual(configuration.warmupIterations, 10)
        XCTAssertEqual(configuration.measuredIterations, 30)
        XCTAssertEqual(configuration.width, 640)
        XCTAssertEqual(configuration.height, 480)
        XCTAssertEqual(first.yPlaneBytes, second.yPlaneBytes)
        XCTAssertEqual(first.uvPlaneBytes, second.uvPlaneBytes)
        XCTAssertEqual(first.yPlaneBytes.count, configuration.width * configuration.height)
        XCTAssertEqual(first.uvPlaneBytes.count, configuration.width * configuration.height / 2)
        XCTAssertEqual(first.yPlaneBytes.count + first.uvPlaneBytes.count, 460_800)
    }

    func testBenchmarkReportsMeasuredStatisticsAndIntermediateSizing() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal-specific test skipped: no Metal device is available.")
        }

        let configuration = MetalBaselineBenchmark.Configuration(
            warmupIterations: 1,
            measuredIterations: 3,
            width: 64,
            height: 48
        )
        let measurement = try MetalBaselineBenchmark(configuration: configuration).run(device: device)

        XCTAssertEqual(measurement.measuredIterations, 3)
        XCTAssertEqual(measurement.warmupIterations, 1)
        XCTAssertEqual(measurement.inputByteCount, 64 * 48 * 3 / 2)
        XCTAssertEqual(measurement.outputIntermediateByteCount, 64 * 48 * 4 * MemoryLayout<Float>.stride)
        XCTAssertGreaterThanOrEqual(measurement.frontendP50Milliseconds, 0)
        XCTAssertGreaterThanOrEqual(measurement.frontendP95Milliseconds, measurement.frontendP50Milliseconds)
        XCTAssertGreaterThanOrEqual(measurement.frontendMeanMilliseconds, 0)
        XCTAssertFalse(measurement.deviceName.isEmpty)
        XCTAssertFalse(measurement.deviceClass.isEmpty)
    }
}
