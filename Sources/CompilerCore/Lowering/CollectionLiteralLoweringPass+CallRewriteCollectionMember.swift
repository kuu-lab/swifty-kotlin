
extension CollectionLiteralConstructionLoweringPass {

    /// Rewrites simple collection member calls that do not require closure ABI expansion.
    func rewriteCollectionMemberCall(
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
        // --- Rewrite collection member calls ---
        // Range first()/last()/endExclusive do not use the Kotlin stdlib source and
        // continue to go through their runtime helpers.
        if callee == lookup.firstName || callee == lookup.lastName
            || callee == lookup.endExclusiveName
        {
            if arguments.count == 1 {
                let receiverID = arguments[0]
                if state.rangeExprIDs.contains(receiverID.rawValue),
                   callee == lookup.firstName || callee == lookup.lastName || callee == lookup.endExclusiveName
                {
                    let kkName: InternedString = switch callee {
                    case lookup.firstName: lookup.kkRangeFirstName
                    case lookup.lastName: lookup.kkRangeLastName
                    case lookup.endExclusiveName: lookup.kkRangeEndExclusiveName
                    default: callee
                    }
                    loweredBody.append(.call(
                        symbol: nil,
                        callee: kkName,
                        arguments: [receiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return true
                }
            }
        }

        if callee == lookup.sizeName || callee == lookup.countName {
            if arguments.count == 1 {
                let receiverID = arguments[0]
                if state.listExprIDs.contains(receiverID.rawValue) {
                    loweredBody.append(.call(
                        symbol: nil,
                        callee: lookup.kkListSizeName,
                        arguments: [receiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return true
                }
                if state.mapExprIDs.contains(receiverID.rawValue) {
                    loweredBody.append(.call(
                        symbol: nil,
                        callee: lookup.kkMapSizeName,
                        arguments: [receiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return true
                }
                if state.setExprIDs.contains(receiverID.rawValue) {
                    loweredBody.append(.call(
                        symbol: nil,
                        callee: lookup.kkSetSizeName,
                        arguments: [receiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return true
                }
                if state.arrayExprIDs.contains(receiverID.rawValue) {
                    loweredBody.append(.call(
                        symbol: nil,
                        callee: lookup.kkArraySizeName,
                        arguments: [receiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return true
                }
                if state.rangeExprIDs.contains(receiverID.rawValue) {
                    if state.ulongRangeExprIDs.contains(receiverID.rawValue) {
                        // ULongRange.count() is bundled Kotlin source.
                        return false
                    }
                    // KSP-1523: UIntRange never reaches this branch — its
                    // constructing callee (e.g. __kk_uint_rangeTo) is never
                    // added to state.rangeExprIDs during PreScan, so the old
                    // isUIntRangeExpr arm was unreachable regardless of that
                    // local helper's own always-false type comparison.
                    loweredBody.append(.call(
                        symbol: nil,
                        callee: lookup.kkRangeCountName,
                        arguments: [receiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return true
                }
            }
        }

        if callee == lookup.getName {
            if arguments.count == 2 {
                let receiverID = arguments[0]
                if state.listExprIDs.contains(receiverID.rawValue) {
                    loweredBody.append(.call(
                        symbol: nil,
                        callee: lookup.kkListGetName,
                        arguments: arguments,
                        result: result,
                        canThrow: canThrow,
                        thrownResult: thrownResult
                    ))
                    return true
                }
                if state.mapExprIDs.contains(receiverID.rawValue) {
                    loweredBody.append(.call(
                        symbol: nil,
                        callee: lookup.kkMapGetName,
                        arguments: arguments,
                        result: result,
                        canThrow: canThrow,
                        thrownResult: thrownResult
                    ))
                    return true
                }
            }
        }

        if callee == lookup.containsName {
            if arguments.count == 2 {
                let receiverID = arguments[0]
                if state.setExprIDs.contains(receiverID.rawValue) {
                    loweredBody.append(.call(
                        symbol: nil,
                        callee: lookup.kkSetContainsName,
                        arguments: arguments,
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return true
                }
            }
        }

        if callee == lookup.addName {
            if arguments.count == 2 {
                let receiverID = arguments[0]
                if state.setExprIDs.contains(receiverID.rawValue) {
                    loweredBody.append(.call(
                        symbol: nil,
                        callee: lookup.kkMutableSetAddName,
                        arguments: arguments,
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return true
                }
            }
        }

        if callee == lookup.removeName {
            if arguments.count == 2 {
                let receiverID = arguments[0]
                if state.setExprIDs.contains(receiverID.rawValue) {
                    loweredBody.append(.call(
                        symbol: nil,
                        callee: lookup.kkMutableSetRemoveName,
                        arguments: arguments,
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return true
                }
            }
        }

        if callee == lookup.isEmptyName {
            if arguments.count == 1 {
                let receiverID = arguments[0]
                if state.listExprIDs.contains(receiverID.rawValue) {
                    loweredBody.append(.call(
                        symbol: nil,
                        callee: lookup.kkListIsEmptyName,
                        arguments: [receiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return true
                }
                if state.setExprIDs.contains(receiverID.rawValue) {
                    loweredBody.append(.call(
                        symbol: nil,
                        callee: lookup.kkSetIsEmptyName,
                        arguments: [receiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return true
                }
                if state.mapExprIDs.contains(receiverID.rawValue) {
                    loweredBody.append(.call(
                        symbol: nil,
                        callee: lookup.kkMapIsEmptyName,
                        arguments: [receiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return true
                }
                // STDLIB-637: UIntRange/ULongRange isEmpty
                if state.rangeExprIDs.contains(receiverID.rawValue) {
                    if state.ulongRangeExprIDs.contains(receiverID.rawValue) {
                        // ULongRange.isEmpty() is bundled Kotlin source.
                        return false
                    }
                    // KSP-1523: see the count() branch above — same unreachable arm.
                    loweredBody.append(.call(
                        symbol: nil,
                        callee: lookup.kkRangeIsEmptyName,
                        arguments: [receiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return true
                }
            }
        }

        // STDLIB-637: range/list sum()
        if callee == lookup.sumName {
            if arguments.count == 1 {
                let receiverID = arguments[0]
                if state.rangeExprIDs.contains(receiverID.rawValue) {
                    if state.ulongRangeExprIDs.contains(receiverID.rawValue) {
                        // ULongRange.sum() is bundled Kotlin source.
                        return false
                    }
                    // KSP-1523: see the count() branch above — same unreachable arm.
                    loweredBody.append(.call(
                        symbol: nil,
                        callee: lookup.kkRangeSumName,
                        arguments: [receiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return true
                }
            }
        }

        return false
    }
}
