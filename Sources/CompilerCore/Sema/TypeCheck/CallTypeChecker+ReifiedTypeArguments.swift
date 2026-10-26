extension CallTypeChecker {
    func validateReifiedIntersectionTypeArguments(
        for callee: SymbolID,
        resolved: ResolvedCall,
        range: SourceRange,
        sema: SemaModule
    ) -> Bool {
        guard let signature = sema.symbols.functionSignature(for: callee) else { return true }
        let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
        var reifiedIndices = signature.reifiedTypeParameterIndices
        // The native arrayOf intrinsic omits the JVM inline/reified modifier
        // because it lowers directly to kk_array_of, but its Kotlin API still
        // has the reified element-type inference restriction.
        if sema.symbols.symbol(callee)?.fqName == ["kotlin", "arrayOf"].map(driver.interner.intern) {
            reifiedIndices.insert(0)
        }
        var hasInvalidArgument = false

        for index in reifiedIndices.sorted() {
            guard signature.typeParameterSymbols.indices.contains(index) else { continue }
            let typeParameter = signature.typeParameterSymbols[index]
            guard let typeVariable = typeVarBySymbol[typeParameter],
                  let typeArgument = resolved.substitutedTypeArguments[typeVariable],
                  case let .intersection(parts) = sema.types.kind(of: typeArgument)
            else {
                continue
            }

            let parameterName = sema.symbols.symbol(typeParameter).map { driver.interner.resolve($0.name) } ?? "T"
            let renderedParts = parts.map { part in
                "'\(sema.types.displayName(of: part, symbols: sema.symbols, interner: driver.interner))'"
            }.joined(separator: " & ")
            sema.diagnostics.error(
                "KSWIFTK-SEMA-REIFIED",
                "Type argument for reified type parameter '\(parameterName)' was inferred to the intersection of [\(renderedParts)].",
                range: range
            )
            hasInvalidArgument = true
        }

        return !hasInvalidArgument
    }
}
