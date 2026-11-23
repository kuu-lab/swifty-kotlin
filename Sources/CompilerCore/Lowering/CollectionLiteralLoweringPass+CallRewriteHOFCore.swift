extension CollectionLiteralConstructionLoweringPass {
    func rewriteCoreHigherOrderCollectionCall(
        callee: InternedString,
        arguments: [KIRExprID],
        result: KIRExprID?,
        canThrow: Bool,
        thrownResult: KIRExprID?,
        module: KIRModule,
        lookup: CollectionLiteralLookupTables,
        state: inout CollectionRewriteState,
        loweredBody: inout KIRLoweringEmitContext
    ) -> Bool {
    if callee == lookup.mapName || callee == lookup.filterName || callee == lookup.filterNotName || callee == lookup.mapNotNullName || callee == lookup.forEachName || callee == lookup.onEachName
        || callee == lookup.flatMapName || callee == lookup.flatMapIndexedName || callee == lookup.anyName || callee == lookup.noneName
        || callee == lookup.allName || callee == lookup.mapValuesName || callee == lookup.mapKeysName
        || callee == lookup.toListName
    {
        if let rewrite = rewriteCollectionHOFCall(
            call: .init(
                callee: callee,
                arguments: arguments,
                result: result,
                canThrow: canThrow,
                thrownResult: thrownResult
            ),
            state: &state,
            ctx: .init(module: module, lookup: lookup)
        ) {
            loweredBody.append(contentsOf: rewrite.instructions)
            return true
        }

        if arguments.count == 2 || arguments.count == 3 {
            let receiverID = arguments[0]
            let lambdaID = arguments[1]
            if let kkName = lookup.collectionHOFRuntimeName(ownerKind: .list, callee: callee, arity: 1),
               state.listExprIDs.contains(receiverID.rawValue),
               callee != lookup.filterName,
               callee != lookup.filterNotName
            {
                let closureRawID: KIRExprID
                if arguments.count == 3 {
                    closureRawID = arguments[2]
                } else {
                    let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
                    loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                    closureRawID = zeroExpr
                }
                let needsListTag = callee == lookup.mapName
                    || callee == lookup.mapNotNullName
                    || callee == lookup.flatMapName
                    || callee == lookup.flatMapIndexedName
                    || callee == lookup.onEachName
                let hofResult = module.arena.appendTemporary(type: nil
                )
                loweredBody.append(.call(
                    callee: kkName,
                    arguments: [receiverID, lambdaID, closureRawID],
                    result: hofResult,
                    canThrow: canThrow,
                    thrownResult: thrownResult
                ))
                if needsListTag, let result {
                    state.listExprIDs.insert(result.rawValue)
                    state.listExprIDs.insert(hofResult.rawValue)
                }
                if let result {
                    loweredBody.append(.copy(from: hofResult, to: result))
                }
                return true
            }
            if state.rangeExprIDs.contains(receiverID.rawValue),
               callee == lookup.mapName || callee == lookup.forEachName
            {
                let closureRawID: KIRExprID
                if arguments.count == 3 {
                    closureRawID = arguments[2]
                } else {
                    let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
                    loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                    closureRawID = zeroExpr
                }
                let isCharRange = state.charRangeExprIDs.contains(receiverID.rawValue)
                let kkName: InternedString
                if callee == lookup.mapName {
                    kkName = lookup.kkRangeMapName
                } else {
                    kkName = isCharRange ? lookup.kkCharRangeForEachName : lookup.kkRangeForEachName
                }
                let hofResult = module.arena.appendTemporary(type: nil
                )
                loweredBody.append(.call(
                    callee: kkName,
                    arguments: [receiverID, lambdaID, closureRawID],
                    result: hofResult,
                    canThrow: canThrow,
                    thrownResult: thrownResult
                ))
                if callee == lookup.mapName, let result {
                    state.listExprIDs.insert(result.rawValue)
                    state.listExprIDs.insert(hofResult.rawValue)
                }
                if let result {
                    loweredBody.append(.copy(from: hofResult, to: result))
                }
                return true
            }
        }
    }

        return false
    }
}
