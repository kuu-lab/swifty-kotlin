extension TypeCheckSemaPhase {
    func validateTailrecFunctions(
        ast: ASTModule,
        sema: SemaModule,
        diagnostics: DiagnosticEngine,
        inlineLambdaArguments: Set<ExprID>
    ) {
        // Callee identity is available only after overload resolution. Extension
        // receivers can change between iterations without changing the callee.
        for index in ast.arena.decls.indices {
            guard case let .funDecl(function) = ast.arena.decls[index],
                  function.isTailrec,
                  let functionSymbol = sema.bindings.declSymbol(for: DeclID(rawValue: Int32(index)))
            else { continue }
            reportTailrecDiagnostics(
                body: function.body,
                functionSymbol: functionSymbol,
                declRange: function.range,
                ast: ast,
                bindings: sema.bindings,
                diagnostics: diagnostics,
                inlineLambdaArguments: inlineLambdaArguments
            )
        }
        for (index, expression) in ast.arena.exprs.enumerated() {
            guard case let .localFunDecl(_, _, _, _, body, _, range, _, isTailrec) = expression,
                  isTailrec,
                  let functionSymbol = sema.bindings.identifierSymbol(for: ExprID(rawValue: Int32(index)))
            else { continue }
            reportTailrecDiagnostics(
                body: body,
                functionSymbol: functionSymbol,
                declRange: range,
                ast: ast,
                bindings: sema.bindings,
                diagnostics: diagnostics,
                inlineLambdaArguments: inlineLambdaArguments
            )
        }
    }

    private func reportTailrecDiagnostics(
        body: FunctionBody,
        functionSymbol: SymbolID,
        declRange: SourceRange,
        ast: ASTModule,
        bindings: BindingTable,
        diagnostics: DiagnosticEngine,
        inlineLambdaArguments: Set<ExprID>
    ) {
        var hasTailCall = false
        var nonTailCalls: [(id: ExprID, inTryRegion: Bool)] = []
        collectSelfCalls(
            body,
            functionSymbol: functionSymbol,
            ast: ast,
            bindings: bindings,
            inlineLambdaArguments: inlineLambdaArguments,
            onTailCall: { hasTailCall = true },
            onNonTailCall: { nonTailCalls.append($0) }
        )
        if !hasTailCall {
            diagnostics.warning(
                "KSWIFTK-SEMA-TAILREC",
                "a function is marked as tail-recursive but no tail calls are found.",
                range: declRange
            )
        }
        for call in nonTailCalls {
            diagnostics.warning(
                "KSWIFTK-SEMA-TAILREC",
                call.inTryRegion
                    ? "tail recursion optimization inside try/catch/finally is not supported."
                    : "recursive call is not a tail call.",
                range: callRange(of: call.id, in: ast)
            )
        }
    }

    private func callRange(of id: ExprID, in ast: ASTModule) -> SourceRange? {
        switch ast.arena.expr(id) {
        case let .call(_, _, _, range),
             let .memberCall(_, _, _, _, range),
             let .safeMemberCall(_, _, _, _, range):
            return range
        default:
            return nil
        }
    }

    /// Reports `onTailCall` for each self-recursive call in a tail position and
    /// `onNonTailCall` for each self-recursive call outside one — including
    /// calls inside lambdas and local declarations; the flag distinguishes
    /// try-region calls for the dedicated kotlinc wording.
    private func collectSelfCalls(
        _ body: FunctionBody,
        functionSymbol: SymbolID,
        ast: ASTModule,
        bindings: BindingTable,
        inlineLambdaArguments: Set<ExprID>,
        onTailCall: @escaping () -> Void,
        onNonTailCall: @escaping ((ExprID, Bool)) -> Void
    ) {
        func walk(_ exprID: ExprID, isValuePosition: Bool) {
            TailrecPositionWalker.visit(
                exprID,
                in: ast.arena,
                isValuePosition: isValuePosition,
                includeLabeledReturns: true,
                inlineLambdaArguments: inlineLambdaArguments,
                onCandidate: { candidate in
                    if bindings.callBinding(for: candidate)?.chosenCallee == functionSymbol {
                        onTailCall()
                    }
                },
                onSelfCall: { callID, inTryRegion in
                    if bindings.callBinding(for: callID)?.chosenCallee == functionSymbol {
                        onNonTailCall((callID, inTryRegion))
                    }
                }
            )
        }
        switch body {
        case .unit:
            break
        case let .expr(exprID, _):
            walk(exprID, isValuePosition: true)
        case let .block(exprIDs, _):
            for (index, exprID) in exprIDs.enumerated() {
                // The last statement doubles as the implicit result; earlier
                // statements only count through an explicit `return`.
                walk(exprID, isValuePosition: index == exprIDs.count - 1)
            }
        }
    }

}
