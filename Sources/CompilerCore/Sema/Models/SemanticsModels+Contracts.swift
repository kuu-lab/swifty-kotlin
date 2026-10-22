public enum ContractReturnCondition: String, Equatable, Sendable, Codable {
    case normally, returnsTrue, returnsFalse, returnsNull, returnsNotNull
}

public enum ContractArgumentCondition: String, Equatable, Sendable, Codable {
    case nonNull, booleanTrue, booleanFalse, isType
}

public enum ContractImplicationTarget: Equatable, Sendable, Codable {
    case valueParameter(Int)
    case extensionReceiver
}

public struct ContractImplicationEffect: Equatable, Sendable, Codable {
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

public struct ContractNonNullEffect: Equatable, Sendable, Codable {
    public let parameterSymbol: SymbolID
    public let appliesOnAnyReturn: Bool

    public init(parameterSymbol: SymbolID, appliesOnAnyReturn: Bool) {
        self.parameterSymbol = parameterSymbol
        self.appliesOnAnyReturn = appliesOnAnyReturn
    }
}

public enum ContractReturnsEffect: Equatable, Sendable, Codable {
    case returnsNormally
    /// `conditionParameterIndex`: heuristic index of the first Boolean parameter,
    /// used by downstream smart-cast analysis (e.g. `require(condition)` patterns).
    /// May be nil if no Boolean parameter exists.
    case returnsBooleanValue(expectedValue: Bool, conditionParameterIndex: Int?)
}

public struct ContractCallsInPlaceEffect: Equatable, Sendable, Codable, CustomStringConvertible {
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

public enum InvocationKind: String, Equatable, Sendable, Codable {
    case atMostOnce = "AT_MOST_ONCE"
    case atLeastOnce = "AT_LEAST_ONCE"
    case exactlyOnce = "EXACTLY_ONCE"
    case unknown = "UNKNOWN"
}

public struct ContractConditionEffect: Equatable, Sendable, Codable, CustomStringConvertible {
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
