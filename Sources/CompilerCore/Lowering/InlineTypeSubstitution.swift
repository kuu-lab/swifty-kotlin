/// Owns the type-argument mapping used while splicing an inline body into its
/// caller.  The mapping is built from the callee's parameter/argument types,
/// then delegated to `TypeSystem` for recursive substitution.  Reified token
/// values are kept here as well because they are the other hidden arguments
/// whose symbols are rewritten while the same body is being spliced.
struct InlineTypeSubstitution {
    let substitution: [TypeVarID: TypeID]
    let typeVarBySymbol: [SymbolID: TypeVarID]

    static func buildInlineTypeSubstitution(
        inlineTarget: KIRFunction,
        arguments: [KIRExprID],
        module: KIRModule,
        sema: SemaModule?
    ) -> InlineTypeSubstitution? {
        guard let sema,
              let signature = sema.symbols.functionSignature(for: inlineTarget.symbol),
              !signature.typeParameterSymbols.isEmpty
        else {
            return nil
        }

        let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
        var substitution: [TypeVarID: TypeID] = [:]
        for (parameter, argument) in zip(inlineTarget.params, arguments) {
            guard let argumentType = module.arena.exprType(argument) else {
                continue
            }
            collectInlineTypeSubstitution(
                expected: parameter.type,
                actual: argumentType,
                sema: sema,
                typeVarBySymbol: typeVarBySymbol,
                substitution: &substitution
            )
        }
        guard !substitution.isEmpty else {
            return nil
        }
        return InlineTypeSubstitution(substitution: substitution, typeVarBySymbol: typeVarBySymbol)
    }

    static func buildTypeParamTokenValues(
        inlineTarget: KIRFunction,
        parameterValues: [SymbolID: KIRExprID],
        sema: SemaModule?
    ) -> [SymbolID: KIRExprID] {
        guard let sema,
              let signature = sema.symbols.functionSignature(for: inlineTarget.symbol),
              !signature.reifiedTypeParameterIndices.isEmpty
        else {
            return [:]
        }
        var result: [SymbolID: KIRExprID] = [:]
        for index in signature.reifiedTypeParameterIndices.sorted() {
            guard index < signature.typeParameterSymbols.count else { continue }
            let typeParamSymbol = signature.typeParameterSymbols[index]
            let tokenSymbol = SyntheticSymbolScheme.reifiedTypeTokenSymbol(for: typeParamSymbol)
            if let tokenArg = parameterValues[tokenSymbol] {
                result[typeParamSymbol] = tokenArg
            }
        }
        return result
    }

    static func substituteInlineType(
        _ type: TypeID?,
        using inlineTypeSubstitution: InlineTypeSubstitution?,
        sema: SemaModule?
    ) -> TypeID? {
        guard let type,
              let inlineTypeSubstitution,
              let sema
        else {
            return type
        }
        return sema.types.substituteTypeParameters(
            in: type,
            substitution: inlineTypeSubstitution.substitution,
            typeVarBySymbol: inlineTypeSubstitution.typeVarBySymbol
        )
    }

    private static func collectInlineTypeSubstitution(
        expected: TypeID,
        actual: TypeID,
        sema: SemaModule,
        typeVarBySymbol: [SymbolID: TypeVarID],
        substitution: inout [TypeVarID: TypeID]
    ) {
        switch sema.types.kind(of: expected) {
        case let .typeParam(typeParam):
            guard let typeVar = typeVarBySymbol[typeParam.symbol],
                  substitution[typeVar] == nil
            else {
                return
            }
            substitution[typeVar] = actual

        case let .classType(expectedClass):
            guard let actualClass = resolveClassType(actual, sema: sema),
                  expectedClass.classSymbol == actualClass.classSymbol
            else {
                return
            }
            for (expectedArg, actualArg) in zip(expectedClass.args, actualClass.args) {
                guard let expectedInner = inlineTypeArgPayload(expectedArg),
                      let actualInner = inlineTypeArgPayload(actualArg)
                else {
                    continue
                }
                collectInlineTypeSubstitution(
                    expected: expectedInner,
                    actual: actualInner,
                    sema: sema,
                    typeVarBySymbol: typeVarBySymbol,
                    substitution: &substitution
                )
            }

        case let .functionType(expectedFunction):
            guard case let .functionType(actualFunction) = sema.types.kind(of: sema.types.makeNonNullable(actual)) else {
                return
            }
            if let expectedReceiver = expectedFunction.receiver,
               let actualReceiver = actualFunction.receiver
            {
                collectInlineTypeSubstitution(
                    expected: expectedReceiver,
                    actual: actualReceiver,
                    sema: sema,
                    typeVarBySymbol: typeVarBySymbol,
                    substitution: &substitution
                )
            }
            for (expectedParam, actualParam) in zip(expectedFunction.params, actualFunction.params) {
                collectInlineTypeSubstitution(
                    expected: expectedParam,
                    actual: actualParam,
                    sema: sema,
                    typeVarBySymbol: typeVarBySymbol,
                    substitution: &substitution
                )
            }
            collectInlineTypeSubstitution(
                expected: expectedFunction.returnType,
                actual: actualFunction.returnType,
                sema: sema,
                typeVarBySymbol: typeVarBySymbol,
                substitution: &substitution
            )

        case let .kClassType(expectedKClass):
            guard case let .kClassType(actualKClass) = sema.types.kind(of: sema.types.makeNonNullable(actual)) else {
                return
            }
            collectInlineTypeSubstitution(
                expected: expectedKClass.argument,
                actual: actualKClass.argument,
                sema: sema,
                typeVarBySymbol: typeVarBySymbol,
                substitution: &substitution
            )

        default:
            return
        }
    }

    private static func inlineTypeArgPayload(_ arg: TypeArg) -> TypeID? {
        switch arg {
        case let .invariant(type), let .out(type), let .in(type):
            return type
        case .star:
            return nil
        }
    }
}
