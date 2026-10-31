extension CollectionLiteralConstructionLoweringPass {
    func rewriteSequenceTerminalCall(
        symbol: SymbolID?,
        callee: InternedString,
        arguments: [KIRExprID],
        result: KIRExprID?,
        canThrow: Bool,
        thrownResult: KIRExprID?,
        module: KIRModule,
        ctx: KIRContext,
        lookup: CollectionLiteralLookupTables,
        state: inout CollectionRewriteState,
        loweredBody: inout KIRLoweringEmitContext
    ) -> Bool {
        // STDLIB-pipeline §5 / KSP-441〜447: Bundled Kotlin source implementations
        // (e.g. flatten, toSet) take priority over runtime shortcuts. Only a
        // confirmed RuntimeSequenceBox may use the `kk_*` helper; source objects,
        // non-Sequence receivers, and unknown provenance stay on the source
        // iterator path.
        if isSourceBacked(symbol: symbol, ctx: ctx),
           let receiverID = arguments.first,
           state.sequenceRuntimeRepresentation(of: receiverID) != .runtimeBox {
            return false
        }
        // KUU-3850: the bundled `first`/`last`/`count`/`firstOrNull`/`lastOrNull`
        // Sequence extensions drive every element through `kk_iterator_*`
        // dispatch under a generated GC frame. On a confirmed RuntimeSequenceBox
        // the direct traversal keeps the same semantics — including
        // NoSuchElementException on `first`/`last` over an empty sequence and
        // producer exceptions via outThrown — without the per-element dispatch.
        //
        // kklib-imported stdlib callees arrive as `kk_fn_*` link names, so the
        // resolved `kotlin.sequences`/`kotlin.collections` declaration (the
        // bundled stdlib declares `Sequence.count` in `kotlin.collections`) is
        // matched as well as the plain callee name.
        let sequenceDeclName = sequenceExtensionSimpleName(
            symbol: symbol,
            sema: ctx.sema,
            interner: ctx.interner
        )
        func matchesTerminal(_ name: InternedString) -> Bool {
            sequenceDeclName == name || (symbol == nil && callee == name)
        }
        if matchesTerminal(lookup.firstName) || matchesTerminal(lookup.firstOrNullName)
            || matchesTerminal(lookup.lastName) || matchesTerminal(lookup.lastOrNullName)
            || matchesTerminal(lookup.countName),
           arguments.count == 1
        {
            let receiverID = arguments[0]
            if state.sequenceRuntimeRepresentation(of: receiverID) == .runtimeBox {
                let kkName: InternedString
                if matchesTerminal(lookup.firstName) {
                    kkName = lookup.kkSequenceFirstName
                } else if matchesTerminal(lookup.firstOrNullName) {
                    kkName = lookup.kkSequenceFirstOrNullName
                } else if matchesTerminal(lookup.lastName) {
                    kkName = lookup.kkSequenceLastName
                } else if matchesTerminal(lookup.lastOrNullName) {
                    kkName = lookup.kkSequenceLastOrNullName
                } else {
                    kkName = lookup.kkSequenceCountName
                }
                loweredBody.append(.call(
                    callee: kkName,
                    arguments: [receiverID],
                    result: result,
                    canThrow: true,
                    thrownResult: thrownResult
                ))
                return true
            }
        }

    if callee == lookup.toSetName, arguments.count == 1 {
        let receiverID = arguments[0]
        if state.sequenceExprIDs.contains(receiverID.rawValue) {
            appendCallWithTrackedResult(
                callee: lookup.kkSequenceToSetName,
                arguments: [receiverID],
                result: result,
                canThrow: false,
                thrownResult: nil,
                trackedAs: .set,
                module: module,
                state: &state,
                loweredBody: &loweredBody
            )
            return true
        }
    }

    if callee == lookup.toMapName, arguments.count == 1 {
        let receiverID = arguments[0]
        if state.sequenceExprIDs.contains(receiverID.rawValue) {
            let thrownExpr = thrownResult ?? module.arena.appendTemporary(type: nil)
            appendCallWithTrackedResult(
                callee: lookup.kkSequenceToMapName,
                arguments: [receiverID],
                result: result,
                canThrow: true,
                thrownResult: thrownExpr,
                trackedAs: .map,
                module: module,
                state: &state,
                loweredBody: &loweredBody
            )
            return true
        }
    }

    if callee == lookup.maxName || callee == lookup.maxOrNullName || callee == lookup.minOrNullName {
        if arguments.count == 1 {
            let receiverID = arguments[0]
            if state.sequenceExprIDs.contains(receiverID.rawValue) {
                let kkName: InternedString
                if callee == lookup.maxName {
                    kkName = lookup.kkSequenceMaxName
                } else {
                    kkName = callee == lookup.maxOrNullName
                        ? lookup.kkSequenceMaxOrNullName
                        : lookup.kkSequenceMinOrNullName
                }
                let hofResult = module.arena.appendTemporary(type: nil
                )
                loweredBody.append(.call(callee: kkName, arguments: [receiverID], result: hofResult, canThrow: canThrow, thrownResult: thrownResult))
                if let result {
                    loweredBody.append(.copy(from: hofResult, to: result))
                }
                return true
            }
        }
    }

    if callee == lookup.flattenName, arguments.count == 1 {
        let receiverID = arguments[0]
        if state.sequenceExprIDs.contains(receiverID.rawValue) {
            loweredBody.append(.call(callee: lookup.kkSequenceFlattenName, arguments: [receiverID], result: result, canThrow: false))
            if let result { state.sequenceExprIDs.insert(result.rawValue) }
            return true
        }
    }

    if callee == lookup.reversedName || callee == lookup.asReversedName, arguments.count == 1 {
        let receiverID = arguments[0]
        if callee == lookup.reversedName, state.rangeExprIDs.contains(receiverID.rawValue) {
            if state.ulongRangeExprIDs.contains(receiverID.rawValue) {
                // ULongRange.reversed() is bundled Kotlin source.
                return false
            }
            // KSP-1523: UIntRange never reaches this branch — its
            // constructing callee is never added to state.rangeExprIDs
            // during PreScan, so the old isUIntRange arm was unreachable.
            let transformResult = module.arena.appendTemporary(type: nil
            )
            let reversedName = lookup.kkRangeReversedName
            loweredBody.append(.call(callee: reversedName, arguments: [receiverID], result: transformResult, canThrow: false))
            if let result {
                state.rangeExprIDs.insert(result.rawValue)
                state.rangeExprIDs.insert(transformResult.rawValue)
                if state.ulongRangeExprIDs.contains(receiverID.rawValue) {
                    state.ulongRangeExprIDs.insert(transformResult.rawValue)
                    state.ulongRangeExprIDs.insert(result.rawValue)
                }
                loweredBody.append(.copy(from: transformResult, to: result))
            }
            return true
        }
    }

    if callee == lookup.toListName, arguments.count == 1 {
        let receiverID = arguments[0]
        if state.sequenceExprIDs.contains(receiverID.rawValue),
           !state.arrayExprIDs.contains(receiverID.rawValue)
        {
            appendCallWithTrackedResult(
                callee: lookup.kkSequenceToListName,
                arguments: [receiverID],
                result: result,
                canThrow: true,
                thrownResult: nil,
                trackedAs: .list,
                module: module,
                state: &state,
                loweredBody: &loweredBody
            )
            return true
        }
        if state.arrayExprIDs.contains(receiverID.rawValue) {
            appendCallWithTrackedResult(
                callee: lookup.kkArrayToListName,
                arguments: [receiverID],
                result: result,
                canThrow: false,
                thrownResult: nil,
                trackedAs: .list,
                module: module,
                state: &state,
                loweredBody: &loweredBody
            )
            return true
        }
        if state.rangeExprIDs.contains(receiverID.rawValue) {
            if state.ulongRangeExprIDs.contains(receiverID.rawValue) {
                // ULongRange.toList() is bundled Kotlin source.
                return false
            }
            let toListResult = module.arena.appendTemporary(type: nil
            )
            // KSP-1523/1524: unsigned range toList() is bundled Kotlin source.
            let rangeToListCallee: InternedString
            if state.charRangeExprIDs.contains(receiverID.rawValue) {
                rangeToListCallee = lookup.kkCharRangeToListName
            } else {
                rangeToListCallee = lookup.kkRangeToListName
            }
            loweredBody.append(.call(callee: rangeToListCallee, arguments: [receiverID], result: toListResult, canThrow: false))
            if let result {
                state.listExprIDs.insert(result.rawValue)
                state.listExprIDs.insert(toListResult.rawValue)
                loweredBody.append(.copy(from: toListResult, to: result))
            }
            return true
        }
    }

        return false
    }
}
