import XCTest
@testable import PlaneFuseCore

final class MobileNetV2SharedQualityEvidenceTests: XCTestCase {
    func testComparisonReportsRankingAndProbabilityMetrics() {
        let sample = MobileNetV2SharedQualityEvidence.compare(
            id: "stress-00",
            category: "procedural-stress",
            corpusKind: "procedural",
            b2Activation: [1, 2, -3],
            c1Activation: [1.25, 1.5, -2.5],
            b2Probabilities: ["a": 0.6, "b": 0.3, "c": 0.1],
            c1Probabilities: ["b": 0.6, "a": 0.3, "c": 0.1]
        )

        XCTAssertEqual(sample.b2Top1Label, "a")
        XCTAssertEqual(sample.c1Top1Label, "b")
        XCTAssertFalse(sample.top1Agreement)
        XCTAssertTrue(sample.top5SetAgreement)
        XCTAssertFalse(sample.top5RankingAgreement)
        XCTAssertEqual(sample.activationMaximumAbsoluteError, 0.5, accuracy: 0.000_000_001)
        XCTAssertEqual(sample.activationMeanAbsoluteError, 0.416_666_666_7, accuracy: 0.000_000_001)
        XCTAssertEqual(sample.probabilityMaximumAbsoluteError, 0.3, accuracy: 0.000_000_001)
        XCTAssertEqual(sample.probabilityL1Distance, 0.6, accuracy: 0.000_000_001)
        XCTAssertTrue(sample.hasClassificationDisagreement)
    }

    func testComparisonUsesStableAlphabeticalTieBreakForTopFive() {
        let sample = MobileNetV2SharedQualityEvidence.compare(
            id: "real-00",
            category: "animals",
            corpusKind: "real",
            b2Activation: [0, 0],
            c1Activation: [0, 0],
            b2Probabilities: ["zebra": 0.5, "ant": 0.5],
            c1Probabilities: ["ant": 0.5, "zebra": 0.5]
        )

        XCTAssertEqual(sample.b2Top5Labels, ["ant", "zebra"])
        XCTAssertEqual(sample.c1Top5Labels, ["ant", "zebra"])
        XCTAssertTrue(sample.top5RankingAgreement)
        XCTAssertEqual(sample.activationCosineSimilarity, 1.0, accuracy: 0.000_000_001)
    }
}
