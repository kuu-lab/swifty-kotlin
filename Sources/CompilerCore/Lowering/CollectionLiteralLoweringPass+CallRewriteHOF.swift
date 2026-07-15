/// Higher-order collection call rewrites split out from
/// `CollectionLiteralLoweringPass+CallRewrite.swift`.
extension CollectionLiteralConstructionLoweringPass {
    func rewriteHigherOrderCollectionCall(
        callee: InternedString,
        arguments: [KIRExprID],
        result: KIRExprID?,
        canThrow: Bool,
        thrownResult: KIRExprID?,
        function: KIRFunction,
        module: KIRModule,
        ctx: KIRContext,
        lookup: CollectionLiteralLookupTables,
        state: inout CollectionRewriteState,
        loweredBody: inout [KIRInstruction]
    ) -> Bool {
        if let receiverCandidate = arguments.first {
            classifyTrackedExprByStaticType(
                receiverCandidate,
                module: module,
                sema: ctx.sema,
                interner: ctx.interner,
                state: &state
            )
        }

        if rewriteCoreHigherOrderCollectionCall(
            callee: callee,
            arguments: arguments,
            result: result,
            canThrow: canThrow,
            thrownResult: thrownResult,
            module: module,
            lookup: lookup,
            state: &state,
            loweredBody: &loweredBody
        ) {
            return true
        }

        if rewriteTransformHigherOrderCollectionCall(
            callee: callee,
            arguments: arguments,
            result: result,
            canThrow: canThrow,
            thrownResult: thrownResult,
            module: module,
            ctx: ctx,
            lookup: lookup,
            state: &state,
            loweredBody: &loweredBody
        ) {
            return true
        }

        if rewriteExtremaHigherOrderCollectionCall(
            callee: callee,
            arguments: arguments,
            result: result,
            canThrow: canThrow,
            thrownResult: thrownResult,
            function: function,
            module: module,
            lookup: lookup,
            state: &state,
            loweredBody: &loweredBody
        ) {
            return true
        }

        if rewriteAccumulationHigherOrderCollectionCall(
            callee: callee,
            arguments: arguments,
            result: result,
            canThrow: canThrow,
            thrownResult: thrownResult,
            module: module,
            lookup: lookup,
            state: &state,
            loweredBody: &loweredBody
        ) {
            return true
        }

        return false
    }
}
