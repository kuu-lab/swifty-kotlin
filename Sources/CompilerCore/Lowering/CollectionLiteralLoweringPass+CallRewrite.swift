
extension CollectionLiteralLoweringPass {
    private func shouldPreserveSourceBackedCollectionHOFCall(
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
            || callee == lookup.runningFoldName
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
            || callee == lookup.filterName
            || callee == lookup.filterNotName
            || callee == lookup.filterNotNullName
            || callee == lookup.filterIndexedName
            || callee == lookup.filterIsInstanceName
            || callee == lookup.filterToName
            || callee == lookup.filterNotToName
            || callee == lookup.filterNotNullToName
            || callee == lookup.filterIndexedToName
            || callee == lookup.filterIsInstanceToName,
            let symbol,
            let sema = ctx.sema,
            let semanticSymbol = sema.symbols.symbol(symbol),
            semanticSymbol.declSite != nil
        else {
            return false
        }
        return (sema.symbols.externalLinkName(for: symbol) ?? "").isEmpty
    }

    func rewriteCalls(module: KIRModule, ctx: KIRContext) throws {
        let lookup = CollectionLiteralLookupTables(interner: ctx.interner)
        let builderLambdaKinds = collectBuilderLambdaKinds(
            module: module,
            lookup: lookup,
            ctx: ctx
        )

        func transformFunction(_ function: KIRFunction) -> KIRFunction {
            var updated: KIRFunction = function

            // Phase 1: Identify collection-typed expression IDs
            var state = CollectionRewriteState()

            collectInitialCollectionExprIDs(
                function: function,
                lookup: lookup,
                arena: module.arena,
                sema: ctx.sema,
                interner: ctx.interner,
                listExprIDs: &state.listExprIDs,
                setExprIDs: &state.setExprIDs,
                mapExprIDs: &state.mapExprIDs,
                arrayExprIDs: &state.arrayExprIDs,
                sequenceExprIDs: &state.sequenceExprIDs,
                rangeExprIDs: &state.rangeExprIDs,
                charRangeExprIDs: &state.charRangeExprIDs,
                ulongRangeExprIDs: &state.ulongRangeExprIDs,
                stringExprIDs: &state.stringExprIDs,
                fileExprIDs: &state.fileExprIDs,
                pathExprIDs: &state.pathExprIDs
            )

            // Phase 2: Rewrite instructions
            var loweredBody: [KIRInstruction] = []
            loweredBody.reserveCapacity(function.body.count + 32)

            for instruction in function.body {
                switch instruction {
                case let .call(symbol, callee, arguments, result, canThrow, thrownResult, _, _):
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
                        continue
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
                        continue
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
                        continue
                    }

                    if shouldPreserveSourceBackedAggregateCall(
                        symbol: symbol,
                        callee: callee,
                        lookup: lookup,
                        ctx: ctx
                    ) {
                        loweredBody.append(instruction)
                        continue
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
                        continue
                    }

                    if shouldPreserveSourceBackedCollectionHOFCall(
                        symbol: symbol,
                        callee: callee,
                        lookup: lookup,
                        ctx: ctx
                    ) {
                        loweredBody.append(instruction)
                        continue
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
                        continue
                    }

                    if rewriteHigherOrderCollectionCall(
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
                        continue
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
                        continue
                    }

                    // Default: keep instruction as-is
                    loweredBody.append(instruction)

                case let .virtualCall(_, callee, receiver, arguments, result, origCanThrow, origThrownResult, _):
                    if rewriteVirtualCallInstruction(
                        callee: callee,
                        receiver: receiver,
                        arguments: arguments,
                        result: result,
                        origCanThrow: origCanThrow,
                        origThrownResult: origThrownResult,
                        context: .init(module: module, lookup: lookup, functionBody: function.body, sema: ctx.sema, interner: ctx.interner),
                        listExprIDs: &state.listExprIDs,
                        setExprIDs: &state.setExprIDs,
                        mapExprIDs: &state.mapExprIDs,
                        arrayExprIDs: &state.arrayExprIDs,
                        sequenceExprIDs: &state.sequenceExprIDs,
                        rangeExprIDs: &state.rangeExprIDs,
                        charRangeExprIDs: &state.charRangeExprIDs,
                        ulongRangeExprIDs: &state.ulongRangeExprIDs,
                        fileExprIDs: &state.fileExprIDs,
                        pathExprIDs: &state.pathExprIDs,
                        indexingIterableExprIDs: &state.indexingIterableExprIDs,
                        loweredBody: &loweredBody
                    ) {
                        continue
                    }
                    loweredBody.append(instruction)

                case let .copy(from, to):
                    // Track copies of collection expressions
                    state.propagateCopy(from: from, to: to)
                    loweredBody.append(instruction)

                default:
                    loweredBody.append(instruction)
                }
            }

            updated.replaceBody(loweredBody)
            return updated
        }
        module.arena.transformFunctions(transformFunction)
        module.recordLowering(Self.name)
    }
}
