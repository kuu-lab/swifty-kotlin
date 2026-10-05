extension ControlFlowTypeChecker {
    /// A try expression keeps its try/catch LUB even when finally prevents completion.
    func canCompleteNormally(_ id: ExprID, ctx: TypeInferenceContext) -> Bool {
        if ctx.sema.bindings.exprType(for: id) == ctx.sema.types.nothingType {
            return false
        }
        guard let expr = ctx.ast.arena.expr(id) else { return true }
        func completes(_ child: ExprID) -> Bool {
            canCompleteNormally(child, ctx: ctx)
        }
        switch expr {
        case let .tryExpr(body, catchClauses, finallyExpr, _):
            if let finallyExpr, !completes(finallyExpr) { return false }
            return completes(body) || catchClauses.contains { completes($0.body) }
        case let .blockExpr(statements, trailingExpr, _):
            return statements.allSatisfy(completes) && (trailingExpr.map(completes) ?? true)
        case let .ifExpr(condition, thenExpr, elseExpr, _):
            return completes(condition) && (completes(thenExpr) || (elseExpr.map(completes) ?? true))
        case let .whenExpr(subject, branches, elseExpr, _):
            if let subject, !completes(subject) { return false }
            guard ctx.sema.bindings.whenExhaustiveness[id] == true else { return true }
            return branches.contains { completes($0.body) } || (elseExpr.map(completes) ?? false)
        case let .localDecl(_, _, _, initializer, _, _):
            return initializer.map(completes) ?? true
        case let .localAssign(_, value, _), let .compoundAssign(_, _, value, _),
             let .destructuringDecl(_, _, value, _):
            return completes(value)
        case let .memberAssign(receiver, _, value, _), let .memberCompoundAssign(_, receiver, _, value, _):
            return completes(receiver) && completes(value)
        case let .indexedAssign(receiver, indices, value, _),
             let .indexedCompoundAssign(_, receiver, indices, value, _):
            return completes(receiver) && indices.allSatisfy(completes) && completes(value)
        case let .call(callee, _, args, _):
            return completes(callee) && args.allSatisfy { completes($0.expr) }
        case let .memberCall(receiver, _, _, args, _):
            return completes(receiver) && args.allSatisfy { completes($0.expr) }
        case let .safeMemberCall(receiver, _, _, _, _):
            return completes(receiver)
        case let .indexedAccess(receiver, indices, _):
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
}
