import Foundation
import Metal

/// Fair real-model B/C measurement at the approved MobileNetV2 boundary.
/// Both paths produce the same first activation and invoke the same compiled
/// Core ML tail. The MLMultiArray bridge is intentionally inside the e2e region
/// because it is part of the current reproducible handoff contract.
public final class MobileNetV2Benchmark {
    public struct Configuration: Codable, Equatable {
        public let warmupIterations: Int
        public let measuredIterations: Int
        public let validationSamples: Int
        public let width: Int
        public let height: Int

        public init(warmupIterations: Int = 3, measuredIterations: Int = 20, validationSamples: Int = 4, width: Int = 224, height: Int = 224) {
            self.warmupIterations = warmupIterations
            self.measuredIterations = measuredIterations
            self.validationSamples = validationSamples
            self.width = width
            self.height = height
        }

        public static let quick = Configuration(warmupIterations: 5, measuredIterations: 20, validationSamples: 4)
        /// Confirmation is never allowed to reuse the rejected pre-fix 20-run tier.
        public static let confirm = Configuration(warmupIterations: 10, measuredIterations: 100, validationSamples: 4)
    }

    public struct Statistics: Codable, Equatable {
        public let p50Milliseconds: Double
        public let p95Milliseconds: Double
        public let meanMilliseconds: Double
        public let medianAbsoluteDeviationMilliseconds: Double

        fileprivate init(_ samples: [Double]) {
            let sorted = samples.sorted()
            func nearestRank(_ percentile: Double) -> Double {
                sorted[max(1, Int(ceil(percentile * Double(sorted.count)))) - 1]
            }
            self.p50Milliseconds = nearestRank(0.50)
            self.p95Milliseconds = nearestRank(0.95)
            self.meanMilliseconds = samples.reduce(0, +) / Double(samples.count)
            let median = nearestRank(0.50)
            let deviations = samples.map { abs($0 - median) }.sorted()
            self.medianAbsoluteDeviationMilliseconds = deviations[max(1, Int(ceil(0.50 * Double(deviations.count)))) - 1]
        }
    }

    public struct Measurement: Codable, Equatable {
        public let configuration: Configuration
        public let pipelineBFrontend: Statistics
        public let pipelineCFrontend: Statistics
        public let pipelineBEndToEnd: Statistics
        public let pipelineCEndToEnd: Statistics
        public let pipelineBRGBIntermediateBytes: Int
        public let pipelineCRGBIntermediateBytes: Int
        public let activationBytes: Int
        public let validationSampleCount: Int
        public let top1Agreement: Double
        public let maxActivationAbsoluteDifference: Double
        public let outputAgreementPass: Bool
        public let cVsBFrontendPercentageDelta: Double
        public let cVsBEndToEndPercentageDelta: Double
        public let deviceName: String
        public let deviceClass: String
        public let commandBufferMethodology: String
        public let validationCorpusSampleIds: [String]
        public let independentStemArrayVsBMaxAbsoluteDifference: Double
        public let independentStemArrayVsCMaxAbsoluteDifference: Double
        public let fullArrayVsSplitTailTop1Agreement: Double
        public let independentParityPass: Bool

    }

    public enum Error: Swift.Error, LocalizedError, Equatable {
        case noDevice
        case invalidConfiguration
        case parityFailed(maxError: Double)
        case outputAgreementFailed(agreement: Double)
        case independentParityFailed(maxError: Double, agreement: Double)

        public var errorDescription: String? {
            switch self {
            case .noDevice: return "No Metal device is available for the MobileNetV2 benchmark."
            case .invalidConfiguration: return "MobileNetV2 benchmark configuration is invalid."
            case let .parityFailed(maxError): return "MobileNetV2 B/C activation parity failed with max error \(maxError)."
            case let .outputAgreementFailed(agreement): return "MobileNetV2 B/C output agreement was \(agreement), below 0.995."
            case let .independentParityFailed(maxError, agreement): return "Original-derived Core ML parity failed: max stem error \(maxError), FullArray/split-tail top-1 agreement \(agreement)."
            }
        }
    }

    public let configuration: Configuration
    private let coefficients: MobileNetV2StemCoefficients
    private let tail: MobileNetV2TailRunning
    private let corpus: MobileNetV2Corpus
    private let independentReference: IndependentReference

    public struct IndependentReference {
        public let stemArray: CoreMLMobileNetV2StemArrayAdapter
        public let fullArray: CoreMLMobileNetV2FullArrayAdapter

        public init(stemArray: CoreMLMobileNetV2StemArrayAdapter, fullArray: CoreMLMobileNetV2FullArrayAdapter) {
            self.stemArray = stemArray
            self.fullArray = fullArray
        }
    }

    public init(
        configuration: Configuration = .quick,
        coefficientsURL: URL,
        tail: MobileNetV2TailRunning,
        corpus: MobileNetV2Corpus,
        independentReference: IndependentReference
    ) throws {
        self.configuration = configuration
        self.coefficients = try MobileNetV2StemCoefficients.load(from: coefficientsURL)
        self.tail = tail
        self.corpus = corpus
        self.independentReference = independentReference
        guard configuration.width == 224, configuration.height == 224,
              configuration.warmupIterations >= 0, configuration.measuredIterations > 0,
              configuration.validationSamples > 0,
              configuration.validationSamples == corpus.manifest.samples.count else { throw Error.invalidConfiguration }
    }

    public func run(device: MTLDevice? = MTLCreateSystemDefaultDevice()) throws -> Measurement {
        guard let device else { throw Error.noDevice }
        let factory = try MetalRGBBaseline(device: device)
        let rgb = try MetalMobileNetV2RGBPipeline(device: device, coefficients: coefficients)
        let native = try MetalMobileNetV2NativeStem(device: device, coefficients: coefficients)
        let normalizedRGB = try rgb.makeNormalizedRGBTexture()
        let bActivation = try rgb.makeActivationBuffer()
        let cActivation = try native.makeActivationBuffer()
        let corpusFrames = try corpus.loadFrames()

        var bFrontend: [Double] = []
        var cFrontend: [Double] = []
        var bEndToEnd: [Double] = []
        var cEndToEnd: [Double] = []
        bFrontend.reserveCapacity(configuration.measuredIterations)
        cFrontend.reserveCapacity(configuration.measuredIterations)
        bEndToEnd.reserveCapacity(configuration.measuredIterations)
        cEndToEnd.reserveCapacity(configuration.measuredIterations)

        for iteration in 0..<configuration.warmupIterations {
            let input = try makeInput(factory: factory, frame: corpusFrames[iteration % corpusFrames.count])
            try interleave(iteration: iteration, b: { try rgb.execute(input, normalizedRGB: normalizedRGB, into: bActivation) }, c: { try native.execute(input, into: cActivation) })
        }
        for iteration in 0..<configuration.measuredIterations {
            let input = try makeInput(factory: factory, frame: corpusFrames[iteration % corpusFrames.count])
            try interleave(iteration: iteration, b: {
                bFrontend.append(try elapsed { try rgb.execute(input, normalizedRGB: normalizedRGB, into: bActivation) })
            }, c: {
                cFrontend.append(try elapsed { try native.execute(input, into: cActivation) })
            })
        }

        for iteration in 0..<configuration.warmupIterations {
            let input = try makeInput(factory: factory, frame: corpusFrames[iteration % corpusFrames.count])
            try interleave(iteration: iteration, b: {
                _ = try elapsed {
                    try rgb.execute(input, normalizedRGB: normalizedRGB, into: bActivation)
                    _ = try tail.predict(stemActivation: rgb.readActivation(from: bActivation))
                }
            }, c: {
                _ = try elapsed {
                    try native.execute(input, into: cActivation)
                    _ = try tail.predict(stemActivation: native.readActivation(from: cActivation))
                }
            })
        }
        for iteration in 0..<configuration.measuredIterations {
            let input = try makeInput(factory: factory, frame: corpusFrames[iteration % corpusFrames.count])
            try interleave(iteration: iteration, b: {
                bEndToEnd.append(try elapsed {
                    try rgb.execute(input, normalizedRGB: normalizedRGB, into: bActivation)
                    _ = try tail.predict(stemActivation: rgb.readActivation(from: bActivation))
                })
            }, c: {
                cEndToEnd.append(try elapsed {
                    try native.execute(input, into: cActivation)
                    _ = try tail.predict(stemActivation: native.readActivation(from: cActivation))
                })
            })
        }

        var agreementMatches = 0
        var maxActivationError = 0.0
        var stemArrayVsBMaxError = 0.0
        var stemArrayVsCMaxError = 0.0
        var fullArraySplitTailMatches = 0
        for frame in corpusFrames {
            let input = try makeInput(factory: factory, frame: frame)
            try rgb.execute(input, normalizedRGB: normalizedRGB, into: bActivation)
            try native.execute(input, into: cActivation)
            let bFeatures = try rgb.readActivation(from: bActivation)
            let cFeatures = try native.readActivation(from: cActivation)
            maxActivationError = max(maxActivationError, zip(bFeatures, cFeatures).map { abs(Double($0 - $1)) }.max() ?? 0)
            let bOutput = try tail.predict(stemActivation: bFeatures)
            let cOutput = try tail.predict(stemActivation: cFeatures)
            if Self.topLabel(bOutput) == Self.topLabel(cOutput) { agreementMatches += 1 }
            let sourcePreprocessed = try rgb.readNormalizedRGB(from: normalizedRGB)
            let stemArrayFeatures = try independentReference.stemArray.predict(normalizedRGB: sourcePreprocessed)
            // Run the independent original-derived graphs CPU-only so their
            // Float32 reference is not perturbed by the asset's default
            // accelerator precision. Retain raw Float32 B/C parity above.
            stemArrayVsBMaxError = max(stemArrayVsBMaxError, Self.maxAbsoluteDifference(stemArrayFeatures, bFeatures))
            stemArrayVsCMaxError = max(stemArrayVsCMaxError, Self.maxAbsoluteDifference(stemArrayFeatures, cFeatures))
            let fullArrayOutput = try independentReference.fullArray.predict(normalizedRGB: sourcePreprocessed)
            let splitTailOutput = try tail.predict(stemActivation: stemArrayFeatures)
            if Self.topLabel(fullArrayOutput) == Self.topLabel(splitTailOutput) { fullArraySplitTailMatches += 1 }
        }
        let agreement = Double(agreementMatches) / Double(configuration.validationSamples)
        let pass = maxActivationError <= Double(FairABCBenchmark.featureParityTolerance) && agreement >= MobileNetV2OutputAgreement.requiredTop1Agreement
        if !pass {
            if maxActivationError > Double(FairABCBenchmark.featureParityTolerance) { throw Error.parityFailed(maxError: maxActivationError) }
            throw Error.outputAgreementFailed(agreement: agreement)
        }
        let fullArraySplitTailAgreement = Double(fullArraySplitTailMatches) / Double(corpusFrames.count)
        let independentPass = stemArrayVsBMaxError <= MobileNetV2OutputAgreement.referenceStemParityTolerance
            && stemArrayVsCMaxError <= MobileNetV2OutputAgreement.referenceStemParityTolerance
            && fullArraySplitTailAgreement >= MobileNetV2OutputAgreement.requiredTop1Agreement
        guard independentPass else {
            throw Error.independentParityFailed(maxError: max(stemArrayVsBMaxError, stemArrayVsCMaxError), agreement: fullArraySplitTailAgreement)
        }

        return Measurement(
            configuration: configuration,
            pipelineBFrontend: Statistics(bFrontend), pipelineCFrontend: Statistics(cFrontend),
            pipelineBEndToEnd: Statistics(bEndToEnd), pipelineCEndToEnd: Statistics(cEndToEnd),
            pipelineBRGBIntermediateBytes: 224 * 224 * 4 * MemoryLayout<Float>.stride,
            pipelineCRGBIntermediateBytes: 0,
            activationBytes: MetalMobileNetV2NativeStem.activationCount * MemoryLayout<Float>.stride,
            validationSampleCount: configuration.validationSamples, top1Agreement: agreement,
            maxActivationAbsoluteDifference: maxActivationError, outputAgreementPass: pass,
            cVsBFrontendPercentageDelta: (Statistics(bFrontend).p50Milliseconds - Statistics(cFrontend).p50Milliseconds) / Statistics(bFrontend).p50Milliseconds * 100,
            cVsBEndToEndPercentageDelta: (Statistics(bEndToEnd).p50Milliseconds - Statistics(cEndToEnd).p50Milliseconds) / Statistics(bEndToEnd).p50Milliseconds * 100,
            deviceName: device.name, deviceClass: String(describing: type(of: device)),
            commandBufferMethodology: "Frontend: one command buffer / one submission per B RGB conversion+stem and C native stem. End-to-end: same one-submission B/C Metal boundary, followed by the same Core ML tail and explicit MLMultiArray handoff.",
            validationCorpusSampleIds: corpusFrames.map(\.id),
            independentStemArrayVsBMaxAbsoluteDifference: stemArrayVsBMaxError,
            independentStemArrayVsCMaxAbsoluteDifference: stemArrayVsCMaxError,
            fullArrayVsSplitTailTop1Agreement: fullArraySplitTailAgreement,
            independentParityPass: independentPass
        )
    }

    private func makeInput(factory: MetalRGBBaseline, frame: MobileNetV2CorpusFrame) throws -> MetalRGBBaseline.NV12Textures {
        try factory.makeNV12Textures(width: configuration.width, height: configuration.height, yPlaneBytes: frame.yPlaneBytes, uvPlaneBytes: frame.uvPlaneBytes)
    }

    private func interleave(iteration: Int, b: () throws -> Void, c: () throws -> Void) rethrows {
        if iteration.isMultiple(of: 2) { try b(); try c() } else { try c(); try b() }
    }

    private func elapsed(_ operation: () throws -> Void) rethrows -> Double {
        let start = ProcessInfo.processInfo.systemUptime
        try operation()
        return (ProcessInfo.processInfo.systemUptime - start) * 1_000
    }

    private static func topLabel(_ probabilities: [String: Double]) -> String? {
        probabilities.max { $0.value < $1.value }?.key
    }

    private static func maxAbsoluteDifference(_ lhs: [Float], _ rhs: [Float]) -> Double {
        guard lhs.count == rhs.count else { return .infinity }
        return zip(lhs, rhs).map { abs(Double($0 - $1)) }.max() ?? 0
    }

}
