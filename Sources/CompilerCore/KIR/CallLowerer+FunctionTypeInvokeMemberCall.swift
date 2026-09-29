
/// Lowering for an explicit `.invoke(...)` member call whose receiver's own
/// type is a function type (`(Int) -> Int`, `Int.(Int) -> Int`, ...).
///
/// Sema (`CallTypeChecker+MemberCallInferenceRegularResolution.swift`)
/// intercepts this call shape directly, since a function-typed receiver has
/// no nominal owner to dispatch a member through, and binds a
/// `CallableValueCallBinding` exactly like a bare call (`f(3)`) or
/// extension-receiver call sugar (`1.ef(2)`). This mirrors `lowerCallExpr`'s
/// callable-value path (`CallLowerer.swift`) so all three forms share the
/// same runtime ABI selection (`kk_function_invoke*`) and fast-path
/// (`KIRCallableValueInfo`) lookup.
extension CallLowerer {
    func tryLowerFunctionTypeInvokeMemberCall(
        _ exprID: ExprID,
        calleeName: InternedString,
        args: [CallArgument],
        loweredReceiverID: KIRExprID,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard interner.resolve(calleeName) == "invoke",
              let callableValueCallBinding = sema.bindings.callableValueCalls[exprID],
              case .functionType = sema.types.kind(
                  of: sema.types.makeNonNullable(callableValueCallBinding.functionType)
              )
        else {
            return nil
        }
        let loweredArgIDs = args.map { argument in
            driver.lowerExpr(
                argument.expr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
        }
        let loweredCallable = driver.ctx.callableValueInfo(for: loweredReceiverID)
        return lowerResolvedCallBody(
            exprID,
            args: args,
            loweredArgIDs: loweredArgIDs,
            chosen: nil,
            callBinding: nil,
            callableValueCallBinding: callableValueCallBinding,
            loweredCallable: loweredCallable,
            loweredCalleeExprID: loweredReceiverID,
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
