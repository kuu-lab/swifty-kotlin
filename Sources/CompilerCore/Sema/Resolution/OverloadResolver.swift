public struct CallArg {
    public let label: InternedString?
    public let isSpread: Bool
    public let type: TypeID
    public let signedIntegerLiteral: Int64?
    public let unsignedIntegerLiteral: UInt64?
    public let isTrailingLambda: Bool?
    public let isLambdaLiteral: Bool
    public let isCallableReference: Bool
    public let bindsToLastParameter: Bool

    public init(
        label: InternedString? = nil,
        isSpread: Bool = false,
        type: TypeID,
        signedIntegerLiteral: Int64? = nil,
        unsignedIntegerLiteral: UInt64? = nil,
        isTrailingLambda: Bool? = nil,
        isLambdaLiteral: Bool = false,
        isCallableReference: Bool = false,
        bindsToLastParameter: Bool = false
    ) {
        self.label = label
        self.isSpread = isSpread
        self.type = type
        self.signedIntegerLiteral = signedIntegerLiteral
        self.unsignedIntegerLiteral = unsignedIntegerLiteral
        self.isTrailingLambda = isTrailingLambda
        self.isLambdaLiteral = isLambdaLiteral
        self.isCallableReference = isCallableReference
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
            isTrailingLambda: trailingLambdaPosition(argument, callRange: callRange, ast: ast),
            isLambdaLiteral: {
                guard let expr = ast.arena.expr(argument.expr) else { return false }
                if case .lambdaLiteral = expr { return true }
                return false
            }(),
            isCallableReference: {
                guard let expr = ast.arena.expr(argument.expr) else { return false }
                if case .callableRef = expr { return true }
                return false
            }()
        )
    }
}

func hasImplicitIntegerCoercionAnnotation(
    _ annotations: [MetadataAnnotationRecord],
    forParameter: Bool
) -> Bool {
    annotations.contains { annotation in
        guard annotation.annotationFQName == KnownCompilerAnnotation.implicitIntegerCoercion.qualifiedName else {
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

public struct TypeAliasConstructorContext {
    public let typeParameterSymbols: [SymbolID]
    public let expandedType: TypeID
    public let resultType: TypeID?
    public let typeAliasSymbol: SymbolID?
    public let innerOuterReceiverType: TypeID?
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
    public let dispatchReceiverTypes: [TypeID]
    public let boundObjectDispatchReceiverCandidates: Set<SymbolID>
    public let typeAliasConstructor: TypeAliasConstructorContext?
    public let elvisLhsExpectedTypeHint: Bool
    public let elvisRhsCallResultTypeHint: TypeID?
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
    public let failureDiagnostics: [Diagnostic]

    public init(viableCandidates: [ProbedCallCandidate], failureDiagnostics: [Diagnostic] = []) {
        self.viableCandidates = viableCandidates
        self.failureDiagnostics = failureDiagnostics
    }
}

final class OverloadResolver {
    var cacheContext: SemaCacheContext?

    init() {}
}
