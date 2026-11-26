extension TypeCheckHelpers {
    func lexicalTypeParameterSymbols(in ctx: TypeInferenceContext) -> Set<SymbolID> {
        (ctx.scope as? BaseScope)?.lexicalTypeParameterSymbols() ?? []
    }

    func callableReferenceExpectedTypeHasInferenceParameters(
        _ type: TypeID,
        inferenceParameters: Set<SymbolID>,
        sema: SemaModule
    ) -> Bool {
        guard !inferenceParameters.isEmpty else { return false }
        func contains(_ candidate: TypeID) -> Bool {
            callableReferenceExpectedTypeHasInferenceParameters(
                candidate, inferenceParameters: inferenceParameters, sema: sema
            )
        }
        switch sema.types.kind(of: sema.types.makeNonNullable(type)) {
        case let .typeParam(typeParam):
            return typeParam.capture == nil && inferenceParameters.contains(typeParam.symbol)
        case let .classType(classType):
            return sema.types.allTypeArguments(for: classType).contains { argument in
                switch argument {
                case let .invariant(inner), let .out(inner), let .in(inner):
                    return contains(inner)
                case .star:
                    return false
                }
            }
        case let .functionType(functionType):
            return functionType.contextReceivers.contains(where: contains)
                || (functionType.receiver.map(contains) ?? false)
                || functionType.params.contains(where: contains)
                || contains(functionType.returnType)
        case let .kClassType(kClassType):
            return contains(kClassType.argument)
        case let .intersection(members):
            return members.contains(where: contains)
        default:
            return false
        }
    }

    func postponedCallableReferenceReturnTypeParameter(
        _ type: TypeID?, inferenceParameters: Set<SymbolID>, sema: SemaModule
    ) -> SymbolID? {
        guard let type, case let .functionType(function) = sema.types.kind(of: type),
              case let .typeParam(parameter) = sema.types.kind(of: function.returnType),
              inferenceParameters.contains(parameter.symbol) else { return nil }
        let inputs = function.contextReceivers + (function.receiver.map { [$0] } ?? []) + function.params
        guard !inputs.contains(where: { input in
            inferenceParameters.contains { sema.types.typeContainsTypeParam(input, symbol: $0) }
        }) else { return nil }
        return parameter.symbol
    }
}
