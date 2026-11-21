public enum KIRStage: Int, CaseIterable, Comparable, CustomStringConvertible, Sendable {
    case raw = 0
    case tailrecLowered = 1
    case desugared = 2
    case valueClassUnboxed = 3
    case propertyLowered = 4
    case integerNarrowed = 5
    case abiLowered = 6

    public static func < (lhs: KIRStage, rhs: KIRStage) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var description: String {
        switch self {
        case .raw:
            return "raw"
        case .tailrecLowered:
            return "tailrecLowered"
        case .desugared:
            return "desugared"
        case .valueClassUnboxed:
            return "valueClassUnboxed"
        case .propertyLowered:
            return "propertyLowered"
        case .integerNarrowed:
            return "integerNarrowed"
        case .abiLowered:
            return "abiLowered"
        }
    }
}

enum KIRStageViolation: Error, Equatable, CustomStringConvertible {
    case unexpectedInput(
        passName: String,
        required: KIRStage,
        actual: KIRStage
    )
    case regressingOutput(
        passName: String,
        required: KIRStage,
        produced: KIRStage
    )

    var description: String {
        switch self {
        case let .unexpectedInput(passName, required, actual):
            return "Lowering pass \(passName) requires KIR stage \(required), but the module is at \(actual)."
        case let .regressingOutput(passName, required, produced):
            return "Lowering pass \(passName) declares output stage \(produced), which regresses from required stage \(required)."
        }
    }
}
