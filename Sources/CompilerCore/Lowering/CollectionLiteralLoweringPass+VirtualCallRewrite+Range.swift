/// Virtual-call rewrite for `IntRange` / `LongRange` / `CharRange` /
/// `UIntRange` / `ULongRange` receivers (STDLIB-090/091/092/093).
///
/// Split out from `CollectionLiteralLoweringPass+VirtualCallRewrite.swift`.
extension CollectionVirtualCallRewriteLoweringPass {
    // MARK: - IntRange operations (STDLIB-090/091/092/093)

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
        // KSP-1525/1527: map/filter-family HOFs are source-backed for both
        // unsigned range types, so their rewrite arms are skipped below.
        let isUnsignedRange = isUIntRange || isULongRange
        // step — simple property access (STDLIB-RANGE-037)
        if callee == lookup.stepName, arguments.isEmpty {
            let stepName = isULongRange ? lookup.kkULongRangeStepName : (isUIntRange ? interner.intern("kk_uint_range_step") : lookup.kkRangeStepName)
            loweredBody.append(.call(
                symbol: nil, callee: stepName,
                arguments: [receiver], result: result,
                canThrow: false, thrownResult: nil
            ))
            return true
        }

        // first / last / start / endInclusive / endExclusive / count — simple property access (STDLIB-092 / STDLIB-RANGE-034)
        if callee == lookup.firstName || callee == lookup.startName, arguments.isEmpty {
            // KSP-1523: UIntRange receivers never reach this pass (their
            // constructing callee, e.g. __kk_uint_rangeTo, is not one of the
            // names PreScan checks when populating rangeExprIDs — see the
            // guard at the top of this function), so the old isUIntRange arm
            // here was unreachable independent of `isUIntRange`'s own
            // always-false type check. Confirmed by nm on a comprehensive
            // real-kklib probe covering all 13 KSP-1523 members.
            let firstName = isULongRange ? lookup.kkULongRangeFirstName : lookup.kkRangeFirstName
            loweredBody.append(.call(
                symbol: nil, callee: firstName,
                arguments: [receiver], result: result,
                canThrow: false, thrownResult: nil
            ))
            return true
        }
        if callee == lookup.lastName || callee == lookup.endInclusiveName, arguments.isEmpty {
            // KSP-1523: see the `first`/`start` case above — same unreachable arm.
            let lastName = isULongRange ? lookup.kkULongRangeLastName : lookup.kkRangeLastName
            loweredBody.append(.call(
                symbol: nil, callee: lastName,
                arguments: [receiver], result: result,
                canThrow: false, thrownResult: nil
            ))
            return true
        }
        if callee == lookup.endExclusiveName, arguments.isEmpty {
            loweredBody.append(.call(
                symbol: nil, callee: lookup.kkRangeEndExclusiveName,
                arguments: [receiver], result: result,
                canThrow: false, thrownResult: nil
            ))
            return true
        }
        if callee == lookup.countName, arguments.isEmpty {
            // KSP-1523: see the `first`/`start` case above — same unreachable arm.
            loweredBody.append(.call(
                symbol: nil, callee: lookup.kkRangeCountName,
                arguments: [receiver], result: result,
                canThrow: false, thrownResult: nil
            ))
            return true
        }
        // STDLIB-637: isEmpty / sum
        if callee == lookup.isEmptyName, arguments.isEmpty {
            // KSP-1523: see the `first`/`start` case above — same unreachable arm.
            let isEmptyName = isULongRange ? lookup.kkULongRangeIsEmptyName : lookup.kkRangeIsEmptyName
            loweredBody.append(.call(
                symbol: nil, callee: isEmptyName,
                arguments: [receiver], result: result,
                canThrow: false, thrownResult: nil
            ))
            return true
        }
        if callee == lookup.sumName, arguments.isEmpty {
            // KSP-1523: see the `first`/`start` case above — same unreachable arm.
            loweredBody.append(.call(
                symbol: nil, callee: lookup.kkRangeSumName,
                arguments: [receiver], result: result,
                canThrow: false, thrownResult: nil
            ))
            return true
        }

        // contains — signed and UInt ranges share the bundled __kk_range_contains; ULong keeps its own helper
        if callee == lookup.containsName, arguments.count == 1 {
            // KSP-1523: see the `first`/`start` case above — same unreachable arm.
            let containsName = isULongRange ? lookup.kkULongRangeContainsName : interner.intern("__kk_range_contains")
            loweredBody.append(.call(
                symbol: nil, callee: containsName,
                arguments: [receiver, arguments[0]], result: result,
                canThrow: false, thrownResult: nil
            ))
            return true
        }

        // toList — returns a List (STDLIB-091 / STDLIB-290 / STDLIB-524)
        if callee == lookup.toListName, arguments.isEmpty {
            // KSP-1523: see the `first`/`start` case above — the isUIntRange
            // arm here was equally unreachable.
            let toListCallee: InternedString
            if isCharRange {
                toListCallee = lookup.kkCharRangeToListName
            } else if isULongRange {
                toListCallee = lookup.kkULongRangeToListName
            } else {
                toListCallee = lookup.kkRangeToListName
            }
            loweredBody.append(.call(
                symbol: nil, callee: toListCallee,
                arguments: [receiver], result: result,
                canThrow: false, thrownResult: nil
            ))
            state.tagListResult(result)
            return true
        }

        if callee == lookup.iteratorName, arguments.isEmpty {
            loweredBody.append(.call(
                symbol: nil, callee: lookup.kkRangeIteratorName,
                arguments: [receiver], result: result,
                canThrow: false, thrownResult: nil
            ))
            return true
        }

        // forEach — HOF (STDLIB-091 / STDLIB-290)
        if callee == lookup.forEachName, arguments.count == 1 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            let forEachCallee = isCharRange ? lookup.kkCharRangeForEachName
                : (isUIntRange ? interner.intern("kk_uint_range_forEach") : lookup.kkRangeForEachName)
            _ = emitHOFCall(
                kkName: forEachCallee, receiver: receiver,
                arguments: arguments + [zeroExpr],
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, module: module,
                loweredBody: &loweredBody
            )
            return true
        }

        // map — HOF returning List (STDLIB-091)
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

        // Additional range HOFs.
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
                kkName: isUIntRange ? interner.intern("kk_uint_range_reduce") : lookup.kkRangeReduceName,
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
                kkName: isUIntRange ? interner.intern("kk_uint_range_reduceIndexed") : lookup.kkRangeReduceIndexedName,
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
                kkName: isUIntRange ? interner.intern("kk_uint_range_fold") : lookup.kkRangeFoldName,
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
                kkName: isUIntRange ? interner.intern("kk_uint_range_foldIndexed") : lookup.kkRangeFoldIndexedName,
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
                kkName: isUIntRange ? interner.intern("kk_uint_range_find") : lookup.kkRangeFindName,
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
                kkName: isUIntRange ? interner.intern("kk_uint_range_findLast") : lookup.kkRangeFindLastName,
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
                kkName: isUIntRange ? interner.intern("kk_uint_range_first_predicate") : lookup.kkRangeFirstPredicateName,
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
            let firstOrNullName = isULongRange ? interner.intern("kk_ulong_range_firstOrNull")
                : interner.intern("kk_range_firstOrNull")
            loweredBody.append(.call(
                symbol: nil, callee: firstOrNullName,
                arguments: [receiver], result: result,
                canThrow: false, thrownResult: nil
            ))
            return true
        }
        if callee == lookup.firstOrNullName, arguments.count == 1 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            _ = emitHOFCall(
                kkName: isUIntRange ? interner.intern("kk_uint_range_firstOrNull_predicate") : lookup.kkRangeFirstOrNullPredicateName,
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
                kkName: isUIntRange ? interner.intern("kk_uint_range_last_predicate") : lookup.kkRangeLastPredicateName,
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
            let lastOrNullName = isULongRange ? interner.intern("kk_ulong_range_lastOrNull")
                : interner.intern("kk_range_lastOrNull")
            loweredBody.append(.call(
                symbol: nil, callee: lastOrNullName,
                arguments: [receiver], result: result,
                canThrow: false, thrownResult: nil
            ))
            return true
        }
        if callee == lookup.lastOrNullName, arguments.count == 1 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            _ = emitHOFCall(
                kkName: isUIntRange ? interner.intern("kk_uint_range_lastOrNull_predicate") : lookup.kkRangeLastOrNullPredicateName,
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
                callee == lookup.anyName ? (isUIntRange ? interner.intern("kk_uint_range_any") : lookup.kkRangeAnyName)
                    : callee == lookup.allName ? (isUIntRange ? interner.intern("kk_uint_range_all") : lookup.kkRangeAllName)
                    : (isUIntRange ? interner.intern("kk_uint_range_none") : lookup.kkRangeNoneName)
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
                symbol: nil, callee: isULongRange ? interner.intern("__kk_ulong_range_chunked")
                    : (isUIntRange ? interner.intern("__kk_uint_range_chunked") : lookup.kkRangeChunkedName),
                arguments: [receiver] + arguments, result: result,
                canThrow: true, thrownResult: origThrownResult
            ))
            state.tagListResult(result)
            return true
        }
        if callee == lookup.windowedName, arguments.count == 3 {
            loweredBody.append(.call(
                symbol: nil, callee: isULongRange ? interner.intern("__kk_ulong_range_windowed")
                    : (isUIntRange ? interner.intern("__kk_uint_range_windowed") : lookup.kkRangeWindowedName),
                arguments: [receiver] + arguments, result: result,
                canThrow: true, thrownResult: origThrownResult
            ))
            state.tagListResult(result)
            return true
        }

        // take/drop/average/sorted — dispatch by range type (STDLIB-RANGE-TDS)
        if callee == lookup.takeName, arguments.count == 1 {
            let takeName: InternedString
            if isULongRange {
                takeName = interner.intern("__kk_ulong_range_take")
            } else if isUIntRange {
                takeName = interner.intern("__kk_uint_range_take")
            } else if isLongRange {
                takeName = interner.intern("kk_long_range_take")
            } else if isCharRange {
                takeName = interner.intern("kk_char_range_take")
            } else {
                takeName = lookup.kkRangeTakeName
            }
            loweredBody.append(.call(symbol: nil, callee: takeName,
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
                dropName = interner.intern("kk_long_range_drop")
            } else if isCharRange {
                dropName = interner.intern("kk_char_range_drop")
            } else {
                dropName = lookup.kkRangeDropName
            }
            loweredBody.append(.call(symbol: nil, callee: dropName,
                arguments: [receiver] + arguments, result: result, canThrow: true, thrownResult: origThrownResult))
            state.tagListResult(result)
            return true
        }
        if callee == lookup.averageName, arguments.isEmpty {
            // KSP-1523: the isUIntRange arm here was unreachable for the same
            // structural reason as the other members above (see `first`/`start`).
            let averageName: InternedString
            if isULongRange {
                averageName = interner.intern("kk_ulong_range_average")
            } else if isLongRange {
                averageName = interner.intern("kk_long_range_average")
            } else {
                averageName = lookup.kkRangeAverageName
            }
            loweredBody.append(.call(symbol: nil, callee: averageName,
                arguments: [receiver], result: result, canThrow: false, thrownResult: nil))
            return true
        }
        if callee == lookup.sortedName, arguments.isEmpty {
            // KSP-1523: the isUIntRange arm here was unreachable for the same
            // structural reason as the other members above (see `first`/`start`).
            let sortedName: InternedString
            if isULongRange {
                sortedName = interner.intern("kk_ulong_range_sorted")
            } else if isLongRange {
                sortedName = interner.intern("kk_long_range_sorted")
            } else if isCharRange {
                sortedName = interner.intern("kk_char_range_sorted")
            } else {
                sortedName = lookup.kkRangeSortedName
            }
            loweredBody.append(.call(symbol: nil, callee: sortedName,
                arguments: [receiver], result: result, canThrow: false, thrownResult: nil))
            state.tagListResult(result)
            return true
        }

        // reversed — returns a range (STDLIB-093)
        if callee == lookup.reversedName, arguments.isEmpty {
            // KSP-1523: the isUIntRange arm here was unreachable for the same
            // structural reason as the other members above (see `first`/`start`).
            let reversedName = isULongRange ? lookup.kkULongRangeReversedName : lookup.kkRangeReversedName
            loweredBody.append(.call(
                symbol: nil, callee: reversedName,
                arguments: [receiver], result: result,
                canThrow: false, thrownResult: nil
            ))
            if let result {
                state.insert(.range, result)
                // Propagate char range through reversed() (STDLIB-290)
                if isCharRange { state.insert(.charRange, result) }
                // Propagate ULong range through reversed() (STDLIB-524)
                if isULongRange { state.insert(.ulongRange, result) }
            }
            return true
        }

        return false
    }

    // MARK: - Static type fallback classification (LOWERING-001)

    /// Classify a receiver expression by its static type in the KIR arena.
    /// If the receiver is already in one of the tracking sets, this is a no-op.
    /// Otherwise, look up the expression's TypeID, resolve its class symbol,
    /// and insert it into the appropriate tracking set so that downstream
    /// rewrite logic can match on it.
}
