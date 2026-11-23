extension TypeCheckDriver {
    /// Returns the called `@Composable` symbol(s) or callable-parameter symbol if `id`
    /// invokes a composable declaration or composable function-typed parameter.
    func composableCallTargets(for id: ExprID) -> [SymbolID] {
        guard !sema.composableFunctions.isEmpty || !sema.composableFunctionParameters.isEmpty else {
            return []
        }
        var result: [SymbolID] = []
        if let call = sema.bindings.callBinding(for: id),
           sema.composableFunctions.contains(call.chosenCallee)
        {
            result.append(call.chosenCallee)
        }
        if let callableBinding = sema.bindings.callableValueCallBinding(for: id) {
            if let paramSym = sema.bindings.identifierSymbol(for: callableBinding.implicitInvokeReceiverExpr ?? id),
               sema.composableFunctionParameters.contains(paramSym)
            {
                result.append(paramSym)
            } else if let expr = ast.arena.expr(id),
                      case let .call(calleeExpr, _, _, _) = expr,
                      let paramSym = sema.bindings.identifierSymbol(for: calleeExpr),
                      sema.composableFunctionParameters.contains(paramSym)
            {
                result.append(paramSym)
            }
        }
        if let identSym = sema.bindings.identifierSymbol(for: id),
           sema.symbols.symbol(identSym)?.kind != .object,
           sema.composableFunctions.contains(identSym)
        {
            result.append(identSym)
        }
        if let memberSym = sema.bindings.callBinding(for: id)?.chosenCallee {
            // Covered above, keep distinct.
            _ = memberSym
        }
        return result
    }

    /// Validates that every `@Composable` invocation recorded during type checking
    /// occurs inside a `@Composable` function, getter, composable lambda, or an
    /// inline non-crossinline/non-disallowed lambda enclosed in a `@Composable` scope.
    func validateComposableContexts(
        inlineLambdaArguments: Set<ExprID>,
        inlineAnonymousFunctionArguments: Set<ExprID>
    ) {
        guard sema.composePluginEnabled,
              !callComposableContexts.isEmpty
        else { return }

        let (composableLambdaArguments, disallowedLambdaArguments) = collectComposableLambdaArguments()
        sema.composableLambdaExprs.formUnion(composableLambdaArguments)

        func isSuppressedInFunction(_ functionSymbol: SymbolID?) -> Bool {
            guard let functionSymbol else { return false }
            for ann in sema.symbols.annotations(for: functionSymbol) {
                let shortName = ann.annotationFQName.split(separator: ".").last.map(String.init) ?? ann.annotationFQName
                if shortName == "Suppress" && ann.arguments.contains(where: {
                    $0 == "COMPOSABLE_INVOCATION" || $0 == "\"COMPOSABLE_INVOCATION\""
                }) {
                    return true
                }
            }
            return false
        }

        func allowsComposition(in context: SuspensionContext) -> (allowed: Bool, isReadOnly: Bool) {
            var allowed = false
            var isReadOnly = false
            if let enclosingFunction = context.function {
                if sema.composableFunctions.contains(enclosingFunction) {
                    allowed = true
                    isReadOnly = sema.readonlyComposableFunctions.contains(enclosingFunction)
                } else if isSuppressedInFunction(enclosingFunction) {
                    allowed = true
                }
            }
            for lambda in context.lambdas {
                if disallowedLambdaArguments.contains(lambda) {
                    allowed = false
                    isReadOnly = false
                } else if composableLambdaArguments.contains(lambda) {
                    allowed = true
                } else if !inlineLambdaArguments.contains(lambda) && !inlineAnonymousFunctionArguments.contains(lambda) {
                    allowed = false
                    isReadOnly = false
                }
            }
            return (allowed, isReadOnly)
        }

        for id in callComposableContexts.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard let context = callComposableContexts[id] else { continue }
            let targets = composableCallTargets(for: id)
            guard !targets.isEmpty else { continue }

            let status = allowsComposition(in: context)
            if !status.allowed {
                for target in targets {
                    let targetName = sema.symbols.symbol(target).map { interner.resolve($0.name) } ?? "composable"
                    diagnostics.error(
                        "KSWIFTK-SEMA-0493",
                        "@Composable invocations (such as '\(targetName)') can only happen from the context of a @Composable function.",
                        range: ast.arena.exprRange(id)
                    )
                }
            } else if status.isReadOnly {
                for target in targets where sema.composableFunctions.contains(target) && !sema.readonlyComposableFunctions.contains(target) {
                    let targetName = sema.symbols.symbol(target).map { interner.resolve($0.name) } ?? "composable"
                    diagnostics.error(
                        "KSWIFTK-SEMA-0494",
                        "Calls to '@Composable' function '\(targetName)' that are not '@ReadOnlyComposable' are not allowed inside a '@ReadOnlyComposable' function.",
                        range: ast.arena.exprRange(id)
                    )
                }
            }
        }
    }

    private func collectComposableLambdaArguments() -> (
        composableLambdas: Set<ExprID>,
        disallowedLambdas: Set<ExprID>
    ) {
        var composableLambdas: Set<ExprID> = []
        var disallowedLambdas: Set<ExprID> = []
        let hasComposableDef = sema.symbols.lookup(
            fqName: ["androidx", "compose", "runtime", "Composable"].map { interner.intern($0) }
        ) != nil

        for context in callComposableContexts.values {
            for lambdaID in context.lambdas {
                if ast.arena.expressionAnnotations(for: lambdaID).contains(where: {
                    ComposePlugin.isComposableAnnotation($0.name, allowShort: hasComposableDef)
                }) {
                    composableLambdas.insert(lambdaID)
                }
            }
        }

        for (callExprID, binding) in sema.bindings.callBindings {
            guard let signature = sema.symbols.functionSignature(for: binding.chosenCallee) else { continue }
            let argExprs: [ExprID]
            switch ast.arena.expr(callExprID) {
            case let .call(_, _, args, _), let .memberCall(_, _, _, args, _),
                 let .safeMemberCall(_, _, _, args, _):
                argExprs = args.map(\.expr)
            default:
                continue
            }

            for (index, argExpr) in argExprs.enumerated() {
                let paramIdx = binding.parameterMapping[index] ?? index
                guard signature.valueParameterSymbols.indices.contains(paramIdx) else { continue }
                let paramSym = signature.valueParameterSymbols[paramIdx]

                var candidateExpr = argExpr
                if ast.arena.isAnonymousFunction(argExpr),
                   case let .blockExpr(stmts, _, _) = ast.arena.expr(argExpr),
                   let anon = stmts.first(where: ast.arena.isAnonymousFunction)
                {
                    candidateExpr = anon
                }

                if sema.disallowComposableCallsParameters.contains(paramSym) {
                    disallowedLambdas.insert(candidateExpr)
                } else if sema.composableFunctionParameters.contains(paramSym) {
                    composableLambdas.insert(candidateExpr)
                }
            }
        }
        return (composableLambdas, disallowedLambdas)
    }
}
