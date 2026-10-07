extension ControlFlowTypeChecker {
    /// Resolve unsuffixed integer branch results against Long peers before LUB.
    /// Ordinary Int expressions retain their type; Kotlin has no Int-to-Long widening.
    func contextualizeLongBranchLiterals(
        expressions: [ExprID],
        types: [TypeID],
        ctx: TypeInferenceContext
    ) -> [TypeID] {
        let sema = ctx.sema
        guard types.contains(where: { sema.types.makeNonNullable($0) == sema.types.longType }) else {
            return types
        }
        var literalNodes: [Int: [ExprID]] = [:]
        for (index, pair) in zip(expressions, types).enumerated() {
            let nonNullType = sema.types.makeNonNullable(pair.1)
            if nonNullType == sema.types.longType || nonNullType == sema.types.nothingType {
                continue
            }
            guard pair.1 == sema.types.intType,
                  let nodes = integerBranchLiteralNodes(pair.0, ctx: ctx)
            else { return types }
            literalNodes[index] = nodes
        }
        var contextualized = types
        for (index, nodes) in literalNodes {
            for node in nodes {
                sema.bindings.bindExprType(node, type: sema.types.longType)
            }
            contextualized[index] = sema.types.longType
        }
        return contextualized
    }

    /// Collect only result-producing literals and their expression wrappers.
    /// Earlier block statements and branch conditions are never contextualized.
    private func integerBranchLiteralNodes(_ id: ExprID, ctx: TypeInferenceContext) -> [ExprID]? {
        switch ctx.ast.arena.expr(id) {
        case .intLiteral:
            return [id]
        case let .unaryExpr(op, operand, _) where op == .unaryMinus || op == .unaryPlus:
            guard case .intLiteral = ctx.ast.arena.expr(operand) else { return nil }
            return [operand, id]
        case let .blockExpr(_, trailingExpr?, _):
            guard let nodes = integerBranchLiteralNodes(trailingExpr, ctx: ctx) else { return nil }
            return nodes + [id]
        case let .ifExpr(_, thenExpr, elseExpr?, _):
            guard let thenNodes = integerBranchLiteralNodes(thenExpr, ctx: ctx),
                  let elseNodes = integerBranchLiteralNodes(elseExpr, ctx: ctx)
            else { return nil }
            return thenNodes + elseNodes + [id]
        case let .whenExpr(_, branches, elseExpr, _):
            var nodes: [ExprID] = []
            for body in branches.map(\.body) + (elseExpr.map { [$0] } ?? []) {
                guard let branchNodes = integerBranchLiteralNodes(body, ctx: ctx) else { return nil }
                nodes += branchNodes
            }
            return nodes + [id]
        default:
            return nil
        }
    }
}
