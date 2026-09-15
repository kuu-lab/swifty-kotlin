extension CollectionLiteralConstructionLoweringPass {
    /// Resolve the representation evidence used by the direct-call policy.
    ///
    /// The rewrite state is the source of runtime provenance.  When it has no
    /// runtime fact, a resolved receiver signature can still prove that the
    /// call is a non-Sequence extension (or a top-level function); it cannot
    /// prove which representation backs a `Sequence` receiver, so that case
    /// remains `.unknown`.
    private func sequenceRuntimeRepresentationForCall(
        symbol: SymbolID?,
        arguments: [KIRExprID],
        state: CollectionRewriteState,
        ctx: KIRContext
    ) -> CollectionLiteralLoweringSupport.SequenceRuntimeRepresentation {
        guard let receiverID = arguments.first else {
            return .notSequence
        }

        let representation = state.sequenceRuntimeRepresentation(of: receiverID)
        guard representation == .unknown,
              let symbol,
              let sema = ctx.sema,
              sema.symbols.symbol(symbol) != nil,
              let signature = sema.symbols.functionSignature(for: symbol)
        else {
            return representation
        }

        guard let receiverType = signature.receiverType else {
            return .notSequence
        }
        guard let (_, receiverSymbol) = resolveClassTypeSymbol(receiverType, sema: sema) else {
            return representation
        }
        let sequenceFQName = [
            ctx.interner.intern("kotlin"),
            ctx.interner.intern("sequences"),
            ctx.interner.intern("Sequence"),
        ]
        return receiverSymbol.fqName == sequenceFQName ? .unknown : .notSequence
    }

    /// Adapts this pass's rewrite state to `SourceBackedCallPreservationPolicy`
    /// inputs. RF-LOWER-CALL-007 moved the decision itself — the preserved API
    /// name sets and array-conversion branch — into the policy; what stays here
    /// is the receiver bookkeeping the policy must not know about. Every input
    /// is an `@autoclosure` so the symbol-table and signature lookups still run
    /// only after a name matches, as they did when this was one predicate.
    private func shouldPreserveSourceBackedAggregateCall(
        symbol: SymbolID?,
        callee: InternedString,
        arguments: [KIRExprID],
        state: CollectionRewriteState,
        ctx: KIRContext
    ) -> Bool {
        sourceBackedPreservation.preservesDirectCall(
            callee: callee,
            resolution: SourceBackedCalleeResolution(symbol: symbol, sema: ctx.sema),
            receiverIsTrackedArrayLiteral: arguments.first.map {
                state.arrayExprIDs.contains($0.rawValue)
            } ?? false,
            sequenceRuntimeRepresentation: sequenceRuntimeRepresentationForCall(
                symbol: symbol,
                arguments: arguments,
                state: state,
                ctx: ctx
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

        if shouldPreserveSourceBackedAggregateCall(
            symbol: symbol,
            callee: callee,
            arguments: arguments,
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
