import Foundation
import Metal

/// R1 decomposition of the current B1/C0 boundary. Component runs isolate
/// conversion and stem encoders; the production benchmark remains the paired
/// one-submission path in `MobileNetV2Benchmark`.
public final class MobileNetV2ComponentProfile {
    public struct Configuration: Codable, Equatable {
        public let warmupIterations: Int
        public let measuredIterations: Int
        public init(warmupIterations: Int = 5, measuredIterations: Int = 20) {
            self.warmupIterations = warmupIterations
            self.measuredIterations = measuredIterations
        }
        public static let quick = Configuration()
    }

    public struct Statistics: Codable, Equatable {
        public let p50Milliseconds: Double
        public let p95Milliseconds: Double
        public let meanMilliseconds: Double
        public let medianAbsoluteDeviationMilliseconds: Double

        public init(_ values: [Double]) {
            let sorted = values.sorted()
            func nearestRank(_ percentile: Double) -> Double {
                sorted[max(1, Int(ceil(percentile * Double(sorted.count)))) - 1]
            }
            let median = nearestRank(0.50)
            p50Milliseconds = median
            p95Milliseconds = nearestRank(0.95)
            meanMilliseconds = values.reduce(0, +) / Double(values.count)
            let deviations = values.map { abs($0 - median) }.sorted()
            medianAbsoluteDeviationMilliseconds = deviations[max(1, Int(ceil(0.50 * Double(deviations.count)))) - 1]
        }
    }

    public struct Pipeline: Codable, Equatable {
        public let inputTextureCreation: Statistics
        public let rgbConversion: Statistics?
        public let rgbStem: Statistics?
        public let nativeStem: Statistics?
        public let gpuWait: Statistics
        public let gpuExecution: Statistics
        public let activationBufferToSwiftArray: Statistics
        public let multiArrayAllocation: Statistics
        public let multiArrayPopulation: Statistics
        public let tailPrediction: Statistics
        public let outputExtraction: Statistics
        public let inputReadyToResult: Statistics
        public let totalIncludingInputPreparation: Statistics
    }

    public struct Measurement: Codable, Equatable {
        public let schemaVersion: Int
        public let configuration: Configuration
        public let pipelineB: Pipeline
        public let pipelineC: Pipeline
        public let top1Agreement: Double
        public let maxActivationAbsoluteDifference: Double
        public let validationSampleCount: Int
        public let deviceName: String
        public let deviceClass: String
        public let methodology: String
    }

    private struct Samples {
        var input: [Double] = []
        var conversion: [Double] = []
        var stem: [Double] = []
        var native: [Double] = []
        var wait: [Double] = []
        var gpu: [Double] = []
        var read: [Double] = []
        var allocation: [Double] = []
        var population: [Double] = []
        var prediction: [Double] = []
        var extraction: [Double] = []
        var inputReady: [Double] = []
        var total: [Double] = []
    }

    private let configuration: Configuration
    private let coefficients: MobileNetV2StemCoefficients
    private let tail: CoreMLMobileNetV2TailAdapter
    private let corpus: MobileNetV2Corpus

    public init(configuration: Configuration = .quick, coefficientsURL: URL, tail: CoreMLMobileNetV2TailAdapter, corpus: MobileNetV2Corpus) throws {
        guard configuration.warmupIterations >= 0, configuration.measuredIterations > 0 else { throw MobileNetV2Benchmark.Error.invalidConfiguration }
        self.configuration = configuration
        self.coefficients = try MobileNetV2StemCoefficients.load(from: coefficientsURL)
        self.tail = tail
        self.corpus = corpus
    }

    public func run(device: MTLDevice? = MTLCreateSystemDefaultDevice()) throws -> Measurement {
        guard let device else { throw MobileNetV2Benchmark.Error.noDevice }
        let factory = try MetalRGBBaseline(device: device)
        let rgb = try MetalMobileNetV2RGBPipeline(device: device, coefficients: coefficients)
        let native = try MetalMobileNetV2NativeStem(device: device, coefficients: coefficients)
        let normalizedRGB = try rgb.makeNormalizedRGBTexture()
        let bActivation = try rgb.makeActivationBuffer()
        let cActivation = try native.makeActivationBuffer()
        let frames = try corpus.loadFrames()
        var b = Samples(); var c = Samples()
        var agreement = 0; var maxError = 0.0

        for iteration in 0..<(configuration.warmupIterations + configuration.measuredIterations) {
            let frame = frames[iteration % frames.count]
            let inputStart = ProcessInfo.processInfo.systemUptime
            let input = try factory.makeNV12Textures(width: 224, height: 224, yPlaneBytes: frame.yPlaneBytes, uvPlaneBytes: frame.uvPlaneBytes)
            let inputMilliseconds = (ProcessInfo.processInfo.systemUptime - inputStart) * 1_000
            let measured = iteration >= configuration.warmupIterations

            let bStart = ProcessInfo.processInfo.systemUptime
            let conversion = try rgb.executeConversion(input, into: normalizedRGB)
            let stem = try rgb.executeRGBStem(normalizedRGB, into: bActivation)
            let readStart = ProcessInfo.processInfo.systemUptime
            let bFeatures = try rgb.readActivation(from: bActivation)
            let readMilliseconds = (ProcessInfo.processInfo.systemUptime - readStart) * 1_000
            let bTail = try tail.predictWithBreakdown(stemActivation: bFeatures)
            let bInputReadyMilliseconds = (ProcessInfo.processInfo.systemUptime - bStart) * 1_000

            let cStart = ProcessInfo.processInfo.systemUptime
            let nativeTiming = try native.executeTimed(input, into: cActivation)
            let cReadStart = ProcessInfo.processInfo.systemUptime
            let cFeatures = try native.readActivation(from: cActivation)
            let cReadMilliseconds = (ProcessInfo.processInfo.systemUptime - cReadStart) * 1_000
            let cTail = try tail.predictWithBreakdown(stemActivation: cFeatures)
            let cInputReadyMilliseconds = (ProcessInfo.processInfo.systemUptime - cStart) * 1_000

            if measured {
                record(&b, inputMilliseconds, conversion.totalMilliseconds, stem.totalMilliseconds, conversion.gpuWaitMilliseconds + stem.gpuWaitMilliseconds, (conversion.gpuExecutionMilliseconds ?? 0) + (stem.gpuExecutionMilliseconds ?? 0), readMilliseconds, bTail, bInputReadyMilliseconds, inputMilliseconds + bInputReadyMilliseconds)
                record(&c, inputMilliseconds, nil, nativeTiming.totalMilliseconds, nativeTiming.gpuWaitMilliseconds, nativeTiming.gpuExecutionMilliseconds ?? 0, cReadMilliseconds, cTail, cInputReadyMilliseconds, inputMilliseconds + cInputReadyMilliseconds)
                maxError = max(maxError, zip(bFeatures, cFeatures).map { abs(Double($0 - $1)) }.max() ?? 0)
                if topLabel(bTail.probabilities) == topLabel(cTail.probabilities) { agreement += 1 }
            }
        }

        return Measurement(
            schemaVersion: 1,
            configuration: configuration,
            pipelineB: makePipeline(b, hasConversion: true),
            pipelineC: makePipeline(c, hasConversion: false),
            top1Agreement: Double(agreement) / Double(configuration.measuredIterations),
            maxActivationAbsoluteDifference: maxError,
            validationSampleCount: configuration.measuredIterations,
            deviceName: device.name,
            deviceClass: String(describing: type(of: device)),
            methodology: "R1 component isolation: B conversion and RGB stem are submitted separately to expose direct regions; C native stem uses one submission. Both paths then use the same MLMultiArray tail with allocation, population, prediction, and output extraction timed separately. These isolated regions are diagnostic and are not substituted for the paired one-submission headline benchmark."
        )
    }

    private func record(_ samples: inout Samples, _ input: Double, _ conversion: Double?, _ stem: Double, _ wait: Double, _ gpu: Double, _ read: Double, _ tail: MobileNetV2TailPredictionBreakdown, _ inputReady: Double, _ total: Double) {
        samples.input.append(input)
        if let conversion { samples.conversion.append(conversion) }
        samples.stem.append(stem); samples.native.append(stem); samples.wait.append(wait); samples.gpu.append(gpu); samples.read.append(read)
        samples.allocation.append(tail.multiArrayAllocationMilliseconds)
        samples.population.append(tail.multiArrayPopulationMilliseconds)
        samples.prediction.append(tail.tailPredictionMilliseconds)
        samples.extraction.append(tail.outputExtractionMilliseconds)
        samples.inputReady.append(inputReady); samples.total.append(total)
    }

    private func makePipeline(_ samples: Samples, hasConversion: Bool) -> Pipeline {
        Pipeline(
            inputTextureCreation: Statistics(samples.input),
            rgbConversion: hasConversion ? Statistics(samples.conversion) : nil,
            rgbStem: hasConversion ? Statistics(samples.stem) : nil,
            nativeStem: hasConversion ? nil : Statistics(samples.native),
            gpuWait: Statistics(samples.wait),
            gpuExecution: Statistics(samples.gpu),
            activationBufferToSwiftArray: Statistics(samples.read),
            multiArrayAllocation: Statistics(samples.allocation),
            multiArrayPopulation: Statistics(samples.population),
            tailPrediction: Statistics(samples.prediction),
            outputExtraction: Statistics(samples.extraction),
            inputReadyToResult: Statistics(samples.inputReady),
            totalIncludingInputPreparation: Statistics(samples.total)
        )
    }

    private func topLabel(_ probabilities: [String: Double]) -> String? {
        probabilities.max { $0.value < $1.value }?.key
    }
}
