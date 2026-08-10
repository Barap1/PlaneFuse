import Foundation

/// Deterministic descriptive and paired-inference statistics for PlaneFuse
/// benchmarks. The bootstrap constants are the preregistered R6.1 protocol
/// and deliberately cannot be overridden by benchmark callers.
public enum BenchmarkStatistics {
    public static let algorithmVersion = "r6.1-hierarchical-block-bootstrap-v1"
    public static let nearestRankPercentileDefinition = "nearest-rank: sorted[ceil(p * n) - 1]"
    public static let pairedDifferenceConvention = "B - C; positive means C is faster"
    public static let bootstrapReplicateCount = 10_000
    public static let bootstrapSeed: UInt64 = 0x50464A52
    public static let bootstrapBatchCount = 5
    public static let bootstrapBlockSize = 10
    public static let bootstrapPairsPerBatch = 200
    public static let bootstrapConfidenceLevel = 0.95

    public enum Error: Swift.Error, Equatable {
        case emptySamples
        case nonFiniteSample
        case invalidPercentile
        case mismatchedPairCounts
        case invalidBatchCount(expected: Int, actual: Int)
        case duplicateBatchID(String)
        case invalidPairCount(batchID: String, expected: Int, actual: Int)
        case zeroBaselinePercentile
    }

    public struct Summary: Codable, Equatable {
        public let p50: Double
        public let p95: Double
        public let mean: Double
        public let medianAbsoluteDeviation: Double

        public init(p50: Double, p95: Double, mean: Double, medianAbsoluteDeviation: Double) {
            self.p50 = p50
            self.p95 = p95
            self.mean = mean
            self.medianAbsoluteDeviation = medianAbsoluteDeviation
        }
    }

    public struct PairedBatch: Codable, Equatable {
        public let batchID: String
        /// Paired B-minus-C differences in frame order. Positive values favor C.
        public let differences: [Double]

        public init(batchID: String, differences: [Double]) {
            self.batchID = batchID
            self.differences = differences
        }
    }

    public struct ConfidenceInterval: Codable, Equatable {
        public let lower: Double
        public let upper: Double

        public init(lower: Double, upper: Double) {
            self.lower = lower
            self.upper = upper
        }
    }

    public struct PairedBootstrapResult: Codable, Equatable {
        public let meanDifference: ConfidenceInterval
        public let medianDifference: ConfidenceInterval

        public init(meanDifference: ConfidenceInterval, medianDifference: ConfidenceInterval) {
            self.meanDifference = meanDifference
            self.medianDifference = medianDifference
        }
    }

    /// Returns `sorted[ceil(p * n) - 1]` using the contract's one-based
    /// nearest-rank definition.
    public static func nearestRank(_ samples: [Double], percentile: Double) throws -> Double {
        try validate(samples)
        guard percentile > 0, percentile <= 1 else { throw Error.invalidPercentile }
        let sorted = samples.sorted()
        return sorted[Int(ceil(percentile * Double(sorted.count))) - 1]
    }

    public static func mean(_ samples: [Double]) throws -> Double {
        try validate(samples)
        return samples.reduce(0, +) / Double(samples.count)
    }

    /// The nearest-rank median of absolute deviations from the sample median.
    public static func medianAbsoluteDeviation(_ samples: [Double]) throws -> Double {
        let median = try nearestRank(samples, percentile: 0.50)
        return try nearestRank(samples.map { abs($0 - median) }, percentile: 0.50)
    }

    public static func summary(_ samples: [Double]) throws -> Summary {
        Summary(
            p50: try nearestRank(samples, percentile: 0.50),
            p95: try nearestRank(samples, percentile: 0.95),
            mean: try mean(samples),
            medianAbsoluteDeviation: try medianAbsoluteDeviation(samples)
        )
    }

    /// Computes the preregistered aggregate percentage from the B2 and C1
    /// p50 values. Positive values mean C1 is faster.
    public static func aggregatePercentage(pipelineB: [Double], pipelineC: [Double]) throws -> Double {
        let b50 = try nearestRank(pipelineB, percentile: 0.50)
        let c50 = try nearestRank(pipelineC, percentile: 0.50)
        guard b50 != 0 else { throw Error.zeroBaselinePercentile }
        return ((b50 - c50) / b50) * 100
    }

    /// Forms frame-aligned B-minus-C differences. Positive values mean C was
    /// faster under the paired latency convention.
    public static func pairedDifferences(pipelineB: [Double], pipelineC: [Double]) throws -> [Double] {
        guard pipelineB.count == pipelineC.count else { throw Error.mismatchedPairCounts }
        try validate(pipelineB)
        try validate(pipelineC)
        return zip(pipelineB, pipelineC).map(-)
    }

    /// Runs the preregistered hierarchical paired bootstrap: resample five
    /// batch IDs with replacement, then resample contiguous 10-frame blocks
    /// within each selected batch until 200 pairs are reconstructed. The 2.5
    /// and 97.5 percentiles use the same nearest-rank convention as the other
    /// descriptive statistics.
    public static func pairedBlockBootstrap(_ batches: [PairedBatch]) throws -> PairedBootstrapResult {
        try validate(batches)
        let orderedBatches = batches.sorted { $0.batchID < $1.batchID }
        var generator = SplitMix64(seed: bootstrapSeed)
        var means: [Double] = []
        var medians: [Double] = []
        means.reserveCapacity(bootstrapReplicateCount)
        medians.reserveCapacity(bootstrapReplicateCount)

        for _ in 0..<bootstrapReplicateCount {
            var reconstructed: [Double] = []
            reconstructed.reserveCapacity(bootstrapBatchCount * bootstrapPairsPerBatch)
            for _ in 0..<bootstrapBatchCount {
                let batch = orderedBatches[generator.nextInt(upperBound: orderedBatches.count)]
                for _ in stride(from: 0, to: bootstrapPairsPerBatch, by: bootstrapBlockSize) {
                    let start = generator.nextInt(upperBound: batch.differences.count - bootstrapBlockSize + 1)
                    reconstructed.append(contentsOf: batch.differences[start..<(start + bootstrapBlockSize)])
                }
            }
            means.append(try mean(reconstructed))
            medians.append(try nearestRank(reconstructed, percentile: 0.50))
        }

        return PairedBootstrapResult(
            meanDifference: ConfidenceInterval(
                lower: try nearestRank(means, percentile: 0.025),
                upper: try nearestRank(means, percentile: 0.975)
            ),
            medianDifference: ConfidenceInterval(
                lower: try nearestRank(medians, percentile: 0.025),
                upper: try nearestRank(medians, percentile: 0.975)
            )
        )
    }

    private static func validate(_ samples: [Double]) throws {
        guard !samples.isEmpty else { throw Error.emptySamples }
        guard samples.allSatisfy({ $0.isFinite }) else { throw Error.nonFiniteSample }
    }

    private static func validate(_ batches: [PairedBatch]) throws {
        guard batches.count == bootstrapBatchCount else {
            throw Error.invalidBatchCount(expected: bootstrapBatchCount, actual: batches.count)
        }
        var batchIDs = Set<String>()
        for batch in batches {
            guard batchIDs.insert(batch.batchID).inserted else { throw Error.duplicateBatchID(batch.batchID) }
            guard batch.differences.count == bootstrapPairsPerBatch else {
                throw Error.invalidPairCount(
                    batchID: batch.batchID,
                    expected: bootstrapPairsPerBatch,
                    actual: batch.differences.count
                )
            }
            try validate(batch.differences)
        }
    }
}

private struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }

    mutating func nextInt(upperBound: Int) -> Int {
        precondition(upperBound > 0)
        let bound = UInt64(upperBound)
        let threshold = (0 &- bound) % bound
        while true {
            let value = next()
            if value >= threshold {
                return Int(value % bound)
            }
        }
    }
}
