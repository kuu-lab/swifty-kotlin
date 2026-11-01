extension TypeCheckDriver {
    func notePendingDeclarationDependency(at expression: ExprID) {
        guard !checkingInferredReturnFunctions.isEmpty || !checkingInferredProperties.isEmpty else { return }
        let property = sema.bindings.identifierSymbol(for: expression)
        let callee = sema.bindings.callBinding(for: expression)?.chosenCallee
        let owner = callee.flatMap { sema.symbols.accessorOwnerProperty(for: $0) }
        if property.map({ pendingPropertyTypes.contains($0) }) == true
            || owner.map({ pendingPropertyTypes.contains($0) }) == true
            || callee.map({ deferredInferredReturnFunctions.contains($0) }) == true
        {
            deferredInferredReturnFunctions.formUnion(checkingInferredReturnFunctions)
            deferredInferredProperties.formUnion(checkingInferredProperties)
        }
    }

    func resolveInferredPropertyType(for symbol: SymbolID) {
        // Resolve initializer dependencies of a function being inferred early.
        // Ordinary property checking retains the existing module pre-pass.
        guard !checkingInferredReturnFunctions.isEmpty,
              let declaration = inferredPropertyDeclarations[symbol],
              !precheckedPropertyDecls.contains(declaration.declaration)
        else { return }
        guard !checkingInferredProperties.contains(symbol) else {
            diagnostics.error(
                "KSWIFTK-TYPE-0001",
                "Recursive property requires an explicit type.",
                range: declaration.property.range
            )
            return
        }
        declChecker.typeCheckBoundPropertyDecl(
            declaration.property,
            declID: declaration.declaration,
            symbol: symbol,
            ctx: declaration.context,
            initialLocals: declaration.initialLocals,
            solver: solver,
            diagnostics: diagnostics
        )
    }
}
