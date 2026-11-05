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
        // Resolve initializer dependencies of a function being inferred early,
        // or of a declaration read during the authoritative source-order pass.
        // The module pre-pass publishes only initializers it can check without
        // running bodies; a read in the source-order pass may still meet a
        // pending inferred property (for example one initialized by a call that
        // takes a lambda argument), so resolve it on demand here.
        guard !checkingInferredReturnFunctions.isEmpty || isCheckingSourceOrderBodies,
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
