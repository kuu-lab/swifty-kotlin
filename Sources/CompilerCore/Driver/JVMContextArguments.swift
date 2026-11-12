extension JVMFunctionBuilder {
    func contextArgument(_ type: TypeID, symbol: SymbolID?, at id: ExprID) throws -> JVMValue {
        if let symbol {
            if let receiver = contextualReceivers[symbol] { return receiver }
            for scope in scopes.reversed() {
                if let local = scope.values.first(where: { $0.symbol == symbol }) {
                    return try readLocal(local)
                }
            }
        }
        let types = program.sema.types
        let requested = program.specialized(type)
        if let receiver = contextArguments.last(where: { types.isSubtype($0.type, requested) }) {
            return receiver.value
        }
        throw fail("Missing JVM context argument.", id)
    }

    func importedContextArguments(_ binding: CallBinding?, method: JVMForeignMethod, id: ExprID) throws -> [JVMValue] {
        guard let function = method.kotlinFunction, !function.contextParameters.isEmpty else { return [] }
        guard let binding, let signature = program.sema.symbols.functionSignature(for: binding.chosenCallee),
              signature.contextParameterTypes.count == function.contextParameters.count,
              binding.contextParameterArgumentMapping.isEmpty else {
            throw fail("Imported JVM context functions require implicit context arguments.", id)
        }
        let types = program.sema.types
        let typeVariables = types.makeTypeVarBySymbol(signature.typeParameterSymbols)
        let substitution = Dictionary(uniqueKeysWithValues: zip(signature.typeParameterSymbols, binding.substitutedTypeArguments)
            .compactMap { symbol, type in typeVariables[symbol].map { ($0, type) } })
        return try signature.contextParameterTypes.enumerated().map { index, type in
            let substituted = types.substituteTypeParameters(in: type, substitution: substitution, typeVarBySymbol: typeVariables)
            let symbol = binding.contextParameterReceiverSymbols.indices.contains(index) ? binding.contextParameterReceiverSymbols[index] : nil
            return try convert(contextArgument(substituted, symbol: symbol, at: id), to: method.parameters[index])
        }
    }
}
