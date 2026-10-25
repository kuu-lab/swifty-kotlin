extension CollectionVirtualCallRewriteLoweringPass {
    func rewriteRangeVirtualCall(
        callee: InternedString,
        receiver: KIRExprID,
        arguments: [KIRExprID],
        result: KIRExprID?,
        origCanThrow: Bool,
        origThrownResult: KIRExprID?,
        module: KIRModule,
        lookup: CollectionLiteralLookupTables,
        sema: SemaModule?,
        interner: StringInterner,
        state: inout CollectionRewriteState,
        loweredBody: inout KIRLoweringEmitContext
    ) -> Bool {
        guard state.contains(.range, receiver) else { return false }
        let isCharRange = state.contains(.charRange, receiver)
        let isULongRange = state.contains(.ulongRange, receiver)
        let isUIntRange = sema.map { module.arena.exprType(receiver) == $0.types.uintType } ?? false
        let isLongRange = sema.map { module.arena.exprType(receiver) == $0.types.longType } ?? false
        // Source-backed ULong members must remain ordinary Kotlin calls. This
        // pass only handles the residual ULong range construction helpers.
        if isULongRange && [
            lookup.containsName, lookup.isEmptyName, lookup.countName,
            lookup.sumName, lookup.toListName, lookup.firstOrNullName,
            lookup.lastOrNullName, lookup.averageName, lookup.sortedName,
            lookup.reversedName,
        ].contains(callee) {
            return false
        }
        // KSP-1525/1527: map/filter-family HOFs are source-backed for both
        // unsigned range types, so their rewrite arms are skipped below.
        let isUnsignedRange = isUIntRange || isULongRange
        if callee == lookup.stepName, arguments.isEmpty {
            let stepName = isULongRange ? lookup.kkULongRangeStepName : (isUIntRange ? interner.intern("__kk_uint_range_step") : lookup.kkRangeStepName)
            loweredBody.append(.call(
                callee: stepName,
                arguments: [receiver], result: result,
                canThrow: false
            ))
            return true
        }

        if callee == lookup.firstName || callee == lookup.startName, arguments.isEmpty {
            // KSP-1523: UIntRange receivers never reach this pass (their
            // constructing callee, e.g. __kk_uint_rangeTo, is not one of the
            // names PreScan checks when populating rangeExprIDs — see the
            // guard at the top of this function), so the old isUIntRange arm
            // here was unreachable independent of `isUIntRange`'s own
            // always-false type check. Confirmed by nm on a comprehensive
            // real-kklib probe covering all 13 KSP-1523 members.
            let firstName = lookup.kkRangeFirstName
            loweredBody.append(.call(
                callee: firstName,
                arguments: [receiver], result: result,
                canThrow: false
            ))
            return true
        }
        if callee == lookup.lastName || callee == lookup.endInclusiveName, arguments.isEmpty {
            // KSP-1523: see the `first`/`start` case above — same unreachable arm.
            let lastName = lookup.kkRangeLastName
            loweredBody.append(.call(
                callee: lastName,
                arguments: [receiver], result: result,
                canThrow: false
            ))
            return true
        }
        if callee == lookup.endExclusiveName, arguments.isEmpty {
            loweredBody.append(.call(
                callee: lookup.kkRangeEndExclusiveName,
                arguments: [receiver], result: result,
                canThrow: true, thrownResult: origThrownResult
            ))
            return true
        }
        if callee == lookup.countName, arguments.isEmpty {
            // KSP-1523: see the `first`/`start` case above — same unreachable arm.
            loweredBody.append(.call(
                callee: lookup.kkRangeCountName,
                arguments: [receiver], result: result,
                canThrow: false
            ))
            return true
        }
        if callee == lookup.isEmptyName, arguments.isEmpty {
            // KSP-1523: see the `first`/`start` case above — same unreachable arm.
            let isEmptyName = lookup.kkRangeIsEmptyName
            loweredBody.append(.call(
                callee: isEmptyName,
                arguments: [receiver], result: result,
                canThrow: false
            ))
            return true
        }
        if callee == lookup.sumName, arguments.isEmpty {
            // KSP-1523: see the `first`/`start` case above — same unreachable arm.
            loweredBody.append(.call(
                callee: lookup.kkRangeSumName,
                arguments: [receiver], result: result,
                canThrow: false
            ))
            return true
        }

        // contains — signed and UInt ranges share the bundled __kk_range_contains; ULong keeps its own helper
        if callee == lookup.containsName, arguments.count == 1 {
            // KSP-1523: see the `first`/`start` case above — same unreachable arm.
            let containsName = interner.intern("__kk_range_contains")
            loweredBody.append(.call(
                callee: containsName,
                arguments: [receiver, arguments[0]], result: result,
                canThrow: false
            ))
            return true
        }

        if callee == lookup.toListName, arguments.isEmpty {
            // KSP-1523: see the `first`/`start` case above — the isUIntRange
            // arm here was equally unreachable.
            let toListCallee: InternedString
            if isCharRange {
                toListCallee = lookup.kkCharRangeToListName
            } else {
                toListCallee = lookup.kkRangeToListName
            }
            loweredBody.append(.call(
                callee: toListCallee,
                arguments: [receiver], result: result,
                canThrow: false
            ))
            state.tagListResult(result)
            return true
        }

        if callee == lookup.iteratorName, arguments.isEmpty {
            loweredBody.append(.call(
                callee: lookup.kkRangeIteratorName,
                arguments: [receiver], result: result,
                canThrow: false
            ))
            return true
        }

        if callee == lookup.forEachName, arguments.count == 1 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            let forEachCallee = isCharRange ? lookup.kkCharRangeForEachName
                : (isUIntRange ? interner.intern("__kk_uint_range_forEach") : lookup.kkRangeForEachName)
            _ = emitHOFCall(
                kkName: forEachCallee, receiver: receiver,
                arguments: arguments + [zeroExpr],
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, module: module,
                loweredBody: &loweredBody
            )
            return true
        }

        if callee == lookup.mapName, arguments.count == 1, !isUnsignedRange {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            let hofResult = emitHOFCall(
                kkName: lookup.kkRangeMapName,
                receiver: receiver,
                arguments: arguments + [zeroExpr],
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, module: module,
                loweredBody: &loweredBody
            )
            state.insert(.list, hofResult)
            state.tagListResult(result)
            return true
        }

        if callee == lookup.mapIndexedName, arguments.count == 1, !isUnsignedRange {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            let hofResult = emitHOFCall(
                kkName: lookup.kkRangeMapIndexedName,
                receiver: receiver,
                arguments: arguments + [zeroExpr],
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, module: module,
                loweredBody: &loweredBody
            )
            state.insert(.list, hofResult)
            state.tagListResult(result)
            return true
        }
        if callee == lookup.mapNotNullName, arguments.count == 1, !isUnsignedRange {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            let hofResult = emitHOFCall(
                kkName: lookup.kkRangeMapNotNullName,
                receiver: receiver,
                arguments: arguments + [zeroExpr],
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, module: module,
                loweredBody: &loweredBody
            )
            state.insert(.list, hofResult)
            state.tagListResult(result)
            return true
        }
        if callee == lookup.filterName, arguments.count == 1, !isUnsignedRange {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            let hofResult = emitHOFCall(
                kkName: lookup.kkRangeFilterName,
                receiver: receiver,
                arguments: arguments + [zeroExpr],
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, module: module,
                loweredBody: &loweredBody
            )
            state.insert(.list, hofResult)
            state.tagListResult(result)
            return true
        }
        if callee == lookup.filterIndexedName, arguments.count == 1, !isUnsignedRange {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            let hofResult = emitHOFCall(
                kkName: lookup.kkRangeFilterIndexedName,
                receiver: receiver,
                arguments: arguments + [zeroExpr],
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, module: module,
                loweredBody: &loweredBody
            )
            state.insert(.list, hofResult)
            state.tagListResult(result)
            return true
        }
        if callee == lookup.filterNotName, arguments.count == 1, !isUnsignedRange {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            let hofResult = emitHOFCall(
                kkName: lookup.kkRangeFilterNotName,
                receiver: receiver,
                arguments: arguments + [zeroExpr],
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, module: module,
                loweredBody: &loweredBody
            )
            state.insert(.list, hofResult)
            state.tagListResult(result)
            return true
        }
        if callee == lookup.reduceName, arguments.count == 1 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            _ = emitHOFCall(
                kkName: isUIntRange ? interner.intern("__kk_uint_range_reduce") : lookup.kkRangeReduceName,
                receiver: receiver,
                arguments: arguments + [zeroExpr],
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, module: module,
                loweredBody: &loweredBody
            )
            return true
        }
        if callee == lookup.reduceIndexedName, arguments.count == 1 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            _ = emitHOFCall(
                kkName: isUIntRange ? interner.intern("__kk_uint_range_reduceIndexed") : lookup.kkRangeReduceIndexedName,
                receiver: receiver,
                arguments: arguments + [zeroExpr],
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, module: module,
                loweredBody: &loweredBody
            )
            return true
        }
        if callee == lookup.foldName, arguments.count == 2 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            _ = emitHOFCall(
                kkName: isUIntRange ? interner.intern("__kk_uint_range_fold") : lookup.kkRangeFoldName,
                receiver: receiver,
                arguments: arguments + [zeroExpr],
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, module: module,
                loweredBody: &loweredBody
            )
            return true
        }
        if callee == lookup.foldIndexedName, arguments.count == 2 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            _ = emitHOFCall(
                kkName: isUIntRange ? interner.intern("__kk_uint_range_foldIndexed") : lookup.kkRangeFoldIndexedName,
                receiver: receiver,
                arguments: arguments + [zeroExpr],
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, module: module,
                loweredBody: &loweredBody
            )
            return true
        }
        if callee == lookup.findName, arguments.count == 1 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            _ = emitHOFCall(
                kkName: isUIntRange ? interner.intern("__kk_uint_range_find") : lookup.kkRangeFindName,
                receiver: receiver,
                arguments: arguments + [zeroExpr],
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, module: module,
                loweredBody: &loweredBody
            )
            return true
        }
        if callee == lookup.findLastName, arguments.count == 1 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            _ = emitHOFCall(
                kkName: isUIntRange ? interner.intern("__kk_uint_range_findLast") : lookup.kkRangeFindLastName,
                receiver: receiver,
                arguments: arguments + [zeroExpr],
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, module: module,
                loweredBody: &loweredBody
            )
            return true
        }
        if callee == lookup.firstName, arguments.count == 1 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            _ = emitHOFCall(
                kkName: isUIntRange ? interner.intern("__kk_uint_range_first_predicate") : lookup.kkRangeFirstPredicateName,
                receiver: receiver,
                arguments: arguments + [zeroExpr],
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, module: module,
                loweredBody: &loweredBody
            )
            return true
        }
        if callee == lookup.firstOrNullName, arguments.isEmpty {
            // KSP-1523: the isUIntRange arm here was unreachable for the same
            // structural reason as the other members above (see `first`/`start`).
            let firstOrNullName = interner.intern("__kk_range_firstOrNull")
            loweredBody.append(.call(
                callee: firstOrNullName,
                arguments: [receiver], result: result,
                canThrow: false
            ))
            return true
        }
        if callee == lookup.firstOrNullName, arguments.count == 1 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            _ = emitHOFCall(
                kkName: isUIntRange ? interner.intern("__kk_uint_range_firstOrNull_predicate") : lookup.kkRangeFirstOrNullPredicateName,
                receiver: receiver,
                arguments: arguments + [zeroExpr],
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, module: module,
                loweredBody: &loweredBody
            )
            return true
        }
        if callee == lookup.lastName, arguments.count == 1 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            _ = emitHOFCall(
                kkName: isUIntRange ? interner.intern("__kk_uint_range_last_predicate") : lookup.kkRangeLastPredicateName,
                receiver: receiver,
                arguments: arguments + [zeroExpr],
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, module: module,
                loweredBody: &loweredBody
            )
            return true
        }
        if callee == lookup.lastOrNullName, arguments.isEmpty {
            // KSP-1523: the isUIntRange arm here was unreachable for the same
            // structural reason as the other members above (see `first`/`start`).
            let lastOrNullName = interner.intern("__kk_range_lastOrNull")
            loweredBody.append(.call(
                callee: lastOrNullName,
                arguments: [receiver], result: result,
                canThrow: false
            ))
            return true
        }
        if callee == lookup.lastOrNullName, arguments.count == 1 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            _ = emitHOFCall(
                kkName: isUIntRange ? interner.intern("__kk_uint_range_lastOrNull_predicate") : lookup.kkRangeLastOrNullPredicateName,
                receiver: receiver,
                arguments: arguments + [zeroExpr],
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, module: module,
                loweredBody: &loweredBody
            )
            return true
        }
        if callee == lookup.anyName || callee == lookup.allName || callee == lookup.noneName, arguments.count == 1 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            let kkName: InternedString =
                callee == lookup.anyName ? (isUIntRange ? interner.intern("__kk_uint_range_any") : lookup.kkRangeAnyName)
                    : callee == lookup.allName ? (isUIntRange ? interner.intern("__kk_uint_range_all") : lookup.kkRangeAllName)
                    : (isUIntRange ? interner.intern("__kk_uint_range_none") : lookup.kkRangeNoneName)
            _ = emitHOFCall(
                kkName: kkName, receiver: receiver,
                arguments: arguments + [zeroExpr],
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, module: module,
                loweredBody: &loweredBody
            )
            return true
        }
        if callee == lookup.chunkedName, arguments.count == 1 {
            loweredBody.append(.call(
                callee: isULongRange ? interner.intern("__kk_ulong_range_chunked")
                    : (isUIntRange ? interner.intern("__kk_uint_range_chunked") : lookup.kkRangeChunkedName),
                arguments: [receiver] + arguments, result: result,
                canThrow: true, thrownResult: origThrownResult
            ))
            state.tagListResult(result)
            return true
        }
        if callee == lookup.windowedName, arguments.count == 3 {
            loweredBody.append(.call(
                callee: isULongRange ? interner.intern("__kk_ulong_range_windowed")
                    : (isUIntRange ? interner.intern("__kk_uint_range_windowed") : lookup.kkRangeWindowedName),
                arguments: [receiver] + arguments, result: result,
                canThrow: true, thrownResult: origThrownResult
            ))
            state.tagListResult(result)
            return true
        }

        if callee == lookup.takeName, arguments.count == 1 {
            let takeName: InternedString
            if isULongRange {
                takeName = interner.intern("__kk_ulong_range_take")
            } else if isUIntRange {
                takeName = interner.intern("__kk_uint_range_take")
            } else if isLongRange {
                takeName = interner.intern("__kk_long_range_take")
            } else if isCharRange {
                takeName = interner.intern("__kk_char_range_take")
            } else {
                takeName = lookup.kkRangeTakeName
            }
            loweredBody.append(.call(callee: takeName,
                arguments: [receiver] + arguments, result: result, canThrow: true, thrownResult: origThrownResult))
            state.tagListResult(result)
            return true
        }
        if callee == lookup.dropName, arguments.count == 1 {
            let dropName: InternedString
            if isULongRange {
                dropName = interner.intern("__kk_ulong_range_drop")
            } else if isUIntRange {
                dropName = interner.intern("__kk_uint_range_drop")
            } else if isLongRange {
                dropName = interner.intern("__kk_long_range_drop")
            } else if isCharRange {
                dropName = interner.intern("__kk_char_range_drop")
            } else {
                dropName = lookup.kkRangeDropName
            }
            loweredBody.append(.call(callee: dropName,
                arguments: [receiver] + arguments, result: result, canThrow: true, thrownResult: origThrownResult))
            state.tagListResult(result)
            return true
        }
        if callee == lookup.averageName, arguments.isEmpty {
            // KSP-1523: the isUIntRange arm here was unreachable for the same
            // structural reason as the other members above (see `first`/`start`).
            let averageName: InternedString
            if isLongRange {
                averageName = interner.intern("__kk_long_range_average")
            } else {
                averageName = lookup.kkRangeAverageName
            }
            loweredBody.append(.call(callee: averageName,
                arguments: [receiver], result: result, canThrow: false))
            return true
        }
        if callee == lookup.sortedName, arguments.isEmpty {
            // KSP-1523: the isUIntRange arm here was unreachable for the same
            // structural reason as the other members above (see `first`/`start`).
            let sortedName: InternedString
            if isLongRange {
                sortedName = interner.intern("__kk_long_range_sorted")
            } else if isCharRange {
                sortedName = interner.intern("__kk_char_range_sorted")
            } else {
                sortedName = lookup.kkRangeSortedName
            }
            loweredBody.append(.call(callee: sortedName,
                arguments: [receiver], result: result, canThrow: false))
            state.tagListResult(result)
            return true
        }

        if callee == lookup.reversedName, arguments.isEmpty {
            // KSP-1523: the isUIntRange arm here was unreachable for the same
            // structural reason as the other members above (see `first`/`start`).
            let reversedName = lookup.kkRangeReversedName
            loweredBody.append(.call(
                callee: reversedName,
                arguments: [receiver], result: result,
                canThrow: false
            ))
            if let result {
                state.insert(.range, result)
                if isCharRange { state.insert(.charRange, result) }
                if isULongRange { state.insert(.ulongRange, result) }
            }
            return true
        }

        return false
    }
}
