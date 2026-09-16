/// Core one-lambda higher-order collection rewrites.
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
    // --- Rewrite higher-order collection member calls (FUNC-003) ---
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
                    symbol: nil,
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
            // RF-LOWER-CALL-012 dropped the Map-receiver branch that used to sit
            // here (`map` / `filter` / `forEach` / `mapValues` / `mapKeys` /
            // `filterKeys` / `filterValues` / `flatMap` / `any` / `all` /
            // `none` / `maxByOrNull` / `minByOrNull` rewritten to `kk_map_*`).
            // It was unreachable: every one of those names resolves to the
            // bundled `MapHOF.kt` declaration (KSP-430) and is preserved by
            // the source-backed preservation gate before
            // `rewriteHigherOrderCollectionCall` runs, and `filterKeys` /
            // `filterValues` / `maxByOrNull` / `minByOrNull` additionally never
            // passed this function's own outer member-name gate above (it
            // never listed them). `kk_map_map`, `kk_map_filter`,
            // `kk_map_mapValues`, `kk_map_mapKeys`, `kk_map_filterKeys`,
            // `kk_map_filterValues`, `kk_map_flatMap`, `kk_map_any`,
            // `kk_map_all`, `kk_map_none`, `kk_map_forEach`,
            // `kk_map_maxByOrNull`, `kk_map_minByOrNull` have no `@_cdecl` in
            // `Sources/Runtime` any more. See `+CallRewriteHandlers.swift` and
            // `MapHOFLoweringRoutingTests` for the full picture.
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
                let isULongRange = state.ulongRangeExprIDs.contains(receiverID.rawValue)
                let kkName: InternedString
                if callee == lookup.mapName {
                    // STDLIB-RANGE-037: use ULong-specific map for unsigned ranges
                    kkName = isULongRange ? lookup.kkULongRangeMapName : lookup.kkRangeMapName
                } else {
                    // forEach: source-backed for ULongRange since KSP-1528; use char
                    // or default range variant otherwise.
                    kkName = isCharRange ? lookup.kkCharRangeForEachName : lookup.kkRangeForEachName
                }
                let hofResult = module.arena.appendTemporary(type: nil
                )
                loweredBody.append(.call(
                    symbol: nil,
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
            // KSP-432: Set higher-order functions are source-backed in
            // Stdlib/kotlin/collections/SetHOF.kt, so set receivers intentionally
            // fall through to normal call lowering here.
        }
    }

        return false
    }
}
