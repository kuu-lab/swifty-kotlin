extension TypeCheckHelpers {
    /// Walk every lexical tier so a shadowed outer parameter stays rigid too.
    func lexicalTypeParameterSymbols(in ctx: TypeInferenceContext) -> Set<SymbolID> {
        (ctx.scope as? BaseScope)?.lexicalTypeParameterSymbols() ?? []
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
