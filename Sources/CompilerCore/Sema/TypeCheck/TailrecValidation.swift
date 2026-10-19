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
        guard let expr = ast.arena.expr(exprID) else { return false }
        func recurse(_ id: ExprID, _ valuePosition: Bool) -> Bool {
            containsTailCall(
                id, isValuePosition: valuePosition, functionSymbol: functionSymbol, ast: ast, bindings: bindings
            )
        }
        switch expr {
        case let .returnExpr(value, _, _):
            return value.map { recurse($0, true) } ?? false
        case .call, .memberCall, .safeMemberCall:
            return isValuePosition && bindings.callBinding(for: exprID)?.chosenCallee == functionSymbol
        case let .ifExpr(_, thenExpr, elseExpr, _):
            return recurse(thenExpr, isValuePosition) || (elseExpr.map { recurse($0, isValuePosition) } ?? false)
        case let .whenExpr(_, branches, elseExpr, _):
            return branches.contains { recurse($0.body, isValuePosition) }
                || (elseExpr.map { recurse($0, isValuePosition) } ?? false)
        case let .blockExpr(statements, trailingExpr, _):
            return statements.contains { recurse($0, false) }
                || (trailingExpr.map { recurse($0, isValuePosition) } ?? false)
        case let .binary(op, _, rhs, _):
            return op == .elvis && recurse(rhs, isValuePosition)
        default:
            return false
        }
    }
}
