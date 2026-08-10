import XCTest
@testable import PlaneFuseCore

final class BenchmarkStatisticsTests: XCTestCase {
    func testNearestRankSummaryAndMADUseDocumentedSmallFixture() throws {
        // Sorted fixture: [1, 2, 5, 5, 9]. Expected p50=5, p95=9,
        // mean=4.4, and MAD=3 from deviations [0, 0, 3, 3, 4].
        let summary = try BenchmarkStatistics.summary([9, 1, 5, 5, 2])

        XCTAssertEqual(summary.p50, 5)
        XCTAssertEqual(summary.p95, 9)
        XCTAssertEqual(summary.mean, 4.4, accuracy: 0.000_000_001)
        XCTAssertEqual(summary.medianAbsoluteDeviation, 3)
        XCTAssertEqual(
            BenchmarkStatistics.nearestRankPercentileDefinition,
            "nearest-rank: sorted[ceil(p * n) - 1]"
        )
    }

    func testPairedDifferencesUsePositiveBMinusCConvention() throws {
        // Expected frame-aligned B-minus-C differences: [2, -3, 3].
        let differences = try BenchmarkStatistics.pairedDifferences(
            pipelineB: [10, 20, 30],
            pipelineC: [8, 23, 27]
        )

        XCTAssertEqual(differences, [2, -3, 3])
        XCTAssertEqual(
            BenchmarkStatistics.pairedDifferenceConvention,
            "B - C; positive means C is faster"
        )
    }

    func testAggregatePercentageUsesB2P50DenominatorAndVersion() throws {
        let percentage = try BenchmarkStatistics.aggregatePercentage(
            pipelineB: [30, 10, 20],
            pipelineC: [27, 8, 18]
        )

        XCTAssertEqual(percentage, 10, accuracy: 0.000_000_001)
        XCTAssertEqual(BenchmarkStatistics.algorithmVersion, "r6.1-hierarchical-block-bootstrap-v1")
    }

    func testAggregatePercentageRejectsZeroBaseline() {
        XCTAssertThrowsError(
            try BenchmarkStatistics.aggregatePercentage(pipelineB: [0], pipelineC: [0])
        ) { error in
            XCTAssertEqual(error as? BenchmarkStatistics.Error, .zeroBaselinePercentile)
        }
    }

    func testHierarchicalBlockBootstrapIsDeterministicForDocumentedFixture() throws {
        // Five 20-frame batches make the selected 10-frame contiguous block
        // observable. The exact fixed-seed CI values below lock the R6.1
        // outer batch resampling and inner contiguous-block procedure.
        let batches = (0..<5).map { batch in
            BenchmarkStatistics.PairedBatch(
                batchID: "batch-\(batch)",
                differences: (0..<200).map { frame in Double(batch * 1000 + frame) }
            )
        }

        let first = try BenchmarkStatistics.pairedBlockBootstrap(batches)
        let second = try BenchmarkStatistics.pairedBlockBootstrap(batches.reversed())

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.meanDifference.lower, 896.41, accuracy: 0.000_000_001)
        XCTAssertEqual(first.meanDifference.upper, 3303.13, accuracy: 0.000_000_001)
        XCTAssertEqual(first.medianDifference.lower, 159.0, accuracy: 0.000_000_001)
        XCTAssertEqual(first.medianDifference.upper, 4040.0, accuracy: 0.000_000_001)
        XCTAssertEqual(BenchmarkStatistics.bootstrapReplicateCount, 10_000)
        XCTAssertEqual(BenchmarkStatistics.bootstrapSeed, 0x50464A52)
        XCTAssertEqual(BenchmarkStatistics.bootstrapBatchCount, 5)
        XCTAssertEqual(BenchmarkStatistics.bootstrapBlockSize, 10)
        XCTAssertEqual(BenchmarkStatistics.bootstrapPairsPerBatch, 200)
    }

    func testBootstrapRejectsBatchPopulationThatDoesNotMatchProtocol() {
        let batches = (0..<5).map { batch in
            BenchmarkStatistics.PairedBatch(batchID: "batch-\(batch)", differences: Array(repeating: Double(batch), count: batch == 0 ? 199 : 200))
        }

        XCTAssertThrowsError(try BenchmarkStatistics.pairedBlockBootstrap(batches)) { error in
            XCTAssertEqual(
                error as? BenchmarkStatistics.Error,
                .invalidPairCount(batchID: "batch-0", expected: 200, actual: 199)
            )
        }
    }

    func testBootstrapRejectsSixBatches() {
        let batches = (0..<6).map { batch in
            BenchmarkStatistics.PairedBatch(
                batchID: "batch-\(batch)",
                differences: Array(repeating: Double(batch), count: 200)
            )
        }

        XCTAssertThrowsError(try BenchmarkStatistics.pairedBlockBootstrap(batches)) { error in
            XCTAssertEqual(error as? BenchmarkStatistics.Error, .invalidBatchCount(expected: 5, actual: 6))
        }
    }
}
