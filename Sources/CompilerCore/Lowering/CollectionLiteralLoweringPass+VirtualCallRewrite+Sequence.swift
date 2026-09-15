// swiftlint:disable file_length

/// Virtual-call rewrite for `Sequence`-typed receivers.
///
/// Split out from `CollectionLiteralLoweringPass+VirtualCallRewrite.swift`
/// to keep each rewrite source scoped to a single receiver kind.
extension CollectionVirtualCallRewriteLoweringPass {
    // MARK: - Sequence operations

    func rewriteSequenceVirtualCall(
        symbol: SymbolID?,
        callee: InternedString,
        receiver: KIRExprID,
        arguments: [KIRExprID],
        result: KIRExprID?,
        origCanThrow: Bool,
        origThrownResult: KIRExprID?,
        module: KIRModule,
        lookup: CollectionLiteralLookupTables,
        context: VirtualCallRewriteContext,
        state: inout CollectionRewriteState,
        loweredBody: inout KIRLoweringEmitContext
    ) -> Bool {
        // STDLIB-pipeline §5 / KSP-441〜447: If the resolved callee is a bundled
        // Kotlin source declaration, route through normal function resolution so
        // the source implementation runs instead of a `kk_*` runtime shortcut.
        func isSourceBackedSequenceCall() -> Bool {
            guard let symbol,
                  let sema = context.sema,
                  sema.symbols.symbol(symbol) != nil
            else {
                return false
            }
            return sema.symbols.isSourceBackedSymbol(symbol)
        }
        // Runtime-backed Sequence expressions need the toMap bridge so iterator
        // exceptions can flow through the ABI outThrown channel.
        if isSourceBackedSequenceCall(),
           !(callee == lookup.toMapName && state.contains(.sequence, receiver))
        {
            return false
        }

        // requireNoNulls() on sequence -> kk_sequence_requireNoNulls
        // The bundled source iterator cannot propagate an exception thrown from
        // hasNext(), so the runtime pipeline step (which sets outThrown) is kept.
        if callee == lookup.requireNoNullsName, arguments.isEmpty,
           let kkName = lookup.collectionHOFRuntimeName(ownerKind: .sequence, callee: callee, arity: 0) {
            loweredBody.append(.call(
                symbol: nil,
                callee: kkName,
                arguments: [receiver],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            state.tagResult(.sequence, result)
            return true
        }

        // asSequence() → kk_list_asSequence only when receiver is a tracked list.
        // Array receivers are handled by rewriteArrayVirtualCall (guarded by arrayExprIDs).
        // Non-tracked receivers are now classified by static type via
        // classifyReceiverByStaticType (LOWERING-001) before reaching here.
        if callee == lookup.asSequenceName, arguments.isEmpty,
           state.contains(.list, receiver)
        {
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkListAsSequenceName,
                arguments: [receiver],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            state.tagResult(.sequence, result)
            return true
        }

        if callee == lookup.mapName || callee == lookup.filterName, arguments.count == 1 {
            if state.contains(.sequence, receiver) {
                let kkName = callee == lookup.mapName
                    ? lookup.kkSequenceMapName : lookup.kkSequenceFilterName
                loweredBody.append(.call(
                    symbol: nil,
                    callee: kkName,
                    arguments: [receiver] + arguments,
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                state.tagResult(.sequence, result)
                return true
            }
        }

        if callee == lookup.flatMapName || callee == lookup.flatMapIndexedName, arguments.count == 1 {
            if state.contains(.sequence, receiver) {
                let kkName = callee == lookup.flatMapName
                    ? lookup.kkSequenceFlatMapName : lookup.kkSequenceFlatMapIndexedName
                loweredBody.append(.call(
                    symbol: nil,
                    callee: kkName,
                    arguments: [receiver] + arguments,
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                state.tagResult(.sequence, result)
                return true
            }
        }


        if callee == lookup.chunkedName, arguments.count == 1, state.contains(.list, receiver) {
            let transformResult = module.arena.appendTemporary(type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkListChunkedBridgeName,
                arguments: [receiver] + arguments,
                result: transformResult,
                canThrow: false,
                thrownResult: nil
            ))
            if let result {
                state.tagListResult(result, temporary: transformResult)
                loweredBody.append(.copy(from: transformResult, to: result))
            }
            return true
        }

        // chunked(size, transform) HOF overload after closure expansion: [size, fnPtr, closureRaw]
        if callee == lookup.chunkedName, arguments.count == 3, state.contains(.list, receiver) {
            let transformResult = module.arena.appendTemporary(type: nil
            )
            let thrownExpr = origThrownResult ?? module.arena.appendTemporary(type: nil)
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkListChunkedTransformBridgeName,
                arguments: [receiver] + arguments,
                result: transformResult,
                canThrow: true,
                thrownResult: thrownExpr
            ))
            if let result {
                state.tagListResult(result, temporary: transformResult)
                loweredBody.append(.copy(from: transformResult, to: result))
            }
            return true
        }

        if callee == lookup.windowedName, arguments.count == 1, state.contains(.list, receiver) {
            let transformResult = module.arena.appendTemporary(type: nil
            )
            let oneExpr = module.arena.appendExpr(.intLiteral(1), type: nil)
            loweredBody.append(.constValue(result: oneExpr, value: .intLiteral(1)))
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkListWindowedBridgeName,
                arguments: [receiver, arguments[0], oneExpr, zeroExpr],
                result: transformResult,
                canThrow: false,
                thrownResult: nil
            ))
            if let result {
                state.tagListResult(result, temporary: transformResult)
                loweredBody.append(.copy(from: transformResult, to: result))
            }
            return true
        }

        if callee == lookup.windowedName, arguments.count == 2, state.contains(.list, receiver) {
            let transformResult = module.arena.appendTemporary(type: nil
            )
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkListWindowedBridgeName,
                arguments: [receiver, arguments[0], arguments[1], zeroExpr],
                result: transformResult,
                canThrow: false,
                thrownResult: nil
            ))
            if let result {
                state.tagListResult(result, temporary: transformResult)
                loweredBody.append(.copy(from: transformResult, to: result))
            }
            return true
        }

        if callee == lookup.windowedName, arguments.count == 3, state.contains(.list, receiver) {
            let thirdArgType = module.arena.exprType(arguments[2])
            let thirdArgIsBoolean = context.sema.map { thirdArgType == $0.types.booleanType } ?? false
            if thirdArgIsBoolean {
                let transformResult = module.arena.appendTemporary(type: nil
                )
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkListWindowedBridgeName,
                    arguments: [receiver] + arguments,
                    result: transformResult,
                    canThrow: false,
                    thrownResult: nil
                ))
                if let result {
                    state.tagListResult(result, temporary: transformResult)
                    loweredBody.append(.copy(from: transformResult, to: result))
                }
                return true
            }
        }

        if callee == lookup.windowedName,
           supportsIterableWindowedTransformReceiver(
               receiver: receiver,
               context: context,
               listExprIDs: state.listExprIDs,
               setExprIDs: state.setExprIDs,
               arrayExprIDs: state.arrayExprIDs
           ),
           let bridgeArguments = makeWindowedTransformBridgeArguments(
               receiver: receiver,
               windowedArguments: arguments,
               module: module,
               sema: context.sema,
               loweredBody: &loweredBody
           )
        {
            let transformResult = module.arena.appendTemporary(type: nil
            )
            let thrownExpr = origThrownResult ?? module.arena.appendTemporary(type: nil)
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkListWindowedTransformBridgeName,
                arguments: bridgeArguments,
                result: transformResult,
                canThrow: true,
                thrownResult: thrownExpr
            ))
            if let result {
                state.tagListResult(result, temporary: transformResult)
                loweredBody.append(.copy(from: transformResult, to: result))
            }
            return true
        }

        if callee == lookup.shuffledName,
           arguments.isEmpty || arguments.count == 1,
           state.contains(.sequence, receiver)
        {
            let kkName = arguments.isEmpty
                ? lookup.kkSequenceShuffledName
                : lookup.kkSequenceShuffledRandomName
            loweredBody.append(.call(
                symbol: nil,
                callee: kkName,
                arguments: [receiver] + arguments,
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            state.tagResult(.sequence, result)
            return true
        }

        if callee == lookup.shuffledName, arguments.isEmpty, state.contains(.list, receiver) {
            let transformResult = module.arena.appendTemporary(type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkListShuffledName,
                arguments: [receiver],
                result: transformResult,
                canThrow: false,
                thrownResult: nil
            ))
            if let result {
                state.tagListResult(result, temporary: transformResult)
                loweredBody.append(.copy(from: transformResult, to: result))
            }
            return true
        }

        // shuffled(random: Random) overload (STDLIB-531)
        if callee == lookup.shuffledName, arguments.count == 1, state.contains(.list, receiver) {
            let transformResult = module.arena.appendTemporary(type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkListShuffledRandomName,
                arguments: [receiver] + arguments,
                result: transformResult,
                canThrow: false,
                thrownResult: nil
            ))
            if let result {
                state.tagListResult(result, temporary: transformResult)
                loweredBody.append(.copy(from: transformResult, to: result))
            }
            return true
        }

        if callee == lookup.toListName, arguments.isEmpty {
            if state.contains(.sequence, receiver) {
                if let result {
                    let toListResult = module.arena.appendTemporary(type: nil
                    )
                    loweredBody.append(.call(
                        symbol: nil,
                        callee: lookup.kkSequenceToListName,
                        arguments: [receiver],
                        result: toListResult,
                        canThrow: true,
                        thrownResult: nil
                    ))
                    state.tagListResult(result, temporary: toListResult)
                    loweredBody.append(.copy(from: toListResult, to: result))
                } else {
                    loweredBody.append(.call(
                        symbol: nil,
                        callee: lookup.kkSequenceToListName,
                        arguments: [receiver],
                        result: nil,
                        canThrow: true,
                        thrownResult: nil
                    ))
                }
                return true
            }
        }

        // constrainOnce() on sequence -> kk_sequence_constrainOnce
        if callee == lookup.constrainOnceName, arguments.isEmpty, state.contains(.sequence, receiver) {
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkSequenceConstrainOnceName,
                arguments: [receiver],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            state.tagResult(.sequence, result)
            return true
        }

        // toSet() on sequence → kk_sequence_toSet (STDLIB-470)
        if callee == lookup.toSetName, arguments.isEmpty, state.contains(.sequence, receiver) {
            let toSetResult = module.arena.appendTemporary(type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkSequenceToSetName,
                arguments: [receiver],
                result: toSetResult,
                canThrow: false,
                thrownResult: nil
            ))
            if let result {
                state.tagResult(.set, result, temporary: toSetResult)
                loweredBody.append(.copy(from: toSetResult, to: result))
            }
            return true
        }

        // toMap() on sequence → kk_sequence_toMap (STDLIB-470)
        if callee == lookup.toMapName, arguments.isEmpty, state.contains(.sequence, receiver) {
            let toMapResult = module.arena.appendTemporary(type: nil
            )
            let thrownExpr = origThrownResult ?? module.arena.appendTemporary(type: nil)
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkSequenceToMapName,
                arguments: [receiver],
                result: toMapResult,
                canThrow: true,
                thrownResult: thrownExpr
            ))
            if let result {
                state.tagMapResult(result, temporary: toMapResult)
                loweredBody.append(.copy(from: toMapResult, to: result))
            }
            return true
        }

        // max / maxOrNull / minOrNull on sequence (STDLIB-SEQ-FN-065, STDLIB-470)
        if callee == lookup.maxName || callee == lookup.maxOrNullName || callee == lookup.minOrNullName,
           arguments.isEmpty, state.contains(.sequence, receiver)
        {
            let kkName: InternedString
            if callee == lookup.maxName {
                kkName = lookup.kkSequenceMaxName
            } else {
                kkName = callee == lookup.maxOrNullName
                    ? lookup.kkSequenceMaxOrNullName : lookup.kkSequenceMinOrNullName
            }
            let hofResult = module.arena.appendTemporary(type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: kkName,
                arguments: [receiver],
                result: hofResult,
                canThrow: origCanThrow,
                thrownResult: origThrownResult
            ))
            if let result {
                loweredBody.append(.copy(from: hofResult, to: result))
            }
            return true
        }

        // flatten on sequence → kk_sequence_flatten (STDLIB-470)
        if callee == lookup.flattenName, arguments.isEmpty, state.contains(.sequence, receiver) {
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkSequenceFlattenName,
                arguments: [receiver],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            state.tagResult(.sequence, result)
            return true
        }

        // runningFoldIndexed on sequence → kk_sequence_runningFoldIndexed (STDLIB-SEQ-016)
        // Args: initial, lambda (2 from Kotlin: initial + operation)
        if callee == lookup.runningFoldIndexedName, arguments.count == 2,
           state.contains(.sequence, receiver)
        {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            let hofResult = emitHOFCall(
                kkName: lookup.kkSequenceRunningFoldIndexedName,
                receiver: receiver,
                arguments: [arguments[0]] + [arguments[1]] + [zeroExpr],
                result: result,
                origCanThrow: origCanThrow,
                origThrownResult: origThrownResult,
                module: module,
                loweredBody: &loweredBody
            )
            state.tagResult(.sequence, result, temporary: hofResult)
            return true
        }

        // scanIndexed on sequence -> kk_sequence_scanIndexed (STDLIB-SEQ-FN-105)
        // Args: initial, lambda (2 from Kotlin: initial + operation)
        if callee == lookup.scanIndexedName, arguments.count == 2,
           state.contains(.sequence, receiver)
        {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            let hofResult = emitHOFCall(
                kkName: lookup.kkSequenceScanIndexedName,
                receiver: receiver,
                arguments: [arguments[0]] + [arguments[1]] + [zeroExpr],
                result: result,
                origCanThrow: origCanThrow,
                origThrownResult: origThrownResult,
                module: module,
                loweredBody: &loweredBody
            )
            state.tagResult(.sequence, result, temporary: hofResult)
            return true
        }

        // reduceIndexed on sequence → kk_sequence_reduceIndexed (STDLIB-556)
        // Args: lambda (1 from Kotlin: operation)
        if callee == lookup.reduceIndexedName, arguments.count == 1,
           state.contains(.sequence, receiver)
        {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            emitHOFCall(
                kkName: lookup.kkSequenceReduceIndexedName,
                receiver: receiver,
                arguments: arguments + [zeroExpr],
                result: result,
                origCanThrow: origCanThrow,
                origThrownResult: origThrownResult,
                module: module,
                loweredBody: &loweredBody
            )
            return true
        }

        // reduceIndexedOrNull on sequence → kk_sequence_reduceIndexedOrNull (STDLIB-SEQ-015)
        // Args: lambda (1 from Kotlin: operation)
        if callee == lookup.reduceIndexedOrNullName, arguments.count == 1,
           state.contains(.sequence, receiver)
        {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            emitHOFCall(
                kkName: lookup.kkSequenceReduceIndexedOrNullName,
                receiver: receiver,
                arguments: arguments + [zeroExpr],
                result: result,
                origCanThrow: origCanThrow,
                origThrownResult: origThrownResult,
                module: module,
                loweredBody: &loweredBody
            )
            return true
        }

        let sequencePlusMinusCallees = SequencePlusMinusRuntimeCallees(
            plus: lookup.kkSequencePlusName,
            minus: lookup.kkSequenceMinusName,
            ofSingle: lookup.kkSequenceOfSingleName
        )

        // plus(other) on sequence → kk_sequence_plus (STDLIB-561)
        if callee == lookup.plusMemberName, arguments.count == 1, state.contains(.sequence, receiver) {
            let argID = arguments[0]
            // Only sequence/list/array are supported by kk_sequence_plus
            // at the ABI level (not Set/Map).
            let isArgCollection = state.contains(.list, argID)
                || state.contains(.sequence, argID)
                || state.contains(.array, argID)
            emitSequencePlusMinusRewrite(
                operation: .plus,
                receiver: receiver,
                argument: argID,
                argumentIsCollection: isArgCollection,
                result: result,
                arena: module.arena,
                callees: sequencePlusMinusCallees,
                instructions: &loweredBody
            )
            state.tagResult(.sequence, result)
            return true
        }

        // plusElement(element) on sequence -> kk_sequence_plus_element (STDLIB-SEQ-013)
        if callee == lookup.plusElementName, arguments.count == 1, state.contains(.sequence, receiver) {
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkSequencePlusElementName,
                arguments: [receiver, arguments[0]],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            state.tagResult(.sequence, result)
            return true
        }

        // Iterable.minusElement(element) returns a List, even when the receiver
        // is tracked through the generic Iterable interface.
        // minus(element)/minusElement(element) on sequence → kk_sequence_minus
        if callee == lookup.minusMemberName || callee == lookup.minusElementName,
           arguments.count == 1,
           state.contains(.sequence, receiver)
        {
            let argID = arguments[0]
            // Only sequence/list/array are supported by the ABI (not
            // Set/Map) -- consistent with plus path.
            let isArgCollection = state.contains(.list, argID)
                || state.contains(.sequence, argID)
                || state.contains(.array, argID)
            let rewriteResult = emitSequencePlusMinusRewrite(
                operation: .minus,
                receiver: receiver,
                argument: argID,
                argumentIsCollection: isArgCollection,
                result: result,
                arena: module.arena,
                callees: sequencePlusMinusCallees,
                instructions: &loweredBody
            )
            guard case .emitted = rewriteResult else {
                // Fall through: collection-removal not supported
                return false
            }
            state.tagResult(.sequence, result)
            return true
        }

        return false
    }

    // MARK: - List higher-order function operations
}
