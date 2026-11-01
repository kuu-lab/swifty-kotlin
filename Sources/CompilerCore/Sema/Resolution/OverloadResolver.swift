public struct CallArg {
    public let label: InternedString?
    public let isSpread: Bool
    public let type: TypeID
    /// Keep a literal's value until each candidate's parameter type is known.
    /// A pre-inferred Int/UInt alone loses contextual integer adaptation.
    public let signedIntegerLiteral: Int64?
    public let unsignedIntegerLiteral: UInt64?
    /// Source calls distinguish a lambda outside parentheses from ordinary
    /// positional arguments. Nil preserves normalized calls without an AST.
    public let isTrailingLambda: Bool?
    /// Synthetic operator-set calls bind the assigned value to the setter's
    /// final parameter, skipping any defaulted parameters between the indices
    /// and that value.
    public let bindsToLastParameter: Bool

    public init(
        label: InternedString? = nil,
        isSpread: Bool = false,
        type: TypeID,
        signedIntegerLiteral: Int64? = nil,
        unsignedIntegerLiteral: UInt64? = nil,
        isTrailingLambda: Bool? = nil,
        bindsToLastParameter: Bool = false
    ) {
        self.label = label
        self.isSpread = isSpread
        self.type = type
        self.signedIntegerLiteral = signedIntegerLiteral
        self.unsignedIntegerLiteral = unsignedIntegerLiteral
        self.isTrailingLambda = isTrailingLambda
        self.bindsToLastParameter = bindsToLastParameter
    }

    private static func trailingLambdaPosition(
        _ argument: CallArgument, callRange: SourceRange, ast: ASTModule
    ) -> Bool {
        guard case .lambdaLiteral = ast.arena.expr(argument.expr) else { return false }
        return ast.arena.exprRange(argument.expr)?.end == callRange.end
    }

    package static func source(
        _ argument: CallArgument, type: TypeID, callRange: SourceRange, ast: ASTModule,
        signedIntegerLiteral: Int64? = nil, unsignedIntegerLiteral: UInt64? = nil
    ) -> CallArg {
        CallArg(
            label: argument.label, isSpread: argument.isSpread, type: type,
            signedIntegerLiteral: signedIntegerLiteral, unsignedIntegerLiteral: unsignedIntegerLiteral,
            isTrailingLambda: trailingLambdaPosition(argument, callRange: callRange, ast: ast)
        )
    }
}

func hasImplicitIntegerCoercionAnnotation(
    _ annotations: [MetadataAnnotationRecord],
    forParameter: Bool
) -> Bool {
    annotations.contains { annotation in
        guard annotation.annotationFQName == "kotlin.internal.ImplicitIntegerCoercion" else {
            return false
        }
        switch annotation.useSiteTarget?.lowercased() {
        case nil:
            return true
        case "param" where forParameter:
            return true
        case "property" where !forParameter:
            return true
        default:
            return false
        }
    }
}

func implicitSignedIntegerCoercionTargetType(
    _ value: Int64,
    parameterType: TypeID,
    types: TypeSystem
) -> TypeID? {
    guard case let .primitive(primitive, _) = types.kind(of: types.makeNonNullable(parameterType)) else {
        return nil
    }
    return switch primitive {
    case .ubyte where (0 ... Int64(UInt8.max)).contains(value):
        types.ubyteType
    case .ushort where (0 ... Int64(UInt16.max)).contains(value):
        types.ushortType
    case .uint where (0 ... Int64(UInt32.max)).contains(value):
        types.uintType
    case .ulong where value >= 0:
        types.ulongType
    default:
        nil
    }
}

func implicitSignedIntegerCoercionConstant(
    _ value: Int64,
    to parameterType: TypeID,
    types: TypeSystem
) -> KIRExprKind? {
    guard let targetType = implicitSignedIntegerCoercionTargetType(
        value, parameterType: parameterType, types: types
    ), case let .primitive(primitive, _) = types.kind(of: targetType) else {
        return nil
    }
    return switch primitive {
    case .ubyte, .ushort:
        .intLiteral(value)
    case .uint:
        .uintLiteral(UInt64(value))
    case .ulong:
        .ulongLiteral(UInt64(value))
    default:
        nil
    }
}

/// The alias's parameters remain inference variables until overload resolution.
public struct TypeAliasConstructorContext {
    public let typeParameterSymbols: [SymbolID]
    public let expandedType: TypeID
    /// Optional source-level result type when an expect declaration gives the
    /// alias a distinct nominal type from its expanded constructor target.
    public let resultType: TypeID?
    /// The source alias, used for call-site annotations such as opt-in markers.
    public let typeAliasSymbol: SymbolID?
    /// The enclosing instance supplied to a member-style inner constructor call.
    public let innerOuterReceiverType: TypeID?
    /// Alias parameters that map to the enclosing class's type parameters.
    public let outerTypeParameterSymbols: [SymbolID]

    public init(
        typeParameterSymbols: [SymbolID],
        expandedType: TypeID,
        resultType: TypeID? = nil,
        typeAliasSymbol: SymbolID? = nil,
        innerOuterReceiverType: TypeID? = nil,
        outerTypeParameterSymbols: [SymbolID] = []
    ) {
        self.typeParameterSymbols = typeParameterSymbols
        self.expandedType = expandedType
        self.resultType = resultType
        self.typeAliasSymbol = typeAliasSymbol
        self.innerOuterReceiverType = innerOuterReceiverType
        self.outerTypeParameterSymbols = outerTypeParameterSymbols
    }
}

public struct CallExpr {
    public let range: SourceRange
    public let calleeName: InternedString
    public let args: [CallArg]
    public let explicitTypeArgs: [TypeID]
    /// Lexical receivers, innermost first, independently of the extension receiver.
    public let dispatchReceiverTypes: [TypeID]
    /// Direct imports bind these ordinary object members to their singleton.
    /// Explicit member calls must retain their actual receiver type.
    public let boundObjectDispatchReceiverCandidates: Set<SymbolID>
    public let typeAliasConstructor: TypeAliasConstructorContext?
    /// An Elvis branch's peer or enclosing type may guide generic inference
    /// without requiring the call result to be a subtype of that type.
    public let elvisLhsExpectedTypeHint: Bool
    /// A non-null Elvis LHS type may fill unresolved RHS call type variables,
    /// without constraining variables already inferred from call inputs.
    public let elvisRhsCallResultTypeHint: TypeID?
    /// `true` when the call was written with operator syntax (`a + b`,
    /// `x in y`, `a[i]`, `a += b`, `l..r`). kotlinc reports NONE_APPLICABLE
    /// for such calls when several operator candidates are inapplicable,
    /// rather than an argument-type mismatch, so a multi-candidate operator
    /// call keeps the generic no-viable-overload diagnostic.
    public let isOperatorCall: Bool

    public init(range: SourceRange, calleeName: InternedString, args: [CallArg], explicitTypeArgs: [TypeID] = [], dispatchReceiverTypes: [TypeID] = [], boundObjectDispatchReceiverCandidates: Set<SymbolID> = [], typeAliasConstructor: TypeAliasConstructorContext? = nil, elvisLhsExpectedTypeHint: Bool = false, elvisRhsCallResultTypeHint: TypeID? = nil, isOperatorCall: Bool = false) {
        self.range = range
        self.calleeName = calleeName
        self.args = args
        self.explicitTypeArgs = explicitTypeArgs
        self.dispatchReceiverTypes = dispatchReceiverTypes
        self.boundObjectDispatchReceiverCandidates = boundObjectDispatchReceiverCandidates
        self.typeAliasConstructor = typeAliasConstructor
        self.elvisLhsExpectedTypeHint = elvisLhsExpectedTypeHint
        self.elvisRhsCallResultTypeHint = elvisRhsCallResultTypeHint
        self.isOperatorCall = isOperatorCall
    }
}

public struct ResolvedCall {
    public let chosenCallee: SymbolID?
    public let substitutedTypeArguments: [TypeVarID: TypeID]
    public let parameterMapping: [Int: Int]
    /// Maps source argument indices to explicitly supplied context-parameter indices.
    public let contextParameterArgumentMapping: [Int: Int]
    public let diagnostic: Diagnostic?
    public let defaultArgumentOwner: SymbolID?

    public init(
        chosenCallee: SymbolID?,
        substitutedTypeArguments: [TypeVarID: TypeID],
        parameterMapping: [Int: Int],
        contextParameterArgumentMapping: [Int: Int] = [:],
        diagnostic: Diagnostic?,
        defaultArgumentOwner: SymbolID? = nil
    ) {
        self.chosenCallee = chosenCallee
        self.substitutedTypeArguments = substitutedTypeArguments
        self.parameterMapping = parameterMapping
        self.contextParameterArgumentMapping = contextParameterArgumentMapping
        self.diagnostic = diagnostic
        self.defaultArgumentOwner = defaultArgumentOwner
    }
}

public struct ProbedCallCandidate {
    public let symbol: SymbolID

    public init(symbol: SymbolID) {
        self.symbol = symbol
    }
}

public struct ProbedCallResult {
    public let viableCandidates: [ProbedCallCandidate]

    public init(viableCandidates: [ProbedCallCandidate]) {
        self.viableCandidates = viableCandidates
    }
}

final class OverloadResolver {
    var cacheContext: SemaCacheContext?

    init() {}
}
