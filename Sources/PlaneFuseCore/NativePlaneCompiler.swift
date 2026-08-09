import Foundation

/// The narrow input contract understood by the native-plane Conv2D compiler.
/// This is inspection metadata only; it does not load or compile model files.
public struct NativePlaneRGBCHWNormalization: Codable, Equatable {
    public let channelOrder: [String]
    public let mean: [Double]
    public let standardDeviation: [Double]

    public init(
        channelOrder: [String] = ["R", "G", "B"],
        mean: [Double],
        standardDeviation: [Double]
    ) {
        self.channelOrder = channelOrder
        self.mean = mean
        self.standardDeviation = standardDeviation
    }

    /// Affine form of the CHW transform: `normalized = rgb * scale + bias`.
    public var scale: [Double] {
        standardDeviation.map { 1 / $0 }
    }

    public var bias: [Double] {
        zip(mean, scale).map { -$0.0 * $0.1 }
    }
}

public enum NativePlaneStemValidationError: LocalizedError, Equatable {
    case invalidInputGeometry(width: Int, height: Int)
    case invalidOutputGeometry(width: Int, height: Int)
    case unsupportedKernel(width: Int, height: Int)
    case unsupportedStride(x: Int, y: Int)
    case unsupportedPadding(String)
    case invalidChannelOrder([String])
    case invalidNormalizationArity(mean: Int, standardDeviation: Int)
    case invalidNormalizationMean(channel: Int, value: Double)
    case invalidNormalizationScale(channel: Int, value: Double)
    case invalidOutputChannels(Int)
    case emptyCoefficientLineage
    case emptyModelLineage

    public var errorDescription: String? {
        switch self {
        case let .invalidInputGeometry(width, height):
            return "Native-plane Conv2D stems require a 224x224 input; received \(width)x\(height)."
        case let .invalidOutputGeometry(width, height):
            return "Native-plane Conv2D stems require a 112x112 output; received \(width)x\(height)."
        case let .unsupportedKernel(width, height):
            return "Native-plane Conv2D stems require a 3x3 kernel; received \(width)x\(height)."
        case let .unsupportedStride(x, y):
            return "Native-plane Conv2D stems require stride 2x2; received \(x)x\(y)."
        case let .unsupportedPadding(mode):
            return "Native-plane Conv2D stems support only SAME bottom/right padding; received '\(mode)'."
        case let .invalidChannelOrder(order):
            return "RGB CHW normalization requires channel order [R, G, B]; received \(order)."
        case let .invalidNormalizationArity(mean, standardDeviation):
            return "RGB CHW normalization requires three means and three standard deviations; received \(mean) and \(standardDeviation)."
        case let .invalidNormalizationMean(channel, value):
            return "RGB CHW normalization mean at channel \(channel) must be finite; received \(value)."
        case let .invalidNormalizationScale(channel, value):
            return "RGB CHW normalization standard deviation at channel \(channel) must be finite and greater than zero; received \(value)."
        case let .invalidOutputChannels(count):
            return "Native-plane Conv2D stems require a positive output-channel count; received \(count)."
        case .emptyCoefficientLineage:
            return "A native-plane stem must identify its coefficient lineage."
        case .emptyModelLineage:
            return "A native-plane stem must identify its model lineage."
        }
    }
}

/// Codable, reusable description of a compatible NV12 native-plane Conv2D stem.
/// It intentionally contains no weights and performs no model inspection itself.
public struct NativePlaneStemSpec: Codable, Equatable {
    public let inputWidth: Int
    public let inputHeight: Int
    public let outputWidth: Int
    public let outputHeight: Int
    public let kernelWidth: Int
    public let kernelHeight: Int
    public let strideX: Int
    public let strideY: Int
    /// Canonical spelling is `same_bottom_right`.
    public let paddingMode: String
    public let normalization: NativePlaneRGBCHWNormalization
    public let outputChannels: Int
    public let usesBatchNormalization: Bool
    public let usesReLU6: Bool
    public let coefficientLineage: String
    public let modelLineage: String

    public init(
        inputWidth: Int,
        inputHeight: Int,
        outputWidth: Int,
        outputHeight: Int,
        kernelWidth: Int,
        kernelHeight: Int,
        strideX: Int,
        strideY: Int,
        paddingMode: String,
        normalization: NativePlaneRGBCHWNormalization,
        outputChannels: Int,
        usesBatchNormalization: Bool,
        usesReLU6: Bool,
        coefficientLineage: String,
        modelLineage: String
    ) {
        self.inputWidth = inputWidth
        self.inputHeight = inputHeight
        self.outputWidth = outputWidth
        self.outputHeight = outputHeight
        self.kernelWidth = kernelWidth
        self.kernelHeight = kernelHeight
        self.strideX = strideX
        self.strideY = strideY
        self.paddingMode = paddingMode
        self.normalization = normalization
        self.outputChannels = outputChannels
        self.usesBatchNormalization = usesBatchNormalization
        self.usesReLU6 = usesReLU6
        self.coefficientLineage = coefficientLineage
        self.modelLineage = modelLineage
    }

    public func validate() throws {
        guard inputWidth == 224, inputHeight == 224 else {
            throw NativePlaneStemValidationError.invalidInputGeometry(width: inputWidth, height: inputHeight)
        }
        guard outputWidth == 112, outputHeight == 112 else {
            throw NativePlaneStemValidationError.invalidOutputGeometry(width: outputWidth, height: outputHeight)
        }
        guard kernelWidth == 3, kernelHeight == 3 else {
            throw NativePlaneStemValidationError.unsupportedKernel(width: kernelWidth, height: kernelHeight)
        }
        guard strideX == 2, strideY == 2 else {
            throw NativePlaneStemValidationError.unsupportedStride(x: strideX, y: strideY)
        }
        guard paddingMode == "same_bottom_right" else {
            throw NativePlaneStemValidationError.unsupportedPadding(paddingMode)
        }
        guard normalization.channelOrder == ["R", "G", "B"] else {
            throw NativePlaneStemValidationError.invalidChannelOrder(normalization.channelOrder)
        }
        guard normalization.mean.count == 3,
              normalization.standardDeviation.count == 3 else {
            throw NativePlaneStemValidationError.invalidNormalizationArity(
                mean: normalization.mean.count,
                standardDeviation: normalization.standardDeviation.count
            )
        }
        for (channel, value) in normalization.mean.enumerated() {
            guard value.isFinite else {
                throw NativePlaneStemValidationError.invalidNormalizationMean(channel: channel, value: value)
            }
        }
        for (channel, value) in normalization.standardDeviation.enumerated() {
            guard value.isFinite, value > 0 else {
                throw NativePlaneStemValidationError.invalidNormalizationScale(channel: channel, value: value)
            }
        }
        guard outputChannels > 0 else {
            throw NativePlaneStemValidationError.invalidOutputChannels(outputChannels)
        }
        guard !coefficientLineage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NativePlaneStemValidationError.emptyCoefficientLineage
        }
        guard !modelLineage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NativePlaneStemValidationError.emptyModelLineage
        }
    }

    public static func mobileNetV2() -> Self {
        Self(
            inputWidth: 224, inputHeight: 224, outputWidth: 112, outputHeight: 112,
            kernelWidth: 3, kernelHeight: 3, strideX: 2, strideY: 2,
            paddingMode: "same_bottom_right",
            normalization: NativePlaneRGBCHWNormalization(
                // Apple's MobileNetV2 image scaler is pixel / 127.5 - 1,
                // represented here as (rgb - 0.5) / 0.5 for RGB in [0, 1].
                mean: [0.5, 0.5, 0.5],
                standardDeviation: [0.5, 0.5, 0.5]
            ),
            outputChannels: 48,
            usesBatchNormalization: true,
            usesReLU6: true,
            coefficientLineage: "MobileNetV2StemCoefficients.json",
            modelLineage: "Apple MobileNetV2 ImageNet / MobileNetV2.mlmodel"
        )
    }

    /// A second, parameterized reference configuration used to prove that the
    /// inspection/validation contract is not tied to MobileNetV2's 48 channels.
    /// It is deliberately not presented as a pretrained workload.
    public static func referenceFixture() -> Self {
        Self(
            inputWidth: 224, inputHeight: 224, outputWidth: 112, outputHeight: 112,
            kernelWidth: 3, kernelHeight: 3, strideX: 2, strideY: 2,
            paddingMode: "same_bottom_right",
            normalization: NativePlaneRGBCHWNormalization(
                mean: [0, 0, 0], standardDeviation: [1, 1, 1]
            ),
            outputChannels: 16,
            usesBatchNormalization: true,
            usesReLU6: true,
            coefficientLineage: "fixture://native-plane-conv3x3-v1",
            modelLineage: "PlaneFuse parameterized reference fixture (not pretrained)"
        )
    }
}

/// Compatibility name for callers that model the metadata as a configuration.
public typealias NativePlaneStemConfiguration = NativePlaneStemSpec

/// Stable inspection result for tooling. A failed inspection is data, not an
/// assertion that a model can be compiled by silently relaxing the contract.
public struct NativePlaneStemInspection: Codable, Equatable {
    public let compatible: Bool
    public let modelLineage: String
    public let outputChannels: Int
    public let supportedSemantics: [String]
    public let rejectionReason: String?

    public static func inspect(_ spec: NativePlaneStemSpec) -> Self {
        do {
            try spec.validate()
            return Self(
                compatible: true,
                modelLineage: spec.modelLineage,
                outputChannels: spec.outputChannels,
                supportedSemantics: [
                    "NV12 8-bit bi-planar Y+UV input",
                    "3x3 Conv2D, stride 2x2",
                    "SAME bottom/right source coordinate: 2 * output + tap",
                    "RGB CHW affine normalization",
                    "optional BatchNorm folding and ReLU6"
                ],
                rejectionReason: nil
            )
        } catch let error as NativePlaneStemValidationError {
            return Self(
                compatible: false,
                modelLineage: spec.modelLineage,
                outputChannels: spec.outputChannels,
                supportedSemantics: [],
                rejectionReason: error.localizedDescription
            )
        } catch {
            return Self(
                compatible: false,
                modelLineage: spec.modelLineage,
                outputChannels: spec.outputChannels,
                supportedSemantics: [],
                rejectionReason: String(describing: error)
            )
        }
    }
}
