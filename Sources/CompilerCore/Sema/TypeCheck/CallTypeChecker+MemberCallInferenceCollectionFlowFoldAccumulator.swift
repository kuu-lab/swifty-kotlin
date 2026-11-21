extension CallTypeChecker.MemberCallCollectionFlowContext {
    func inferFoldAccumulatorType(initialType: TypeID, locals: inout LocalBindings) -> TypeID {
        guard hasUninferredTypeArgument(initialType), let expectedType else {
            return initialType
        }
        let accumulatorType = sema.types.makeNonNullable(expectedType)
        guard case .classType = sema.types.kind(of: accumulatorType),
              !hasUninferredTypeArgument(accumulatorType),
              !sema.types.typeContainsAnyTypeParam(accumulatorType)
        else {
            return initialType
        }
        let checkpoint = sema.diagnostics.checkpoint()
        let contextualInitialType = driver.inferExpr(
            args[0].expr,
            ctx: ctx,
            locals: &locals,
            expectedType: accumulatorType
        )
        let failed = sema.diagnostics.diagnostics.dropFirst(checkpoint).contains { $0.severity == .error }
        if !failed, sema.types.isSubtype(contextualInitialType, accumulatorType) {
            if let argumentRange = ast.arena.exprRange(args[0].expr) {
                for diagnostic in sema.diagnostics.removeErrorDiagnostics(containedIn: argumentRange)
                where diagnostic.code != "KSWIFTK-SEMA-INFER" || diagnostic.primaryRange != argumentRange {
                    sema.diagnostics.emit(diagnostic)
                }
            }
            return accumulatorType
        }
        sema.diagnostics.rollback(to: checkpoint)
        _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
        return initialType
    }

    private func hasUninferredTypeArgument(_ type: TypeID) -> Bool {
        guard case let .classType(classType) = sema.types.kind(of: type) else {
            return false
        }
        return classType.args.contains { arg in
            switch arg {
            case let .invariant(inner), let .out(inner), let .in(inner):
                if case .nothing = sema.types.kind(of: inner) { return true }
                return hasUninferredTypeArgument(inner)
            case .star:
                return false
            }
        }
    }
}
