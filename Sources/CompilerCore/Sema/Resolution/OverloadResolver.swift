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

    public init(
        label: InternedString? = nil,
        isSpread: Bool = false,
        type: TypeID,
        signedIntegerLiteral: Int64? = nil,
        unsignedIntegerLiteral: UInt64? = nil,
        isTrailingLambda: Bool? = nil
    ) {
        self.label = label
        self.isSpread = isSpread
        self.type = type
        self.signedIntegerLiteral = signedIntegerLiteral
        self.unsignedIntegerLiteral = unsignedIntegerLiteral
        self.isTrailingLambda = isTrailingLambda
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

/// The alias's parameters remain inference variables until overload resolution.
public struct TypeAliasConstructorContext {
    public let typeParameterSymbols: [SymbolID]
    public let expandedType: TypeID

    public init(typeParameterSymbols: [SymbolID], expandedType: TypeID) {
        self.typeParameterSymbols = typeParameterSymbols
        self.expandedType = expandedType
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

    public init(range: SourceRange, calleeName: InternedString, args: [CallArg], explicitTypeArgs: [TypeID] = [], dispatchReceiverTypes: [TypeID] = [], boundObjectDispatchReceiverCandidates: Set<SymbolID> = [], typeAliasConstructor: TypeAliasConstructorContext? = nil) {
        self.range = range
        self.calleeName = calleeName
        self.args = args
        self.explicitTypeArgs = explicitTypeArgs
        self.dispatchReceiverTypes = dispatchReceiverTypes
        self.boundObjectDispatchReceiverCandidates = boundObjectDispatchReceiverCandidates
        self.typeAliasConstructor = typeAliasConstructor
    }
}

public struct ResolvedCall {
    public let chosenCallee: SymbolID?
    public let substitutedTypeArguments: [TypeVarID: TypeID]
    public let parameterMapping: [Int: Int]
    public let diagnostic: Diagnostic?
    public let defaultArgumentOwner: SymbolID?

    public init(
        chosenCallee: SymbolID?,
        substitutedTypeArguments: [TypeVarID: TypeID],
        parameterMapping: [Int: Int],
        diagnostic: Diagnostic?,
        defaultArgumentOwner: SymbolID? = nil
    ) {
        self.chosenCallee = chosenCallee
        self.substitutedTypeArguments = substitutedTypeArguments
        self.parameterMapping = parameterMapping
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
