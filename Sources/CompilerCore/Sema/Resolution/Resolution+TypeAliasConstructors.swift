extension OverloadResolver {
    /// Specialize only this candidate, retaining the original callable symbol
    /// and its parameter labels/defaults for binding and code generation.
    func typeAliasConstructorSignature(
        _ alias: TypeAliasConstructorContext,
        original: FunctionSignature,
        sema: SemaModule
    ) -> FunctionSignature? {
        guard case let .classType(owner) = sema.types.kind(of: alias.expandedType),
              owner.args.count == original.classTypeParameterCount
        else { return nil }
        let originalVariables = sema.types.makeTypeVarBySymbol(original.typeParameterSymbols)
        var ownerSubstitution: [TypeVarID: TypeID] = [:]
        for (symbol, argument) in zip(original.typeParameterSymbols, owner.args) {
            let type: TypeID
            switch argument {
            case let .invariant(value), let .out(value), let .in(value): type = value
            case .star: return nil
            }
            if let variable = originalVariables[symbol] { ownerSubstitution[variable] = type }
        }
        func specialize(_ type: TypeID) -> TypeID {
            sema.types.substituteTypeParameters(
                in: type, substitution: ownerSubstitution, typeVarBySymbol: originalVariables
            )
        }
        let classCount = original.classTypeParameterCount
        let ownParameters = Array(original.typeParameterSymbols.dropFirst(classCount))
        var bounds = Array(repeating: [TypeID](), count: alias.typeParameterSymbols.count)
        for (index, argument) in owner.args.enumerated() {
            let type: TypeID
            switch argument {
            case let .invariant(value), let .out(value), let .in(value): type = value
            case .star: return nil
            }
            guard case let .typeParam(parameter) = sema.types.kind(of: type),
                  let aliasIndex = alias.typeParameterSymbols.firstIndex(of: parameter.symbol)
            else { continue }
            let symbol = original.typeParameterSymbols[index]
            let declaredBounds = (original.typeParameterUpperBoundsList.indices.contains(index)
                ? original.typeParameterUpperBoundsList[index] : [])
                + sema.symbols.typeParameterUpperBounds(for: symbol)
            for bound in declaredBounds.map(specialize) where !bounds[aliasIndex].contains(bound) {
                bounds[aliasIndex].append(bound)
            }
        }
        for index in classCount ..< original.typeParameterSymbols.count {
            bounds.append(original.typeParameterUpperBoundsList.indices.contains(index)
                ? original.typeParameterUpperBoundsList[index].map(specialize) : [])
        }
        return FunctionSignature(
            receiverType: original.receiverType.map(specialize),
            contextReceiverTypes: original.contextReceiverTypes.map(specialize),
            parameterTypes: original.parameterTypes.map(specialize),
            returnType: alias.resultType ?? alias.expandedType,
            isSuspend: original.isSuspend,
            canThrow: original.canThrow,
            valueParameterSymbols: original.valueParameterSymbols,
            valueParameterHasDefaultValues: original.valueParameterHasDefaultValues,
            valueParameterIsVararg: original.valueParameterIsVararg,
            valueParameterAllowsNonLocalReturn: original.valueParameterAllowsNonLocalReturn,
            hasExplicitInlineParameterMetadata: original.hasExplicitInlineParameterMetadata,
            typeParameterSymbols: alias.typeParameterSymbols + ownParameters,
            reifiedTypeParameterIndices: Set(original.reifiedTypeParameterIndices.compactMap { index in
                index >= classCount ? alias.typeParameterSymbols.count + index - classCount : nil
            }),
            typeParameterUpperBoundsList: bounds,
            classTypeParameterCount: alias.typeParameterSymbols.count
        )
    }

    /// Convert alias inference back to the original constructor's positional
    /// variables, including nullable and nested arguments such as Box<T>.
    func typeAliasConstructorBindingArguments(
        _ alias: TypeAliasConstructorContext,
        original: FunctionSignature,
        specialized: FunctionSignature,
        substitution: [TypeVarID: TypeID],
        types: TypeSystem
    ) -> [TypeVarID: TypeID] {
        let variables = types.makeTypeVarBySymbol(specialized.typeParameterSymbols)
        let originalVariables = types.makeTypeVarBySymbol(original.typeParameterSymbols)
        var result: [TypeVarID: TypeID] = [:]
        if case let .classType(owner) = types.kind(of: alias.expandedType) {
            for (symbol, argument) in zip(original.typeParameterSymbols, owner.args) {
                let type: TypeID
                switch argument {
                case let .invariant(value), let .out(value), let .in(value): type = value
                case .star: continue
                }
                if let variable = originalVariables[symbol] {
                    result[variable] = types.substituteTypeParameters(
                        in: type, substitution: substitution, typeVarBySymbol: variables
                    )
                }
            }
        }
        for symbol in original.typeParameterSymbols.dropFirst(original.classTypeParameterCount) {
            if let variable = variables[symbol], let originalVariable = originalVariables[symbol],
               let type = substitution[variable] {
                result[originalVariable] = type
            }
        }
        return result
    }
}
