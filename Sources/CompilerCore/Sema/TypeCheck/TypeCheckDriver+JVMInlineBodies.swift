extension TypeCheckDriver {
    func checkDemandedJVMInlineBodies(
        _ pending: inout [SymbolID: (declaration: DeclID, function: FunDecl, context: TypeInferenceContext)]
    ) {
        // Work from resolved uses, including callable references. Checking one
        // body can resolve further inline calls. Remove each body before checking
        // it so cycles cannot schedule the same function twice.
        while !pending.isEmpty {
            let bindings = sema.bindings
            var demanded: Set<SymbolID> = []
            for binding in bindings.callBindings.values where pending[binding.chosenCallee] != nil {
                demanded.insert(binding.chosenCallee)
            }
            for binding in bindings.callableReferenceBindings.values where pending[binding.chosenCallee] != nil {
                demanded.insert(binding.chosenCallee)
            }
            for symbol in bindings.identifierSymbols.values where pending[symbol] != nil {
                demanded.insert(symbol)
            }
            guard !demanded.isEmpty else { return }
            for symbol in demanded.sorted(by: { $0.rawValue < $1.rawValue }) {
                guard let body = pending.removeValue(forKey: symbol),
                      let syntax = compilationContext?.deferredJVMInlineBodies.removeValue(forKey: body.declaration)
                else { continue }
                let expressions = BuildASTPhase(diagnostics: diagnostics).blockExpressions(
                    from: syntax.block, in: syntax.arena, interner: interner, astArena: ast.arena
                )
                let function = body.function.replacingBody(.block(expressions, syntax.arena.node(syntax.block).range))
                ast.arena.replaceDecl(body.declaration, with: .funDecl(function))
                declChecker.typeCheckFunctionDecl(
                    function, symbol: symbol, ctx: body.context,
                    solver: solver, diagnostics: diagnostics
                )
            }
        }
    }
}
