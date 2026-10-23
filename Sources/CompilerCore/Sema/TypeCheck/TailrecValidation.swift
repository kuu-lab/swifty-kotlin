extension TypeCheckSemaPhase {
    func validateTailrecFunctions(ast: ASTModule, sema: SemaModule, diagnostics: DiagnosticEngine) {
        // Callee identity is available only after overload resolution. Extension
        // receivers can change between iterations without changing the callee.
        for file in ast.sortedFiles {
            for declID in file.topLevelDecls {
                guard case let .funDecl(function) = ast.arena.decl(declID),
                      function.isTailrec,
                      let functionSymbol = sema.bindings.declSymbol(for: declID)
                else { continue }
                if !checkTailRecursiveBody(
                    function.body, functionSymbol: functionSymbol, ast: ast, bindings: sema.bindings
                ) {
                    diagnostics.warning(
                        "KSWIFTK-SEMA-TAILREC",
                        "Function marked 'tailrec' but last expression is not a self-recursive call.",
                        range: function.range
                    )
                }
            }
        }
        for (index, expression) in ast.arena.exprs.enumerated() {
            guard case let .localFunDecl(_, _, _, _, body, _, range, _, isTailrec) = expression,
                  isTailrec,
                  let functionSymbol = sema.bindings.identifierSymbol(for: ExprID(rawValue: Int32(index)))
            else { continue }
            if !checkTailRecursiveBody(
                body, functionSymbol: functionSymbol, ast: ast, bindings: sema.bindings
            ) {
                diagnostics.warning(
                    "KSWIFTK-SEMA-TAILREC",
                    "Function marked 'tailrec' but last expression is not a self-recursive call.",
                    range: range
                )
            }
        }
    }

    private func checkTailRecursiveBody(
        _ body: FunctionBody, functionSymbol: SymbolID, ast: ASTModule, bindings: BindingTable
    ) -> Bool {
        switch body {
        case .unit:
            return false
        case let .expr(exprID, _):
            return containsTailCall(
                exprID, isValuePosition: true, functionSymbol: functionSymbol, ast: ast, bindings: bindings
            )
        case let .block(exprIDs, _):
            for (index, exprID) in exprIDs.enumerated() {
                // The last statement doubles as the implicit result; earlier
                // statements only count through an explicit `return`.
                let isLast = index == exprIDs.count - 1
                if containsTailCall(
                    exprID, isValuePosition: isLast, functionSymbol: functionSymbol, ast: ast, bindings: bindings
                ) {
                    return true
                }
            }
            return false
        }
    }

    /// `isValuePosition` is true when the expression's value is the function's
    /// result; otherwise only an explicit `return f(..)` inside it counts.
    private func containsTailCall(
        _ exprID: ExprID, isValuePosition: Bool, functionSymbol: SymbolID, ast: ASTModule, bindings: BindingTable
    ) -> Bool {
        var found = false
        TailrecPositionWalker.visit(
            exprID, in: ast.arena, isValuePosition: isValuePosition, includeLabeledReturns: true
        ) { candidate in
            if bindings.callBinding(for: candidate)?.chosenCallee == functionSymbol { found = true }
        }
        return found
    }
}
