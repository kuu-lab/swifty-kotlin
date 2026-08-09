extension CollectionLiteralConstructionLoweringPass {
    private func shouldPreserveSourceBackedAggregateCall(
        symbol: SymbolID?,
        callee: InternedString,
        arguments: [KIRExprID],
        state: CollectionRewriteState,
        lookup: CollectionLiteralLookupTables,
        ctx: KIRContext
    ) -> Bool {
        guard callee == lookup.foldName
            || callee == lookup.foldRightName
            || callee == lookup.reduceName
            || callee == lookup.reduceOrNullName
            || callee == lookup.scanName
            || callee == lookup.scanIndexedName
            || callee == lookup.scanReduceName
            || callee == lookup.runningFoldName
            || callee == lookup.runningFoldIndexedName
            || callee == lookup.runningReduceName
            || callee == lookup.runningReduceIndexedName
            || callee == lookup.foldIndexedName
            || callee == lookup.foldRightIndexedName
            || callee == lookup.reduceRightName
            || callee == lookup.reduceRightOrNullName
            || callee == lookup.reduceRightIndexedName
            || callee == lookup.reduceRightIndexedOrNullName
            || callee == lookup.reduceIndexedName
            || callee == lookup.reduceIndexedOrNullName
            || callee == lookup.filterName
            || callee == lookup.filterNotName
            || callee == lookup.filterNotNullName
            || callee == lookup.filterIndexedName
            || callee == lookup.associateName
            || callee == lookup.associateByName
            || callee == lookup.groupByName
            || callee == lookup.sumOfName
            || callee == lookup.maxByOrNullName
            || callee == lookup.minByOrNullName
            // KSP-421: List transform HOFs have Kotlin source implementations.
            || callee == lookup.mapName
            || callee == lookup.mapIndexedName
            || callee == lookup.mapNotNullName
            || callee == lookup.mapIndexedNotNullName
            || callee == lookup.mapToName
            || callee == lookup.mapIndexedToName
            || callee == lookup.mapNotNullToName
            || callee == lookup.mapIndexedNotNullToName
            || callee == lookup.flatMapName
            || callee == lookup.flatMapIndexedName
            || callee == lookup.flatMapToName
            || callee == lookup.flatMapIndexedToName
            || callee == lookup.flattenName
            // KSP-430: Map higher-order functions have Kotlin source implementations.
            || callee == lookup.mapValuesName
            || callee == lookup.mapValuesToName
            || callee == lookup.mapKeysName
            || callee == lookup.mapKeysToName
            || callee == lookup.filterKeysName
            || callee == lookup.filterValuesName
            || callee == lookup.forEachName
            // STDLIB-pipeline §5: take/drop have real require() validation in
            // SequenceWindowChunk.kt as of MIGRATION-SEQ-005. A resolved call
            // to that source declaration must not be short-circuited to the
            // unchecked kk_sequence_take/drop runtime bridge.
            || callee == lookup.takeName
            || callee == lookup.dropName
            // KSP-423: List search and predicate HOFs have Kotlin source implementations.
            || callee == lookup.findName
            || callee == lookup.findLastName
            || callee == lookup.indexOfName
            || callee == lookup.lastIndexOfName
            || callee == lookup.indexOfFirstName
            || callee == lookup.indexOfLastName
            || callee == lookup.containsName
            || callee == lookup.containsAllName
            || callee == lookup.countName
            || callee == lookup.anyName
            || callee == lookup.allName
            || callee == lookup.noneName
            || callee == lookup.firstName
            || callee == lookup.lastName
            || callee == lookup.firstOrNullName
            || callee == lookup.lastOrNullName
            // KSP-658: generic Array<T>.copyOf / copyOfRange have Kotlin source implementations.
            || callee == lookup.copyOfName
            || callee == lookup.copyOfRangeName,
            let symbol,
            let sema = ctx.sema,
            sema.symbols.symbol(symbol) != nil
        else {
            return false
        }
        guard sema.symbols.isSourceBackedSymbol(symbol) else {
            return false
        }
        // STDLIB-pipeline §5 / KSP-441: take/drop have real require() validation
        // in bundled source, but a runtime Sequence handle cannot be iterated by
        // the source object-expression iterator. Allow the lowering pipeline to
        // rewrite to kk_sequence_take/kk_sequence_drop when the receiver is known
        // to be a runtime Sequence box.
        //
        // The same applies to map/filter: source Sequence.map walks a source
        // Sequence object via iterator(), but RuntimeSequenceBox (from
        // kk_array_asSequence / kk_list_asSequence) has no itable map entry and
        // must go through kk_sequence_map/filter.
        if let receiverID = arguments.first,
           state.sequenceExprIDs.contains(receiverID.rawValue),
           callee == lookup.takeName
            || callee == lookup.dropName
            || callee == lookup.mapName
            || callee == lookup.filterName
        {
            return false
        }
        // A Sequence-typed receiver may still be a RuntimeSequenceBox at run
        // time (e.g. a parameter fed by asSequence()), which the source
        // iterator cannot walk. flatMap/flatMapIndexed are excluded: their
        // bundled source implementations traverse the receiver through the
        // shared iterator bridge and are the KSP-441 source pipeline.
        if (callee == lookup.mapName || callee == lookup.filterName),
           isSequenceReceiverType(symbol: symbol, ctx: ctx) {
            return false
        }
        return true
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
        builderLambdaKinds: [InternedString: InternedString],
        module: KIRModule,
        ctx: KIRContext,
        lookup: CollectionLiteralLookupTables,
        state: inout CollectionRewriteState,
        loweredBody: inout [KIRInstruction]
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
            function: function,
            builderLambdaKinds: builderLambdaKinds,
            module: module,
            ctx: ctx,
            lookup: lookup,
            state: &state,
            loweredBody: &loweredBody
        ) {
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
            lookup: lookup,
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
            function: function,
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
