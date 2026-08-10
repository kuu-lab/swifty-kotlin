import Foundation

/// Virtual-call rewrite for `Array`-typed receivers
/// (STDLIB-087/088/089).
///
/// Split out from `CollectionLiteralLoweringPass+VirtualCallRewrite.swift`.
extension CollectionVirtualCallRewriteLoweringPass {
    // MARK: - Array virtual call operations (STDLIB-087/088/089)

    func rewriteArrayVirtualCall(
        callee: InternedString,
        receiver: KIRExprID,
        arguments: [KIRExprID],
        result: KIRExprID?,
        origCanThrow: Bool,
        origThrownResult: KIRExprID?,
        module: KIRModule,
        lookup: CollectionLiteralLookupTables,
        listExprIDs: inout Set<Int32>,
        arrayExprIDs: inout Set<Int32>,
        sequenceExprIDs: inout Set<Int32>,
        loweredBody: inout [KIRInstruction]
    ) -> Bool {
        // Non-tracked array receivers are now classified by static type via
        // classifyReceiverByStaticType (LOWERING-001) before reaching here.
        guard arrayExprIDs.contains(receiver.rawValue) else { return false }

        // toList on array → kk_array_toList (result is List)
        if callee == lookup.toListName, arguments.isEmpty {
            let toListResult = module.arena.appendTemporary(type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkArrayToListName,
                arguments: [receiver],
                result: toListResult,
                canThrow: false,
                thrownResult: nil
            ))
            if let result {
                listExprIDs.insert(result.rawValue)
                listExprIDs.insert(toListResult.rawValue)
                loweredBody.append(.copy(from: toListResult, to: result))
            }
            return true
        }

        // toMutableList on array → kk_array_toMutableList (result is MutableList)
        if callee == lookup.toMutableListName, arguments.isEmpty {
            let toMutableListResult = module.arena.appendTemporary(type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkArrayToMutableListName,
                arguments: [receiver],
                result: toMutableListResult,
                canThrow: false,
                thrownResult: nil
            ))
            if let result {
                listExprIDs.insert(result.rawValue)
                listExprIDs.insert(toMutableListResult.rawValue)
                loweredBody.append(.copy(from: toMutableListResult, to: result))
            }
            return true
        }

        // map/filter on array → kk_array_map/kk_array_filter (result is List)
        if callee == lookup.mapName || callee == lookup.filterName, arguments.count == 1 {
            let kkName = callee == lookup.mapName
                ? lookup.kkArrayMapName : lookup.kkArrayFilterName
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            let hofResult = emitHOFCall(
                kkName: kkName, receiver: receiver, arguments: arguments + [zeroExpr],
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, module: module,
                loweredBody: &loweredBody
            )
            if let result {
                listExprIDs.insert(result.rawValue)
                listExprIDs.insert(hofResult.rawValue)
            }
            return true
        }

        // forEach on array → kk_array_forEach
        if callee == lookup.forEachName, arguments.count == 1 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            _ = emitHOFCall(
                kkName: lookup.kkArrayForEachName, receiver: receiver, arguments: arguments + [zeroExpr],
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, module: module,
                loweredBody: &loweredBody
            )
            return true
        }

        // any/all/none/count on array → kk_array_any/kk_array_all/kk_array_none/kk_array_count
        if callee == lookup.anyName || callee == lookup.allName || callee == lookup.noneName || callee == lookup.countName,
           arguments.count == 1
        {
            let kkName: InternedString = if callee == lookup.anyName {
                lookup.kkArrayAnyName
            } else if callee == lookup.allName {
                lookup.kkArrayAllName
            } else if callee == lookup.noneName {
                lookup.kkArrayNoneName
            } else {
                lookup.kkArrayCountName
            }
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            _ = emitHOFCall(
                kkName: kkName, receiver: receiver, arguments: arguments + [zeroExpr],
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, module: module,
                loweredBody: &loweredBody
            )
            return true
        }

        // copyOf on array → kk_array_copyOf* (result is Array)
        if callee == lookup.copyOfName, arguments.isEmpty || arguments.count == 1 || arguments.count == 2 || arguments.count == 3 {
            let copyResult = module.arena.appendTemporary(type: nil
            )
            let runtimeCallee: InternedString
            let runtimeArguments: [KIRExprID]
            let canThrow: Bool
            if arguments.isEmpty {
                runtimeCallee = lookup.kkArrayCopyOfName
                runtimeArguments = [receiver]
                canThrow = false
            } else if arguments.count == 1 {
                runtimeCallee = lookup.kkArrayCopyOfNewSizeName
                runtimeArguments = [receiver] + arguments
                canThrow = false
            } else {
                let closureRawExpr: KIRExprID
                if arguments.count == 3 {
                    closureRawExpr = arguments[2]
                } else {
                    let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
                    loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                    closureRawExpr = zeroExpr
                }
                runtimeCallee = lookup.kkArrayCopyOfNewSizeInitName
                runtimeArguments = [receiver, arguments[0], arguments[1], closureRawExpr]
                canThrow = true
            }
            loweredBody.append(.call(
                symbol: nil,
                callee: runtimeCallee,
                arguments: runtimeArguments,
                result: copyResult,
                canThrow: canThrow,
                thrownResult: canThrow ? origThrownResult : nil
            ))
            if let result {
                arrayExprIDs.insert(result.rawValue)
                arrayExprIDs.insert(copyResult.rawValue)
                loweredBody.append(.copy(from: copyResult, to: result))
            }
            return true
        }

        // copyOfRange on array → kk_array_copyOfRange (result is Array)
        if callee == lookup.copyOfRangeName, arguments.count == 2 {
            let copyResult = module.arena.appendTemporary(type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkArrayCopyOfRangeName,
                arguments: [receiver] + arguments,
                result: copyResult,
                canThrow: true,
                thrownResult: origThrownResult
            ))
            if let result {
                arrayExprIDs.insert(result.rawValue)
                arrayExprIDs.insert(copyResult.rawValue)
                loweredBody.append(.copy(from: copyResult, to: result))
            }
            return true
        }

        // fill on array → kk_array_fill
        if callee == lookup.fillName, arguments.count == 1 {
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkArrayFillName,
                arguments: [receiver] + arguments,
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return true
        }

        // asSequence on array → kk_array_asSequence (STDLIB-471)
        if callee == lookup.asSequenceName, arguments.isEmpty {
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkArrayAsSequenceName,
                arguments: [receiver],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            if let result { sequenceExprIDs.insert(result.rawValue) }
            return true
        }

        // reduce/reduceOrNull/reduceIndexed on array (STDLIB-GAP-PH1)
        if callee == lookup.reduceName || callee == lookup.reduceOrNullName || callee == lookup.reduceIndexedName,
           arguments.count == 1
        {
            let kkName: InternedString = if callee == lookup.reduceName {
                lookup.kkArrayReduceName
            } else if callee == lookup.reduceOrNullName {
                lookup.kkArrayReduceOrNullName
            } else {
                lookup.kkArrayReduceIndexedName
            }
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            _ = emitHOFCall(
                kkName: kkName, receiver: receiver, arguments: arguments + [zeroExpr],
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, module: module,
                loweredBody: &loweredBody
            )
            return true
        }

        // fold/foldIndexed on array (STDLIB-GAP-PH1)
        if callee == lookup.foldName || callee == lookup.foldIndexedName, arguments.count == 2 {
            let kkName: InternedString = callee == lookup.foldName
                ? lookup.kkArrayFoldName : lookup.kkArrayFoldIndexedName
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            _ = emitHOFCall(
                kkName: kkName, receiver: receiver, arguments: arguments + [zeroExpr],
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, module: module,
                loweredBody: &loweredBody
            )
            return true
        }

        // flatMap on array → kk_array_flatMap (result is List) (STDLIB-GAP-PH1)
        if callee == lookup.flatMapName, arguments.count == 1 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            let hofResult = emitHOFCall(
                kkName: lookup.kkArrayFlatMapName, receiver: receiver, arguments: arguments + [zeroExpr],
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, module: module,
                loweredBody: &loweredBody
            )
            if let result {
                listExprIDs.insert(result.rawValue)
                listExprIDs.insert(hofResult.rawValue)
            }
            return true
        }

        // mapIndexed/filterIndexed on array → kk_array_mapIndexed/kk_array_filterIndexed
        // (result is List). Array HOF gap fix: these previously failed Sema
        // member resolution outright (see CallTypeChecker+ArrayMemberFallback.swift).
        if callee == lookup.mapIndexedName || callee == lookup.filterIndexedName, arguments.count == 1 {
            let kkName: InternedString = callee == lookup.mapIndexedName
                ? lookup.kkArrayMapIndexedName : lookup.kkArrayFilterIndexedName
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            let hofResult = emitHOFCall(
                kkName: kkName, receiver: receiver, arguments: arguments + [zeroExpr],
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, module: module,
                loweredBody: &loweredBody
            )
            if let result {
                listExprIDs.insert(result.rawValue)
                listExprIDs.insert(hofResult.rawValue)
            }
            return true
        }

        // mapNotNull/filterNot on array → kk_array_mapNotNull/kk_array_filterNot
        // (result is List). Array HOF gap fix.
        if callee == lookup.mapNotNullName || callee == lookup.filterNotName, arguments.count == 1 {
            let kkName: InternedString = callee == lookup.mapNotNullName
                ? lookup.kkArrayMapNotNullName : lookup.kkArrayFilterNotName
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            let hofResult = emitHOFCall(
                kkName: kkName, receiver: receiver, arguments: arguments + [zeroExpr],
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, module: module,
                loweredBody: &loweredBody
            )
            if let result {
                listExprIDs.insert(result.rawValue)
                listExprIDs.insert(hofResult.rawValue)
            }
            return true
        }

        // filterNotNull on array → kk_array_filterNotNull (result is List, no
        // lambda argument). Array HOF gap fix.
        if callee == lookup.filterNotNullName, arguments.isEmpty {
            let filterResult = module.arena.appendTemporary(type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkArrayFilterNotNullName,
                arguments: [receiver],
                result: filterResult,
                canThrow: false,
                thrownResult: nil
            ))
            if let result {
                listExprIDs.insert(result.rawValue)
                listExprIDs.insert(filterResult.rawValue)
                loweredBody.append(.copy(from: filterResult, to: result))
            }
            return true
        }

        // first()/last() on array (no predicate) → kk_array_first/kk_array_last
        // (throws NoSuchElementException when empty). Array HOF gap fix.
        if callee == lookup.firstName, arguments.isEmpty {
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkArrayFirstName,
                arguments: [receiver],
                result: result,
                canThrow: true,
                thrownResult: origThrownResult
            ))
            return true
        }
        if callee == lookup.lastName, arguments.isEmpty {
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkArrayLastName,
                arguments: [receiver],
                result: result,
                canThrow: true,
                thrownResult: origThrownResult
            ))
            return true
        }

        // firstOrNull()/lastOrNull() on array (no predicate) →
        // kk_array_firstOrNull/kk_array_lastOrNull (never throws). Array HOF gap fix.
        if callee == lookup.firstOrNullName, arguments.isEmpty {
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkArrayFirstOrNullName,
                arguments: [receiver],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return true
        }
        if callee == lookup.lastOrNullName, arguments.isEmpty {
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkArrayLastOrNullName,
                arguments: [receiver],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return true
        }

        // first(predicate)/last(predicate) on array → kk_array_first_predicate/
        // kk_array_last_predicate (throws NoSuchElementException on no match).
        // Array HOF gap fix. Like the map/filter/mapIndexed/etc. cases above,
        // a zero placeholder is appended after the single source-level lambda
        // argument to match the runtime function's (arrayRaw, fnPtr,
        // closureRaw, outThrown) shape — see emitHOFCall's callers above.
        if callee == lookup.firstName, arguments.count == 1 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            _ = emitHOFCall(
                kkName: lookup.kkArrayFirstPredicateName, receiver: receiver, arguments: arguments + [zeroExpr],
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
                kkName: lookup.kkArrayLastPredicateName, receiver: receiver, arguments: arguments + [zeroExpr],
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, module: module,
                loweredBody: &loweredBody
            )
            return true
        }

        // firstOrNull(predicate)/lastOrNull(predicate) on array reuse the
        // existing find/findLast runtime entry points (identical semantics:
        // returns null, never throws, when no element matches). Array HOF gap fix.
        if callee == lookup.firstOrNullName, arguments.count == 1 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            _ = emitHOFCall(
                kkName: lookup.kkArrayFindName, receiver: receiver, arguments: arguments + [zeroExpr],
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, module: module,
                loweredBody: &loweredBody
            )
            return true
        }
        if callee == lookup.lastOrNullName, arguments.count == 1 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            _ = emitHOFCall(
                kkName: lookup.kkArrayFindLastName, receiver: receiver, arguments: arguments + [zeroExpr],
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, module: module,
                loweredBody: &loweredBody
            )
            return true
        }

        return false
    }
}
