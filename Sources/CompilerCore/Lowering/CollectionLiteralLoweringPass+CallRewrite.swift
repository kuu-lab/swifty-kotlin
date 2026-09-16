extension CollectionLiteralConstructionLoweringPass {
    /// Keep resolved source declarations on the original call path unless the
    /// receiver is a confirmed runtime Sequence box. Runtime-specific
    /// collection intrinsics are emitted under their `kk_*` callee before this
    /// gate and therefore do not need an API-name exception here.
    private func shouldPreserveSourceBackedCall(
        symbol: SymbolID?,
        arguments: [KIRExprID],
        module: KIRModule,
        state: CollectionRewriteState,
        ctx: KIRContext
    ) -> Bool {
        sourceBackedPreservation.preserves(
            resolution: SourceBackedCalleeResolution(symbol: symbol, sema: ctx.sema),
            sequenceRuntimeRepresentation: sequenceRuntimeRepresentationForCall(
                symbol: symbol,
                receiver: arguments.first,
                state: state,
                module: module,
                sema: ctx.sema,
                interner: ctx.interner
            )
        )
    }

    func lowerCallInstruction(
        instruction: KIRInstruction,
        symbol: SymbolID?,
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
        loweredBody: inout KIRLoweringEmitContext
    ) {
        // kk_sequence_requireNoNulls is emitted directly by CallLowerer when the
        // bundled source declaration is absent. Track its result as a runtime
        // Sequence handle so downstream take/drop rewrites still fire.
        if callee == lookup.kkSequenceRequireNoNullsName, let result {
            state.sequenceExprIDs.insert(result.rawValue)
        }
        if rewriteFactoryAndBuilderCall(
            symbol: symbol,
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
            // Concrete-class collection constructors (`LinkedHashSet()`,
            // `HashMap()`, ...) are rewritten to runtime factories whose
            // returned boxes never pass `kk_object_new`, so the
            // constructor-site vtable registrations never ran for them.
            // Register the nominal vtable implementations on the box so an
            // open member dispatch (e.g. `LinkedHashSet.size`) resolves
            // instead of trapping at `kk_vtable_lookup`. No-ops for
            // interface-typed results.
            appendFactoryResultVtableRegistrations(
                result: result,
                module: module,
                ctx: ctx,
                loweredBody: &loweredBody
            )
            return
        }

        if rewriteFileCall(
            symbol: symbol,
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
            return
        }

        if rewriteArrayAndIteratorBridgeCall(
            symbol: symbol,
            callee: callee,
            arguments: arguments,
            result: result,
            module: module,
            ctx: ctx,
            lookup: lookup,
            state: &state,
            loweredBody: &loweredBody
        ) {
            return
        }

        if shouldPreserveSourceBackedCall(
            symbol: symbol,
            arguments: arguments,
            module: module,
            state: state,
            ctx: ctx
        ) {
            loweredBody.append(instruction)
            return
        }

        if rewriteCollectionMemberCall(
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
            return
        }

        if rewriteSequenceCollectionCall(
            symbol: symbol,
            callee: callee,
            arguments: arguments,
            result: result,
            canThrow: canThrow,
            thrownResult: thrownResult,
            instruction: instruction,
            module: module,
            ctx: ctx,
            lookup: lookup,
            state: &state,
            loweredBody: &loweredBody
        ) {
            return
        }

        if rewriteHigherOrderCollectionCall(
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
            return
        }

        if rewriteRuntimeAdapterCall(
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
            return
        }

        loweredBody.append(instruction)
    }
}
