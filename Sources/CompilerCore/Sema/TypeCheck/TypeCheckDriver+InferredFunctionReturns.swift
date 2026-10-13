extension TypeCheckDriver {
    /// Infer a source function in its declaration's scope before overload
    /// resolution consumes its return type. In particular, a later extension
    /// such as `fun Parser<Char>.string() = map { it.toString() }` must not
    /// contribute the header's `Any` placeholder to an enclosing vararg call.
    func inferFunctionReturnTypesIfNeeded(for candidates: [SymbolID]) {
        for symbol in candidates {
            guard let declaration = inferredReturnFunctions[symbol],
                  !checkedInferredReturnFunctions.contains(symbol)
            else { continue }
            guard checkingInferredReturnFunctions.insert(symbol).inserted else {
                // A candidate is not necessarily the selected overload. Diagnose
                // a cycle only after expression inference binds the actual call.
                continue
            }
            declChecker.typeCheckFunctionDecl(
                declaration.function,
                symbol: symbol,
                ctx: declaration.context,
                solver: solver,
                diagnostics: diagnostics
            )
            checkingInferredReturnFunctions.remove(symbol)
            checkedInferredReturnFunctions.insert(symbol)
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
