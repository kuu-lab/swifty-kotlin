public struct TypeID: Hashable, Sendable, Codable {
    public let rawValue: Int32

    public static let invalid = TypeID(rawValue: -1)

    public init(rawValue: Int32 = -1) {
        self.rawValue = rawValue
    }
}

public enum PrimitiveType: String, Hashable, Sendable, Codable {
    case boolean
    case char
    case int
    case long
    case float
    case double
    case uint
    case ulong
    case ubyte
    case ushort
    case byte
    case short
}

public extension PrimitiveType {
    var kotlinName: String {
        switch self {
        case .boolean: "Boolean"
        case .char: "Char"
        case .int: "Int"
        case .long: "Long"
        case .float: "Float"
        case .double: "Double"
        case .uint: "UInt"
        case .ulong: "ULong"
        case .ubyte: "UByte"
        case .ushort: "UShort"
        case .byte: "Byte"
        case .short: "Short"
        }
    }

    /// Primitives that can collide with `runtimeNullSentinelInt` inside a
    /// `P?`-typed slot: `Long.MIN_VALUE`, `ULong` 2^63 and `-0.0` bit-equal
    /// the sentinel directly, and `-0.0f` equals the sentinel's truncation
    /// under the f32 comparison a `Float?` null check lowers to. A raw
    /// scalar of one of these stored in a nullable slot is read as `null`
    /// by every null check (KUU-854), so writes must keep the slot
    /// box-or-sentinel.
    var rawValueCollidesWithNullSentinel: Bool {
        switch self {
        case .long, .ulong, .double, .float:
            true
        case .boolean, .char, .int, .uint, .ubyte, .ushort, .byte, .short:
            false
        }
    }
}

public enum Nullability: Hashable, Sendable, Codable {
    case nonNull
    case nullable
    case platformType // T! — nullability unknown (from external declarations)

    /// Nullability used by legacy link-name/signature encodings with two
    /// states. Library metadata can separately preserve platform types as P<T>.
    public var erasedForMetadata: Nullability {
        switch self {
        case .nonNull:
            .nonNull
        case .nullable, .platformType:
            .nullable
        }
    }
}

public struct ClassType: Hashable, Sendable, Codable {
    public let classSymbol: SymbolID
    public let args: [TypeArg]
    /// Type arguments captured from enclosing owners of an `inner` class,
    /// ordered from the outermost owner to the immediate owner.
    public let enclosingTypeArgs: [TypeArg]
    public let nullability: Nullability

    public init(
        classSymbol: SymbolID,
        args: [TypeArg] = [],
        enclosingTypeArgs: [TypeArg] = [],
        nullability: Nullability = .nonNull
    ) {
        self.classSymbol = classSymbol
        self.args = args
        self.enclosingTypeArgs = enclosingTypeArgs
        self.nullability = nullability
    }
}

public enum TypeVariance: Hashable, Sendable, Codable {
    case invariant
    case out
    case `in`
}

public enum TypeArg: Hashable, Sendable, Codable {
    case invariant(TypeID)
    case out(TypeID)
    case `in`(TypeID)
    case star
}

extension TypeArg {
    func mapTypes(_ transform: (TypeID) -> TypeID) -> TypeArg {
        switch self {
        case let .invariant(type): .invariant(transform(type))
        case let .out(type): .out(transform(type))
        case let .in(type): .in(transform(type))
        case .star: .star
        }
    }
}

public struct TypeParamType: Hashable, Sendable, Codable {
    public let symbol: SymbolID
    public let nullability: Nullability
    /// An existential parameter captured from a use-site projection. Its identity
    /// is local to inference; the declaration symbol still supplies ABI erasure.
    public let capture: CapturedTypeBounds?

    public init(symbol: SymbolID, nullability: Nullability = .nonNull, capture: CapturedTypeBounds? = nil) {
        self.symbol = symbol
        self.nullability = nullability
        self.capture = capture
    }
}

/// Identifies a projected receiver conversion that can be materialized at
/// multiple member-call sites while denoting the same captured type.
public struct CapturedTypeOrigin: Hashable, Sendable, Codable {
    public let receiverType: TypeID
    public let parameter: SymbolID
    public let argumentIndex: Int

    public init(receiverType: TypeID, parameter: SymbolID, argumentIndex: Int) {
        self.receiverType = receiverType
        self.parameter = parameter
        self.argumentIndex = argumentIndex
    }
}

public struct CapturedTypeBounds: Hashable, Sendable, Codable {
    public let identity: Int
    public let lower: TypeID
    public let upper: TypeID
    public let writeForbidden: Bool
    public let origin: CapturedTypeOrigin?

    public init(
        identity: Int,
        lower: TypeID,
        upper: TypeID,
        writeForbidden: Bool = false,
        origin: CapturedTypeOrigin? = nil
    ) {
        self.identity = identity
        self.lower = lower
        self.upper = upper
        self.writeForbidden = writeForbidden
        self.origin = origin
    }

    func isSameProjectedCapture(as other: CapturedTypeBounds) -> Bool {
        if self == other { return true }
        guard let origin, let otherOrigin = other.origin, origin == otherOrigin else { return false }
        return lower == other.lower && upper == other.upper && writeForbidden == other.writeForbidden
    }
}

public struct FunctionType: Hashable, Sendable, Codable, CustomStringConvertible {
    public let contextReceivers: [TypeID]
    public let receiver: TypeID?
    public let params: [TypeID]
    public let returnType: TypeID
    public let isSuspend: Bool
    public let isCallableReference: Bool
    public let nullability: Nullability
    public let `throws`: [TypeID]

    public init(
        contextReceivers: [TypeID] = [],
        receiver: TypeID? = nil,
        params: [TypeID],
        returnType: TypeID,
        isSuspend: Bool = false,
        isCallableReference: Bool = false,
        nullability: Nullability = .nonNull,
        `throws`: [TypeID] = []
    ) {
        self.contextReceivers = contextReceivers
        self.receiver = receiver
        self.params = params
        self.returnType = returnType
        self.isSuspend = isSuspend
        self.isCallableReference = isCallableReference
        self.nullability = nullability
        self.`throws` = `throws`
    }

    public var description: String {
        return "(\(params.count)) -> \(returnType.rawValue) throws: \(`throws`.count)"
    }
}

/// Represents invariant `kotlin.reflect.KClass<T>`, including `T::class`.
/// Use-site projections remain nominal `ClassType` arguments.
public struct KClassType: Hashable, Sendable, Codable {
    public let argument: TypeID
    public let nullability: Nullability

    public init(argument: TypeID, nullability: Nullability = .nonNull) {
        self.argument = argument
        self.nullability = nullability
    }
}

public enum TypeKind: Hashable, Codable {
    case error
    case unit
    /// A value-bearing Unit slot that can also contain the null sentinel.
    case nullableUnit
    /// A flexible Java Unit value with lower bound Unit and upper bound Unit?.
    case platformUnit
    case nothing(Nullability)
    case any(Nullability)

    case stringStruct(Nullability)
    case primitive(PrimitiveType, Nullability)
    case classType(ClassType)
    case typeParam(TypeParamType)
    case functionType(FunctionType)
    case intersection([TypeID])
    case kClassType(KClassType)
}

extension TypeKind {
    /// Rewrites nested TypeIDs while preserving nominal SymbolIDs.
    func mapTypes(_ transform: (TypeID) -> TypeID) -> TypeKind {
        switch self {
        case .error, .unit, .nullableUnit, .platformUnit, .nothing, .any, .stringStruct, .primitive:
            return self
        case let .typeParam(type):
            guard let capture = type.capture else { return self }
            let origin = capture.origin.map {
                CapturedTypeOrigin(
                    receiverType: transform($0.receiverType),
                    parameter: $0.parameter,
                    argumentIndex: $0.argumentIndex
                )
            }
            return .typeParam(TypeParamType(
                symbol: type.symbol,
                nullability: type.nullability,
                capture: CapturedTypeBounds(
                    identity: capture.identity,
                    lower: transform(capture.lower),
                    upper: transform(capture.upper),
                    writeForbidden: capture.writeForbidden,
                    origin: origin
                )
            ))
        case let .classType(type):
            return .classType(ClassType(
                classSymbol: type.classSymbol,
                args: type.args.map { $0.mapTypes(transform) },
                enclosingTypeArgs: type.enclosingTypeArgs.map { $0.mapTypes(transform) },
                nullability: type.nullability
            ))
        case let .functionType(type):
            return .functionType(FunctionType(
                contextReceivers: type.contextReceivers.map(transform),
                receiver: type.receiver.map(transform), params: type.params.map(transform),
                returnType: transform(type.returnType), isSuspend: type.isSuspend,
                isCallableReference: type.isCallableReference, nullability: type.nullability,
                throws: type.throws.map(transform)
            ))
        case let .intersection(parts):
            return .intersection(parts.map(transform))
        case let .kClassType(type):
            return .kClassType(KClassType(argument: transform(type.argument), nullability: type.nullability))
        }
    }

}
