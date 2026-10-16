extension ControlFlowTypeChecker {
    /// Uses a contextual type as the branch join when the computed LUB is too
    /// broad to retain a common declared upper bound of all completing branches.
    func contextualizeBranchJoin(
        _ inferredType: TypeID,
        branchTypes: [TypeID],
        expectedType: TypeID?,
        ctx: TypeInferenceContext
    ) -> TypeID {
        let types = ctx.sema.types
        guard let expectedType,
              inferredType != types.errorType,
              expectedType != types.errorType,
              !branchTypes.contains(types.errorType),
              !types.isSubtype(inferredType, expectedType),
              branchTypes.allSatisfy({ types.isSubtype($0, expectedType) })
        else {
            return inferredType
        }
        return expectedType
    }

    /// Adapts callable references to the function type selected for a `when`
    /// join. This is needed when the common return type is wider than a branch's
    /// declared return type, because the branch value must use the joined ABI.
    func adaptCallableReferenceBranches(
        expressions: [ExprID],
        branchTypes: [TypeID],
        resultType: TypeID,
        ctx: TypeInferenceContext
    ) {
        let sema = ctx.sema
        guard case .functionType = sema.types.kind(of: resultType),
              expressions.count == branchTypes.count
        else {
            return
        }

        for (expression, branchType) in zip(expressions, branchTypes) {
            guard branchType != resultType,
                  case .functionType = sema.types.kind(of: branchType),
                  sema.types.isSubtype(branchType, resultType),
                  let reference = terminalCallableReference(in: expression, ctx: ctx),
                  sema.bindings.callableRefKind(for: reference) == .functionRef
            else {
                continue
            }

            let binding = sema.bindings.callableReferenceBinding(for: reference)
            guard let chosenCallee = binding?.chosenCallee
                    ?? sema.bindings.identifierSymbol(for: reference)
            else {
                continue
            }
            sema.bindings.bindCallableReference(reference, binding: CallBinding(
                chosenCallee: chosenCallee,
                substitutedTypeArguments: binding?.substitutedTypeArguments ?? [],
                parameterMapping: binding?.parameterMapping ?? [:],
                defaultArgumentOwner: binding?.defaultArgumentOwner,
                dispatchReceiverSymbol: binding?.dispatchReceiverSymbol,
                isCallableReferenceAdapter: true
            ))
            sema.bindings.bindExprType(reference, type: resultType)
            for wrapper in callableReferenceWrappers(in: expression, ctx: ctx) {
                sema.bindings.bindExprType(wrapper, type: resultType)
            }
        }
    }

    private func terminalCallableReference(in expression: ExprID, ctx: TypeInferenceContext) -> ExprID? {
        switch ctx.ast.arena.expr(expression) {
        case .callableRef:
            return expression
        case let .blockExpr(_, trailingExpr?, _):
            return terminalCallableReference(in: trailingExpr, ctx: ctx)
        default:
            return nil
        }
    }

    private func callableReferenceWrappers(in expression: ExprID, ctx: TypeInferenceContext) -> [ExprID] {
        switch ctx.ast.arena.expr(expression) {
        case let .blockExpr(_, trailingExpr?, _):
            return callableReferenceWrappers(in: trailingExpr, ctx: ctx) + [expression]
        default:
            return []
        }
    }

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
