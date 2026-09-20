/// Coarse-grained stage markers for the KIR lowering pipeline.
///
/// The stages intentionally describe contracts between passes, not every
/// individual rewrite.  New stages should be added only when a pass boundary
/// changes the invariants that later passes may rely on.
public enum KIRStage: Int, CaseIterable, Comparable, CustomStringConvertible, Sendable {
    /// KIR emitted directly from the AST/KIR builders.
    case raw = 0
    /// KIR after tail-recursion rewriting, before block normalization.
    case tailrecLowered = 1
    /// KIR after source-level desugaring and structural normalization.
    case desugared = 2
    /// KIR after value-class representation boundaries are normalized.
    case valueClassUnboxed = 3
    /// KIR after property accesses have been lowered to accessors.
    case propertyLowered = 4
    /// KIR after integer-width semantics have been made explicit.
    case integerNarrowed = 5
    /// KIR whose calls and values satisfy the runtime ABI contract.
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

/// A lowering pass was placed at a stage other than the one it declares.
///
/// This is thrown only by debug builds.  Release builds still record the
/// declared output stage, keeping the contract zero-cost in production while
/// retaining the marker for diagnostics and future consumers.
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
