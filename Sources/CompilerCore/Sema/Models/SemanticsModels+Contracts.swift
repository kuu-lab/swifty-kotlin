public enum ContractReturnCondition: String, Equatable, Sendable {
    case normally, returnsTrue, returnsFalse, returnsNull, returnsNotNull
}

public enum ContractArgumentCondition: String, Equatable, Sendable {
    case nonNull, booleanTrue, booleanFalse, isType
}

public enum ContractImplicationTarget: Equatable, Sendable {
    case valueParameter(Int)
    case extensionReceiver
}

public struct ContractImplicationEffect: Equatable, Sendable {
    public let target: ContractImplicationTarget
    public let returnCondition: ContractReturnCondition
    public let argumentCondition: ContractArgumentCondition

    public let targetType: TypeID?
    public let targetTypeSignature: String?

    public init(parameterIndex: Int, returnCondition: ContractReturnCondition, argumentCondition: ContractArgumentCondition, targetType: TypeID? = nil, targetTypeSignature: String? = nil) {
        self.init(target: .valueParameter(parameterIndex), returnCondition: returnCondition,
                  argumentCondition: argumentCondition, targetType: targetType,
                  targetTypeSignature: targetTypeSignature)
    }

    public init(target: ContractImplicationTarget, returnCondition: ContractReturnCondition,
                argumentCondition: ContractArgumentCondition, targetType: TypeID? = nil,
                targetTypeSignature: String? = nil) {
        self.target = target
        self.returnCondition = returnCondition
        self.argumentCondition = argumentCondition
        self.targetType = targetType
        self.targetTypeSignature = targetTypeSignature
    }
}

public struct ContractNonNullEffect: Equatable, Sendable {
    public let parameterSymbol: SymbolID
    public let appliesOnAnyReturn: Bool

    public init(parameterSymbol: SymbolID, appliesOnAnyReturn: Bool) {
        self.parameterSymbol = parameterSymbol
        self.appliesOnAnyReturn = appliesOnAnyReturn
    }
}

/// Represents a `contract { returns() }` or `contract { returns(true/false) }` effect
/// indicating the function guarantees normal return (optionally with a specific Boolean
/// return value).
///
/// - Bare `returns()`: the function guarantees it will return normally (not throw).
/// - `returns(true)` / `returns(false)`: the function guarantees its *return value*
///   will be the given Boolean constant on normal completion.
///
/// Models the kind of `returns(...)` contract effect.
///
/// - `returnsNormally`: bare `returns()` -- the function guarantees normal return.
/// - `returnsBooleanValue(Bool, conditionParameterIndex: Int?)`: `returns(true)` or
///   `returns(false)` -- the function guarantees a specific Boolean return value on
///   normal completion.  `conditionParameterIndex` is a heuristic to locate the first
///   Boolean parameter for downstream smart-cast patterns like `require(condition)`.
public enum ContractReturnsEffect: Equatable, Sendable {
    /// Bare `returns()` -- the function guarantees normal return without specifying
    /// a particular return value.
    case returnsNormally
    /// `returns(true)` or `returns(false)` -- the function guarantees a specific
    /// Boolean return value on normal completion.
    /// - `expectedValue`: the Boolean value the function returns (`true` or `false`).
    /// - `conditionParameterIndex`: heuristic index of the first Boolean parameter,
    ///   used by downstream smart-cast analysis (e.g. `require(condition)` patterns).
    ///   May be nil if no Boolean parameter exists.
    case returnsBooleanValue(expectedValue: Bool, conditionParameterIndex: Int?)
}

/// STDLIB-592: `contract { callsInPlace(block, InvocationKind.EXACTLY_ONCE) }` effect.
/// Records that a lambda parameter is guaranteed to be invoked a specific number of times.
public struct ContractCallsInPlaceEffect: Equatable, Sendable, CustomStringConvertible {
    public let parameterSymbol: SymbolID
    public let kind: InvocationKind

    public init(parameterSymbol: SymbolID, kind: InvocationKind) {
        self.parameterSymbol = parameterSymbol
        self.kind = kind
    }

    public var description: String {
        return "\(parameterSymbol.rawValue) \(kind.rawValue)"
    }
}

/// Kotlin `InvocationKind` enum modelling how many times a lambda parameter is called.
public enum InvocationKind: String, Equatable, Sendable {
    case atMostOnce = "AT_MOST_ONCE"
    case atLeastOnce = "AT_LEAST_ONCE"
    case exactlyOnce = "EXACTLY_ONCE"
    case unknown = "UNKNOWN"
}

/// STDLIB-591: `contract { returns() implies (condition) }` effect where `condition`
/// is a Boolean parameter.  After normal return, the argument expression at
/// `conditionParameterIndex` is guaranteed true, enabling smart casts derived from
/// that expression (e.g. `require(x != null)` narrows `x` to non-null).
public struct ContractConditionEffect: Equatable, Sendable, CustomStringConvertible {
    /// Index into the function signature's value-parameter list whose argument
    /// expression is guaranteed true on normal return.
    public let conditionParameterIndex: Int

    /// When to apply the smart cast:
    /// - `nil`: applies on any normal return (`returns() implies condition`)
    /// - `true`: applies when function returns true (`returns(true) implies condition`)
    /// - `false`: applies when function returns false (`returns(false) implies condition`)
    public let returnsValue: Bool?

    public init(conditionParameterIndex: Int, returnsValue: Bool? = nil) {
        self.conditionParameterIndex = conditionParameterIndex
        self.returnsValue = returnsValue
    }

    public var description: String {
        return "\(conditionParameterIndex) \(String(describing: returnsValue))"
    }
}
