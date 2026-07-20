
extension CollectionLiteralConstructionLoweringPass {

    /// Rewrites late-stage runtime call adapters after direct collection/HOF rewrites.
    func rewriteRuntimeAdapterCall(
        callee: InternedString,
        arguments: [KIRExprID],
        result: KIRExprID?,
        canThrow: Bool,
        thrownResult: KIRExprID?,
        function: KIRFunction,
        module: KIRModule,
        lookup: CollectionLiteralLookupTables,
        state: inout CollectionRewriteState,
        loweredBody: inout [KIRInstruction]
    ) -> Bool {
        // Rewrite println on list/map → kk_list_to_string / kk_map_to_string
        if callee == lookup.kkPrintlnAnyName || callee == lookup.printlnName, arguments.count == 1 {
            let argID = arguments[0]
            if state.listExprIDs.contains(argID.rawValue) {
                let strResult = module.arena.appendTemporary(type: nil
                )
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkListToStringName,
                    arguments: [argID],
                    result: strResult,
                    canThrow: false,
                    thrownResult: nil
                ))
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkPrintlnAnyName,
                    arguments: [strResult],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return true
            }
            if state.setExprIDs.contains(argID.rawValue) {
                let strResult = module.arena.appendTemporary(type: nil
                )
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkSetToStringName,
                    arguments: [argID],
                    result: strResult,
                    canThrow: false,
                    thrownResult: nil
                ))
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkPrintlnAnyName,
                    arguments: [strResult],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return true
            }
            if state.mapExprIDs.contains(argID.rawValue) {
                let strResult = module.arena.appendTemporary(type: nil
                )
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkMapToStringName,
                    arguments: [argID],
                    result: strResult,
                    canThrow: false,
                    thrownResult: nil
                ))
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkPrintlnAnyName,
                    arguments: [strResult],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return true
            }
        }

        if callee == lookup.kkAnyToStringName, arguments.count >= 1 {
            let argID = arguments[0]
            if state.listExprIDs.contains(argID.rawValue) {
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkListToStringName,
                    arguments: [argID],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return true
            }
            if state.setExprIDs.contains(argID.rawValue) {
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkSetToStringName,
                    arguments: [argID],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return true
            }
            if state.mapExprIDs.contains(argID.rawValue) {
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkMapToStringName,
                    arguments: [argID],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return true
            }
        }

        // --- sortedWith with Comparator argument (STDLIB-649) ---
        // When kk_list_sortedWith is emitted as a .call (from synthetic stub),
        // the comparator argument needs trampoline/closure expansion.
        // args layout: [receiver, comparatorExpr]
        if callee == lookup.kkListSortedWithName, arguments.count == 2 {
            let receiverID = arguments[0]
            let comparatorExpr = arguments[1]
            let source = isComparatorFromCall(
                exprID: comparatorExpr,
                body: function.body,
                multiSelectorCallee: lookup.kkComparatorFromMultiSelectorsName,
                nullsFirstCallee: lookup.kkComparatorNullsFirstName,
                nullsLastCallee: lookup.kkComparatorNullsLastName,
                nullsFirstComparableCallee: lookup.kkComparatorNullsFirstComparableName,
                nullsLastNaturalCallee: lookup.kkComparatorNullsLastNaturalName,
                multiSelector3Callee: lookup.kkComparatorFromMultiSelectors3Name,
                multiSelectorVarargCallee: lookup.kkComparatorFromMultiSelectorsVarargName,
            )
            if let (trampolineName, closureExpr) = retainedComparatorRuntimePair(
                source: source,
                comparatorExpr: comparatorExpr,
                module: module,
                lookup: lookup,
                loweredBody: &loweredBody
            ) {
                let trampolineExpr = module.arena.appendExpr(.externSymbolAddress(trampolineName), type: nil)
                loweredBody.append(.constValue(result: trampolineExpr, value: .externSymbolAddress(trampolineName)))
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkListSortedWithName,
                    arguments: [receiverID, trampolineExpr, closureExpr],
                    result: result,
                    canThrow: canThrow,
                    thrownResult: thrownResult
                ))
            } else {
                let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
                loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkListSortedWithName,
                    arguments: [receiverID, comparatorExpr, zeroExpr],
                    result: result,
                    canThrow: canThrow,
                    thrownResult: thrownResult
                ))
            }
            if let result {
                state.listExprIDs.insert(result.rawValue)
            }
            return true
        }

        // --- STDLIB-189: String HOF closureRaw injection ---
        // String higher-order functions are called with args = [receiver,
        // lambdaRef]. Insert closureRaw=0 so ABI lowering only needs to append
        // the outThrown slot.
        if arguments.count == 2,
           callee == lookup.kkStringFilterName
            || callee == lookup.kkStringMapName
            || callee == lookup.kkStringCountName
            || callee == lookup.kkStringAnyName
            || callee == lookup.kkStringAllName
            || callee == lookup.kkStringNoneName
        {
            let receiverID = arguments[0]
            let lambdaID = arguments[1]
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            let isStringResult = callee == lookup.kkStringFilterName
            loweredBody.append(.call(
                symbol: nil,
                callee: callee,
                arguments: [receiverID, lambdaID, zeroExpr],
                result: result,
                canThrow: canThrow,
                thrownResult: thrownResult
            ))
            if isStringResult, let result {
                state.stringExprIDs.insert(result.rawValue)
            }
            return true
        }

        return false
    }
}
