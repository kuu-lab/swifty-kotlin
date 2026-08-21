
extension CallLowerer {
    /// Lowers a `.memberCall` resolved by Sema's FQN-package-qualified
    /// top-level lookup (`CallTypeChecker.tryInferFQNPackageTopLevelCall`),
    /// e.g. `kotlin.math.abs(x)` or `kotlin.text.StringBuilder()`. That
    /// resolution fires before receiver inference, so the receiver
    /// expression (the namespace path `kotlin.math`/`kotlin.text`) never
    /// gets a Sema type binding — it is not a real value, just a
    /// disambiguating qualifier. Lowering it as one anyway (the ordinary
    /// `.memberCall` path) tries to evaluate the bogus chain, which either
    /// fails to link (an unresolved multi-segment chain is treated as a
    /// global/property load, e.g. an undefined `_math`/`_text` symbol) or,
    /// for a resolved constructor, silently prepends a bogus receiver
    /// argument that shifts the real constructor arguments by one slot and
    /// drops the last one. Marked explicitly by Sema
    /// (`markFQNTopLevelCallExpr`) rather than inferred from the receiver's
    /// missing type binding, so this can never misfire on some other
    /// receiver-skipping special case that happens to leave the receiver
    /// untyped for an unrelated reason.
    func tryLowerFQNTopLevelResolvedCall(
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
        guard sema.bindings.isFQNTopLevelCallExpr(exprID),
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
