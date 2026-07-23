extension CollectionLiteralConstructionLoweringPass {
    private func shouldPreserveSourceBackedAggregateCall(
        symbol: SymbolID?,
        callee: InternedString,
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
            || callee == lookup.firstOrNullName
            || callee == lookup.lastOrNullName,
            let symbol,
            let sema = ctx.sema,
            let semanticSymbol = sema.symbols.symbol(symbol),
            semanticSymbol.declSite != nil
        else {
            return false
        }
        return (sema.symbols.externalLinkName(for: symbol) ?? "").isEmpty
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
