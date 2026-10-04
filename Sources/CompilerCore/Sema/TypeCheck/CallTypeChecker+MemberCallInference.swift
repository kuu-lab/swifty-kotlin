
extension CallTypeChecker {
    func inferMemberCallImpl(
        _ id: ExprID,
        receiverID: ExprID,
        calleeName: InternedString,
        args: [CallArgument],
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID?,
        explicitTypeArgs: [TypeID],
        safeCall: Bool
    ) -> TypeID {
        let request = MemberCallInferenceRequest(
            id: id,
            receiverID: receiverID,
            calleeName: calleeName,
            args: args,
            range: range,
            ctx: ctx,
            expectedType: expectedType,
            explicitTypeArgs: explicitTypeArgs,
            safeCall: safeCall
        )

        markDeferredCollectionHOFLambdaIfNeeded(request)

        if let result = tryInferMemberCallWithoutReceiverSpecials(request, locals: &locals) {
            return result
        }

        if let result = tryInferFQNQualifiedValue(request, locals: locals) {
            return result
        }

        if let result = tryInferFQNPackageTopLevelCall(request, locals: &locals) {
            return result
        }

        let receiverType = driver.inferExpr(receiverID, ctx: ctx, locals: &locals)
        // The invalid super receiver already emitted its own diagnostic.
        // Resolving a member on the error type can introduce unrelated
        // extension candidates and produce a misleading overload error.
        if receiverType == ctx.sema.types.errorType,
           case .superRef = ctx.ast.arena.expr(receiverID)
        {
            ctx.sema.bindings.bindExprType(id, type: ctx.sema.types.errorType)
            return ctx.sema.types.errorType
        }
        if let result = tryInferMemberCallEarlyReceiverSpecials(
            request,
            receiverType: receiverType,
            locals: &locals
        ) {
            return result
        }

        if let result = tryInferMemberCallScopeResultAndFileSpecials(
            request,
            receiverType: receiverType,
            locals: &locals
        ) {
            return result
        }

        if let result = tryInferMemberCallCollectionFlowSpecials(
            request,
            receiverType: receiverType,
            locals: &locals
        ) {
            return result
        }

        if let result = tryInferMemberCallStringRangeComparatorSpecials(
            request,
            receiverType: receiverType,
            locals: &locals
        ) {
            return result
        }

        return inferRegularMemberCall(request, receiverType: receiverType, locals: &locals)
    }
}
