extension CallTypeChecker {
    func inferTypeQualifierCallExpr(
        _ id: ExprID,
        calleeID: ExprID,
        range: SourceRange,
        ctx: TypeInferenceContext
    ) -> TypeID? {
        let ast = ctx.ast
        let sema = ctx.sema

        var segments: [NamedTypeSegment] = []
        var terminalExprID: ExprID?

        func appendPath(from exprID: ExprID) -> Bool {
            guard let expr = ast.arena.expr(exprID) else { return false }
            switch expr {
            case let .nameRef(name, _):
                segments.append(NamedTypeSegment(name: name))
                terminalExprID = exprID
                return true
            case let .memberCall(owner, name, segmentTypeArgs, segmentArgs, _):
                guard segmentArgs.isEmpty, !ast.arena.isExplicitCall(exprID),
                      appendPath(from: owner)
                else { return false }
                segments.append(NamedTypeSegment(name: name, args: segmentTypeArgs.map { TypeArgRef.invariant($0) }))
                return true
            case let .call(callee, callTypeArgs, callArgs, _):
                guard callArgs.isEmpty, ast.arena.isTypeQualifierCall(exprID),
                      appendPath(from: callee)
                else { return false }
                guard let last = segments.popLast() else { return false }
                segments.append(NamedTypeSegment(
                    name: last.name,
                    args: last.args + callTypeArgs.map { TypeArgRef.invariant($0) }
                ))
                return true
            default:
                return false
            }
        }

        guard appendPath(from: calleeID), !segments.isEmpty else { return nil }

        let typeRef: TypeRef = if segments.dropLast().contains(where: { !$0.args.isEmpty }) {
            .qualifiedNamed(segments: segments, nullable: false)
        } else {
            .named(path: segments.map(\.name), args: segments.last?.args ?? [], nullable: false)
        }
        let typeRefID = ast.arena.appendTypeRef(typeRef)
        let resolved = driver.helpers.resolveTypeRef(
            typeRefID,
            ast: ast,
            sema: sema,
            interner: ctx.interner,
            scope: ctx.scope,
            diagnostics: nil,
            inferenceContext: ctx,
            usageRange: range
        )
        guard let nominal = driver.helpers.nominalSymbol(of: resolved, types: sema.types) else {
            return nil
        }
        sema.bindings.bindIdentifier(id, symbol: nominal)
        if let terminalExprID {
            sema.bindings.bindIdentifier(terminalExprID, symbol: nominal)
            sema.bindings.bindExprType(terminalExprID, type: resolved)
        }
        sema.bindings.bindExprType(id, type: resolved)
        return resolved
    }
}
