/// Captures the type arguments inferred for one inline expansion and applies
/// them to the types carried by the copied KIR expressions.
///
/// The mapping is deliberately built from the inline function's declared
/// parameter types and the call-site expression types. It does not invoke
/// overload resolution or constraint solving; those responsibilities belong to
/// Sema and have already completed before lowering starts.
struct InlineTypeSubstitution {
    let substitution: [TypeVarID: TypeID]
    let typeVarBySymbol: [SymbolID: TypeVarID]

    /// Builds a substitution for `inlineTarget` from the concrete arguments at
    /// the call site. Imported inline functions use the same path because their
    /// materialized KIR carries the same parameter and function signature data.
    static func build(
        inlineTarget: KIRFunction,
        arguments: [KIRExprID],
        module: KIRModule,
        ctx: KIRContext
    ) -> InlineTypeSubstitution? {
        guard let sema = ctx.sema,
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
            collect(
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
        return InlineTypeSubstitution(
            substitution: substitution,
            typeVarBySymbol: typeVarBySymbol
        )
    }

    /// Applies this expansion's substitution to an optional KIR type.
    func applying(to type: TypeID?, in ctx: KIRContext) -> TypeID? {
        guard let type, let sema = ctx.sema else {
            return type
        }
        return sema.types.substituteTypeParameters(
            in: type,
            substitution: substitution,
            typeVarBySymbol: typeVarBySymbol
        )
    }

    /// Returns the concrete type when this is the unambiguous one-variable
    /// substitution used by the nullable `generateSequence` bridge path.
    var soleSubstitutedType: TypeID? {
        guard substitution.count == 1 else {
            return nil
        }
        return substitution.values.first
    }

    private static func collect(
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
                guard let expectedInner = typeArgumentPayload(expectedArg),
                      let actualInner = typeArgumentPayload(actualArg)
                else {
                    continue
                }
                collect(
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
                collect(
                    expected: expectedReceiver,
                    actual: actualReceiver,
                    sema: sema,
                    typeVarBySymbol: typeVarBySymbol,
                    substitution: &substitution
                )
            }
            for (expectedParam, actualParam) in zip(expectedFunction.params, actualFunction.params) {
                collect(
                    expected: expectedParam,
                    actual: actualParam,
                    sema: sema,
                    typeVarBySymbol: typeVarBySymbol,
                    substitution: &substitution
                )
            }
            collect(
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
            collect(
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

    private static func typeArgumentPayload(_ arg: TypeArg) -> TypeID? {
        switch arg {
        case let .invariant(type), let .out(type), let .in(type):
            type
        case .star:
            nil
        }
    }
}

/// Builds the hidden-argument bindings used when an inline body refers to a
/// reified type parameter. Keeping this lookup separate from type substitution
/// makes the token-symbol convention explicit and keeps token flow independent
/// from type inference.
enum InlineReifiedTypeTokens {
    static func buildTypeParamTokenValues(
        inlineTarget: KIRFunction,
        parameterValues: [SymbolID: KIRExprID],
        ctx: KIRContext
    ) -> [SymbolID: KIRExprID] {
        guard let sema = ctx.sema,
              let sig = sema.symbols.functionSignature(for: inlineTarget.symbol),
              !sig.reifiedTypeParameterIndices.isEmpty
        else {
            return [:]
        }
        var result: [SymbolID: KIRExprID] = [:]
        for index in sig.reifiedTypeParameterIndices.sorted() {
            guard index < sig.typeParameterSymbols.count else { continue }
            let typeParamSymbol = sig.typeParameterSymbols[index]
            let tokenSymbol = SyntheticSymbolScheme.reifiedTypeTokenSymbol(for: typeParamSymbol)
            if let tokenArg = parameterValues[tokenSymbol] {
                result[typeParamSymbol] = tokenArg
            }
        }
        return result
    }
}
