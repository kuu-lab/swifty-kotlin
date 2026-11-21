
extension CallLowerer {
    func tryLowerLexicalExtensionCallableInvocation(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        loweredReceiverID: KIRExprID,
        calleeName: InternedString,
        args: [CallArgument],
        shared: KIRLoweringSharedContext,
        emit instructions: inout KIRLoweringEmitContext
    ) -> KIRExprID? {
        let sema = shared.sema
        guard let binding = sema.bindings.callableValueCalls[exprID],
              let calleeExpr = binding.extensionCallableExpr
        else {
            return nil
        }
        let functionValue = driver.lowerExpr(calleeExpr, shared: shared, emit: &instructions)
        let loweredArgs = args.map { driver.lowerExpr($0.expr, shared: shared, emit: &instructions) }
        return lowerResolvedCallBody(
            exprID,
            args: [CallArgument(expr: receiverExpr)] + args,
            loweredArgIDs: [loweredReceiverID] + loweredArgs,
            chosen: nil,
            callBinding: nil,
            callableValueCallBinding: binding,
            loweredCallable: driver.ctx.callableValueInfo(for: functionValue),
            loweredCalleeExprID: functionValue,
            sourceCalleeName: calleeName,
            boundType: sema.bindings.exprTypes[exprID],
            knownNames: KnownCompilerNames(interner: shared.interner),
            ast: shared.ast,
            sema: sema,
            arena: shared.arena,
            interner: shared.interner,
            propertyConstantInitializers: shared.propertyConstantInitializers,
            instructions: &instructions.instructions
        )
    }

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
