extension CallTypeChecker.MemberCallCollectionFlowContext {
    /// `val xs: List<Int> = ints.fold(emptyList()) { acc, x -> acc + x }`: the
    /// initial value only gives the accumulator `R` a lower bound
    /// (`List<Nothing>`), while the expected type is its upper bound. Fixing `R`
    /// to the initial type alone would pin both `acc` and the lambda's result to
    /// `List<Nothing>`, so every non-empty accumulator was rejected. When the
    /// initial type still has uninferred (`Nothing`) arguments and the call has
    /// a fully known class-typed expected type, `R` is that expected type and
    /// the initial value is inferred against it (`emptyMap()` then becomes
    /// `Map<Int, List<String>>`), as in kotlinc. kotlinc rejects the same call
    /// when nothing constrains `R` ("cannot infer type for type parameter 'R'"),
    /// so any other call keeps `R = initial`.
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
            // The caller's first `inferExpr` ran without an expected type, so
            // a bare factory initial (`emptyList()`) already reported
            // KSWIFTK-SEMA-INFER eagerly before the checkpoint above. The
            // expected-typed re-inference discharged it, so drop that
            // argument's own stale diagnostic the way
            // discardRescuedNestedCallArgumentDiagnostics does (KUU-4483).
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
