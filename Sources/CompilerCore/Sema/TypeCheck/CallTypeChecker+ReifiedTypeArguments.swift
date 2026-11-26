extension CallTypeChecker {
    func validateReifiedTypeArguments(
        for callee: SymbolID,
        substitutedTypeArguments: [TypeVarID: TypeID],
        range: SourceRange,
        sema: SemaModule
    ) -> Bool {
        guard let signature = sema.symbols.functionSignature(for: callee) else { return true }
        let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
        var reifiedIndices = signature.reifiedTypeParameterIndices
        if sema.symbols.symbol(callee)?.fqName == ["kotlin", "arrayOf"].map(driver.interner.intern) {
            reifiedIndices.insert(0)
        }
        var hasInvalidArgument = false

        for index in reifiedIndices.sorted() {
            guard signature.typeParameterSymbols.indices.contains(index) else { continue }
            let typeParameter = signature.typeParameterSymbols[index]
            guard let typeVariable = typeVarBySymbol[typeParameter],
                  let typeArgument = substitutedTypeArguments[typeVariable]
            else {
                continue
            }

            if sema.types.containsCapturedTypes(typeArgument) {
                sema.diagnostics.error(
                    "KSWIFTK-SEMA-REIFIED",
                    "Cannot use '\(reifiedCapturedArgumentName(of: typeArgument, sema: sema))' as reified type parameter.",
                    range: range
                )
                hasInvalidArgument = true
                continue
            }

            guard case let .intersection(parts) = sema.types.kind(of: typeArgument) else {
                continue
            }

            let nonAnyParts = parts.filter { $0 != sema.types.anyType }
            if parts.count == 2, nonAnyParts.count == 1,
               case let .typeParam(parameter) = sema.types.kind(of: nonAnyParts[0]),
               parameter.capture == nil
            {
                continue
            }

            let parameterName = sema.symbols.symbol(typeParameter).map { driver.interner.resolve($0.name) } ?? "T"
            let renderedParts = parts.map { part in
                "'\(sema.types.displayName(of: part, symbols: sema.symbols, interner: driver.interner))'"
            }.joined(separator: " & ")
            sema.diagnostics.error(
                "KSWIFTK-SEMA-REIFIED",
                "Type argument for reified type parameter '\(parameterName)' was inferred to the intersection of [\(renderedParts)]. Reification of an intersection type results in the common supertype being used. This may lead to subtle issues and an explicit type argument is encouraged.",
                range: range
            )
            hasInvalidArgument = true
        }

        return !hasInvalidArgument
    }

    private func reifiedCapturedArgumentName(of type: TypeID, sema: SemaModule) -> String {
        func render(_ part: TypeID) -> String {
            sema.types.displayName(of: part, symbols: sema.symbols, interner: driver.interner)
        }
        guard case let .typeParam(parameter) = sema.types.kind(of: type),
              let capture = parameter.capture
        else {
            return render(type)
        }
        if capture.lower != sema.types.nothingType {
            return "CapturedType(in \(render(capture.lower)))"
        }
        let declaredBounds = sema.types.declaredUpperBounds(for: parameter.symbol)
        let declaredBound = declaredBounds.isEmpty
            ? sema.types.nullableAnyType
            : declaredBounds.count == 1 ? declaredBounds[0] : sema.types.make(.intersection(declaredBounds))
        if capture.upper == declaredBound || capture.upper == sema.types.anyType {
            return "CapturedType(*)"
        }
        return "CapturedType(out \(render(capture.upper)))"
    }
}
