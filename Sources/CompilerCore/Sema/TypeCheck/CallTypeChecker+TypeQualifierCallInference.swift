extension CallTypeChecker {
    /// `G<Int>.GI()` parses `G<Int>` as a `.call` whose `typeArgs` carry the
    /// type arguments; `isTypeQualifierCall` marks that the node names a
    /// classifier qualifier rather than a zero-argument call. Resolve the
    /// callee path through the same `resolveTypeRef` machinery that handles
    /// `val x: A<B>.C` type references so member resolution sees the same
    /// class-name receiver as `G.GI()`.
    ///
    /// Returns nil when the callee chain is not a classifier path — e.g. a
    /// value expression such as `x.f<T>.y`, where `x.f<T>` is a value
    /// reference with explicit type arguments — so the caller falls back to
    /// ordinary call inference.
    func inferTypeQualifierCallExpr(
        _ id: ExprID,
        calleeID: ExprID,
        range: SourceRange,
        ctx: TypeInferenceContext
    ) -> TypeID? {
        let ast = ctx.ast
        let sema = ctx.sema

        var path: [InternedString] = []
        var argRefs: [TypeArgRef] = []
        var terminalExprID: ExprID?

        // Walks the qualifier chain in path order. A segment contributes its
        // name to `path` and any explicit type arguments to `argRefs` right
        // after it; `resolveTypeRef` then folds the flattened list into the
        // resolved class type's `enclosingTypeArgs` + `args`, matching the
        // `A<B>.C` type-reference form.
        func appendPath(from exprID: ExprID) -> Bool {
            guard let expr = ast.arena.expr(exprID) else { return false }
            switch expr {
            case let .nameRef(name, _):
                path.append(name)
                terminalExprID = exprID
                return true
            case let .memberCall(owner, name, segmentTypeArgs, segmentArgs, _):
                guard segmentArgs.isEmpty, !ast.arena.isExplicitCall(exprID),
                      appendPath(from: owner)
                else { return false }
                path.append(name)
                argRefs.append(contentsOf: segmentTypeArgs.map { TypeArgRef.invariant($0) })
                return true
            case let .call(callee, callTypeArgs, callArgs, _):
                guard callArgs.isEmpty, ast.arena.isTypeQualifierCall(exprID),
                      appendPath(from: callee)
                else { return false }
                argRefs.append(contentsOf: callTypeArgs.map { TypeArgRef.invariant($0) })
                return true
            default:
                return false
            }
        }

        guard appendPath(from: calleeID), !path.isEmpty else { return nil }

        let typeRefID = ast.arena.appendTypeRef(
            .named(path: path, args: argRefs, nullable: false)
        )
        // Resolve silently: a non-classifier callee (`x.f<T>.y`) must fall
        // back to ordinary call inference without emitting type diagnostics.
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
        // `identifierSymbol` on the `.call` marks a class-name receiver for
        // `classNameReceiverNominalSymbol`; the terminal leaf binding lets KIR
        // lower the qualifier like the bare classifier name of `Outer.Inner()`.
        sema.bindings.bindIdentifier(id, symbol: nominal)
        if let terminalExprID {
            sema.bindings.bindIdentifier(terminalExprID, symbol: nominal)
            sema.bindings.bindExprType(terminalExprID, type: resolved)
        }
        sema.bindings.bindExprType(id, type: resolved)
        return resolved
    }
}
