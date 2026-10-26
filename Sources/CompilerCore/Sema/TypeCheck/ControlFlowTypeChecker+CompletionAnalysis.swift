extension ControlFlowTypeChecker {
    /// A try expression keeps its try/catch LUB even when finally prevents completion.
    func canCompleteNormally(_ id: ExprID, ctx: TypeInferenceContext) -> Bool {
        canCompleteNormally(id, inlinedLambda: nil, ctx: ctx)
    }

    private func canCompleteNormally(
        _ id: ExprID,
        inlinedLambda: ExprID?,
        ctx: TypeInferenceContext
    ) -> Bool {
        guard let expr = ctx.ast.arena.expr(id) else { return true }
        if let inlinedLambda, case .returnExpr = expr {
            if ctx.sema.bindings.functionReturnLambdaPaths[id]?.contains(inlinedLambda) == true {
                return false
            }
            if ctx.sema.bindings.lambdaReturnTargets[id] != nil {
                return true
            }
        }
        // A Nothing-typed structured expression in an inline argument may still
        // reach its caller through a local return. Inspect its branches so the
        // bound return target, rather than the aggregate type, decides completion.
        let isStructuredInlineLambdaBody: Bool = {
            guard inlinedLambda != nil else { return false }
            switch expr {
            case .blockExpr, .ifExpr, .whenExpr, .tryExpr:
                return true
            default:
                return false
            }
        }()
        if ctx.sema.bindings.exprType(for: id) == ctx.sema.types.nothingType,
           !isStructuredInlineLambdaBody
        {
            return false
        }
        func completes(_ child: ExprID) -> Bool {
            canCompleteNormally(child, inlinedLambda: inlinedLambda, ctx: ctx)
        }
        switch expr {
        case let .tryExpr(body, catchClauses, finallyExpr, _):
            if let finallyExpr, !completes(finallyExpr) { return false }
            return completes(body) || catchClauses.contains { completes($0.body) }
        case let .blockExpr(statements, trailingExpr, _):
            for statement in statements {
                if let inlinedLambda,
                   let statementExpr = ctx.ast.arena.expr(statement),
                   case .returnExpr = statementExpr,
                   ctx.sema.bindings.lambdaReturnTargets[statement] == inlinedLambda
                {
                    // A local return exits this lambda body and completes its
                    // invocation. Later statements are already unreachable and
                    // must not make the surrounding inline call look terminal.
                    return true
                }
                if !completes(statement) { return false }
            }
            return trailingExpr.map(completes) ?? true
        case let .ifExpr(condition, thenExpr, elseExpr, _):
            return completes(condition) && (completes(thenExpr) || (elseExpr.map(completes) ?? true))
        case let .whenExpr(subject, branches, elseExpr, _):
            if let subject, !completes(subject) { return false }
            guard ctx.sema.bindings.whenExhaustiveness[id] == true else { return true }
            return branches.contains { completes($0.body) } || (elseExpr.map(completes) ?? false)
        case let .localDecl(_, _, _, initializer, _, _, _):
            return initializer.map(completes) ?? true
        case let .localAssign(_, value, _), let .compoundAssign(_, _, value, _),
             let .destructuringDecl(_, _, value, _):
            return completes(value)
        case let .memberAssign(receiver, _, value, _),
             let .memberCompoundAssign(_, receiver, _, value, _):
            return completes(receiver) && completes(value)
        case let .safeMemberAssign(receiver, _, _, _):
            // `a?.b = v` skips `v` entirely when `a` is null — the `?.`
            // short-circuits the rest of the postfix chain — so only the
            // receiver has to complete, matching `safeMemberCall` arguments.
            return completes(receiver)
        case let .indexedAssign(receiver, indices, value, _),
             let .indexedCompoundAssign(_, receiver, indices, value, _):
            if receiverChainIsGuardedBySafeCall(receiver, ctx: ctx) {
                return completes(receiver)
            }
            return completes(receiver) && indices.allSatisfy(completes) && completes(value)
        case let .call(callee, _, args, _):
            return completes(callee)
                && args.allSatisfy { completes($0.expr) }
                && !hasGuaranteedNonCompletingInlineLambda(id, arguments: args, ctx: ctx)
        case let .memberCall(receiver, _, _, args, _):
            return completes(receiver)
                && args.allSatisfy { completes($0.expr) }
                && !hasGuaranteedNonCompletingInlineLambda(id, arguments: args, ctx: ctx)
        case let .safeMemberCall(receiver, _, _, _, _):
            return completes(receiver)
        case let .indexedAccess(receiver, indices, _):
            if receiverChainIsGuardedBySafeCall(receiver, ctx: ctx) {
                return completes(receiver)
            }
            return completes(receiver) && indices.allSatisfy(completes)
        case let .binary(op, lhs, rhs, _):
            switch op {
            case .logicalAnd, .logicalOr, .elvis:
                return completes(lhs)
            default:
                return completes(lhs) && completes(rhs)
            }
        case let .unaryExpr(_, operand, _), let .isCheck(operand, _, _, _),
             let .asCast(operand, _, _, _), let .nullAssert(operand, _):
            return completes(operand)
        case let .inExpr(lhs, rhs, _), let .notInExpr(lhs, rhs, _):
            return completes(lhs) && completes(rhs)
        default:
            return true
        }
    }

    /// Whether `id`'s postfix chain reaches a `?.` that can skip evaluating the
    /// suffixes applied after it. `a?.b[i] = v` never evaluates `i` or `v` when
    /// `a` is null. A `!!`, `as` cast, or plain `.member`/`()` on the nullable
    /// result is not part of the safe navigation and breaks the guard, so the
    /// walk only follows indexed suffixes.
    private func receiverChainIsGuardedBySafeCall(_ id: ExprID, ctx: TypeInferenceContext) -> Bool {
        var current = id
        while let expr = ctx.ast.arena.expr(current) {
            switch expr {
            case .safeMemberCall, .safeMemberAssign:
                return true
            case let .indexedAccess(receiver, _, _),
                 let .indexedAssign(receiver, _, _, _),
                 let .indexedCompoundAssign(_, receiver, _, _, _):
                current = receiver
            default:
                return false
            }
        }
        return false
    }

    private func hasGuaranteedNonCompletingInlineLambda(
        _ call: ExprID,
        arguments: [CallArgument],
        ctx: TypeInferenceContext
    ) -> Bool {
        guard let binding = ctx.sema.bindings.callBindings[call],
              let callee = ctx.sema.symbols.symbol(binding.chosenCallee),
              callee.flags.contains(.inlineFunction),
              let signature = ctx.sema.symbols.functionSignature(for: binding.chosenCallee)
        else {
            return false
        }

        let invocationEffects = ctx.sema.symbols.contractCallsInPlaceEffects(for: binding.chosenCallee)
        for (argumentIndex, argument) in arguments.enumerated() {
            let parameterIndex = binding.parameterMapping[argumentIndex] ?? argumentIndex
            guard signature.valueParameterSymbols.indices.contains(parameterIndex),
                  !signature.valueParameterAllowsNonLocalReturn.indices.contains(parameterIndex)
                    || signature.valueParameterAllowsNonLocalReturn[parameterIndex],
                  invocationEffects.contains(where: { effect in
                      effect.parameterSymbol == signature.valueParameterSymbols[parameterIndex]
                          && (effect.kind == .exactlyOnce || effect.kind == .atLeastOnce)
                  }),
                  case let .lambdaLiteral(_, body, _, _) = ctx.ast.arena.expr(argument.expr)
            else {
                continue
            }
            if !canCompleteNormally(body, inlinedLambda: argument.expr, ctx: ctx) {
                return true
            }
        }
        return false
    }
}
