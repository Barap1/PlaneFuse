import XCTest
@testable import PlaneFuseCore

final class MobileNetV2DirectSharedBenchmarkTests: XCTestCase {
    func testConfigurationDefaultsToFinalProtocolCardinalityAndTwentyWarmups() throws {
        let configuration = try MobileNetV2DirectSharedBenchmark.Configuration()

        XCTAssertEqual(configuration.warmupIterations, 20)
        XCTAssertEqual(configuration.measuredPairsPerBatch, 200)
        XCTAssertEqual(configuration.batchCount, 5)
        XCTAssertEqual(configuration.validationSamples, 0)
    }

    func testConfigurationRejectsFewerThanTwentyWarmups() {
        XCTAssertThrowsError(try MobileNetV2DirectSharedBenchmark.Configuration(warmupIterations: 19)) { error in
            XCTAssertEqual(error as? MobileNetV2DirectSharedBenchmark.Error, .invalidConfiguration)
        }
    }

    func testConfigurationDecodingRejectsAlternateProductionCardinality() {
        let invalidPairs = Data(#"{"warmupIterations":20,"measuredPairsPerBatch":199,"batchCount":5,"validationSamples":0}"#.utf8)
        let invalidBatches = Data(#"{"warmupIterations":20,"measuredPairsPerBatch":200,"batchCount":6,"validationSamples":0}"#.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(MobileNetV2DirectSharedBenchmark.Configuration.self, from: invalidPairs))
        XCTAssertThrowsError(try JSONDecoder().decode(MobileNetV2DirectSharedBenchmark.Configuration.self, from: invalidBatches))
    }

    func testRawPairRecordAlwaysUsesDirectB2MinusC1Difference() {
        let record = MobileNetV2DirectSharedBenchmark.RawPairRecord(
            batchID: "batch-0",
            frameIndex: 7,
            sourceSampleID: "fixture-7",
            executionOrder: "C1_then_B2",
            b2Milliseconds: 12.5,
            c1Milliseconds: 10.25
        )

        XCTAssertEqual(record.b2MinusC1Milliseconds, 2.25, accuracy: 0.000_000_001)
        XCTAssertEqual(record.executionOrder, "C1_then_B2")
    }

    func testProtocolMetadataIsTakenFromFixedBenchmarkStatisticsContract() {
        XCTAssertEqual(BenchmarkStatistics.bootstrapBatchCount, 5)
        XCTAssertEqual(BenchmarkStatistics.bootstrapPairsPerBatch, 200)
        XCTAssertEqual(BenchmarkStatistics.bootstrapReplicateCount, 10_000)
        XCTAssertEqual(BenchmarkStatistics.bootstrapSeed, 0x50464A52)
    }
}
