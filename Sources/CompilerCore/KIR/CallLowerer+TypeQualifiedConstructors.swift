extension CallLowerer {
    /// Lowers a constructor selected through a static nested-class qualifier
    /// (`Outer.Inner(...)`). The qualifier names a type, not an object value,
    /// so the constructor must use the ordinary allocation path without a
    /// receiver expression in the argument list.
    func tryLowerTypeQualifiedConstructorCall(
        _ exprID: ExprID,
        calleeName: InternedString,
        args: [CallArgument],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard sema.bindings.isTypeQualifiedConstructorCallExpr(exprID),
              let callBinding = sema.bindings.callBinding(for: exprID)
        else {
            return nil
        }

        let chosen = callBinding.chosenCallee
        let loweredArgIDs = args.enumerated().map { argumentIndex, argument in
            let previousAllowance = driver.ctx.pendingLambdaNonLocalReturnAllowance
            driver.ctx.pendingLambdaNonLocalReturnAllowance = allowsNonLocalReturn(
                argumentExpr: argument.expr,
                argumentIndex: argumentIndex,
                ast: ast,
                sema: sema,
                callBinding: callBinding,
                chosen: chosen
            )
            defer {
                driver.ctx.pendingLambdaNonLocalReturnAllowance = previousAllowance
            }
            return driver.lowerExpr(
                argument.expr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
        }

        return lowerResolvedCallBody(
            exprID,
            args: args,
            loweredArgIDs: loweredArgIDs,
            chosen: chosen,
            callBinding: callBinding,
            callableValueCallBinding: nil,
            loweredCallable: nil,
            loweredCalleeExprID: nil,
            sourceCalleeName: calleeName,
            boundType: sema.bindings.exprTypes[exprID],
            knownNames: KnownCompilerNames(interner: interner),
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
    }
}
