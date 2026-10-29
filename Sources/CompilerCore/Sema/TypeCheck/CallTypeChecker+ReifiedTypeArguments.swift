extension CallTypeChecker {
    /// Validates inferred type arguments for `reified` parameters. Returns
    /// false when at least one argument cannot back a reified token: a
    /// captured existential produced by a use-site projection such as
    /// `KClass<*>` has no concrete class to reify, and a multi-bound
    /// intersection cannot be reified either.
    func validateReifiedTypeArguments(
        for callee: SymbolID,
        substitutedTypeArguments: [TypeVarID: TypeID],
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
                  let typeArgument = substitutedTypeArguments[typeVariable]
            else {
                continue
            }

            // A projection such as `KClass<*>` captures the receiver's argument
            // as an existential. kotlinc rejects it as "cannot use
            // 'CapturedType(*)' as reified type parameter."
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

            // A definitely-non-null type parameter is represented as T & Any.
            // It can be forwarded to a reified call without inferring a
            // multi-bound intersection type.
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
                "Type argument for reified type parameter '\(parameterName)' was inferred to the intersection of [\(renderedParts)].",
                range: range
            )
            hasInvalidArgument = true
        }

        return !hasInvalidArgument
    }

    /// Renders a captured existential the way kotlinc prints it in
    /// "cannot use 'CapturedType(...)' as reified type parameter" — e.g.
    /// `CapturedType(*)`, `CapturedType(out Number)`, or `CapturedType(in Int)`.
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
        // `out X` and `*` both capture as a read-only existential with a
        // Nothing lower bound. The star shape is the one whose readable bound
        // is the captured parameter's own declared bound.
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
