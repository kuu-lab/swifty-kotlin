extension TypeCheckDriver {
    /// Infer a source function in its declaration's scope before overload
    /// resolution consumes its return type. In particular, a later extension
    /// such as `fun Parser<Char>.string() = map { it.toString() }` must not
    /// contribute the header's `Any` placeholder to an enclosing vararg call.
    func inferFunctionReturnTypesIfNeeded(for candidates: [SymbolID]) {
        for symbol in candidates {
            guard let declaration = inferredReturnFunctions[symbol],
                  !checkedInferredReturnFunctions.contains(symbol),
                  !checkingInferredReturnFunctions.contains(symbol)
            else { continue }
            // Use the declaration's file scope and receiver/parameter bindings,
            // never the caller's lambda locals or expected return type.
            let checkpoint = diagnostics.checkpoint()
            let signature = sema.symbols.functionSignature(for: symbol)
            declChecker.typeCheckFunctionDecl(
                declaration.function,
                symbol: symbol,
                ctx: declaration.context,
                solver: solver,
                diagnostics: diagnostics
            )
            let errors = diagnostics.diagnostics.dropFirst(checkpoint).filter { $0.severity == .error }
            if !errors.isEmpty,
               !errors.contains(where: { $0.message.hasPrefix("Recursive ") })
            {
                // An untyped member dependency may become concrete during its
                // owner's normal pass. Retry this declaration authoritatively;
                // do not turn a speculative placeholder failure into a new error.
                diagnostics.rollback(to: checkpoint)
                if let signature { sema.symbols.setFunctionSignature(signature, for: symbol) }
                checkedInferredReturnFunctions.remove(symbol)
                deferredInferredReturnFunctions.insert(symbol)
            }
        }
    }

    func diagnoseRecursiveInferredReturnType(for symbol: SymbolID) {
        guard checkingInferredReturnFunctions.contains(symbol),
              let declaration = inferredReturnFunctions[symbol],
              !diagnostics.diagnostics.contains(where: {
                  $0.code == "KSWIFTK-SEMA-INFER" && $0.primaryRange == declaration.function.range
              })
        else { return }
        diagnostics.error(
            "KSWIFTK-SEMA-INFER",
            "Recursive return type inference requires an explicit return type.",
            range: declaration.function.range
        )
    }
}
