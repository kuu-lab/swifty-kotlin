// swiftlint:disable file_length

/// Split out from `CollectionLiteralLoweringPass+VirtualCallRewrite.swift`
/// to keep each rewrite source scoped to a single receiver kind.
extension CollectionVirtualCallRewriteLoweringPass {
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
        // STDLIB-pipeline §5 / KSP-441〜447: source-backed Sequence calls stay
        // on their Kotlin implementation unless the receiver is a confirmed
        // RuntimeSequenceBox. The virtual `toMap` bridge remains the one
        // representation-specific exception because its iterator failure must
        // use the ABI outThrown channel.
        let resolution = SourceBackedCalleeResolution(symbol: symbol, sema: context.sema)
        if resolution == .sourceBacked {
            let representation = sequenceRuntimeRepresentationForCall(
                symbol: symbol,
                receiver: receiver,
                state: state,
                module: module,
                sema: context.sema,
                interner: context.interner
            )
            if !(callee == lookup.toMapName && representation == .runtimeBox) {
                return false
            }
        }

        // The bundled source iterator cannot propagate an exception thrown from
        // hasNext(), so the runtime pipeline step (which sets outThrown) is kept.
        if callee == lookup.requireNoNullsName, arguments.isEmpty,
           let kkName = lookup.collectionHOFRuntimeName(ownerKind: .sequence, callee: callee, arity: 0) {
            loweredBody.append(.call(
                callee: kkName,
                arguments: [receiver],
                result: result,
                canThrow: false
            ))
            state.tagResult(.sequence, result)
            return true
        }

        // Array receivers are handled by rewriteArrayVirtualCall (guarded by arrayExprIDs).
        // Non-tracked receivers are now classified by static type via
        // classifyReceiverByStaticType (LOWERING-001) before reaching here.
        if callee == lookup.asSequenceName, arguments.isEmpty,
           state.contains(.list, receiver)
        {
            loweredBody.append(.call(
                callee: lookup.kkListAsSequenceName,
                arguments: [receiver],
                result: result,
                canThrow: false
            ))
            state.tagResult(.sequence, result)
            return true
        }

        if callee == lookup.mapName || callee == lookup.filterName, arguments.count == 1 {
            if state.contains(.sequence, receiver) {
                let kkName = callee == lookup.mapName
                    ? lookup.kkSequenceMapName : lookup.kkSequenceFilterName
                loweredBody.append(.call(
                    callee: kkName,
                    arguments: [receiver] + arguments,
                    result: result,
                    canThrow: false
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
                    callee: kkName,
                    arguments: [receiver] + arguments,
                    result: result,
                    canThrow: false
                ))
                state.tagResult(.sequence, result)
                return true
            }
        }


        if callee == lookup.chunkedName, arguments.count == 1, state.contains(.list, receiver) {
            let transformResult = module.arena.appendTemporary(type: nil
            )
            loweredBody.append(.call(
                callee: lookup.kkListChunkedBridgeName,
                arguments: [receiver] + arguments,
                result: transformResult,
                canThrow: false
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
                callee: lookup.kkListWindowedBridgeName,
                arguments: [receiver, arguments[0], oneExpr, zeroExpr],
                result: transformResult,
                canThrow: false
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
                callee: lookup.kkListWindowedBridgeName,
                arguments: [receiver, arguments[0], arguments[1], zeroExpr],
                result: transformResult,
                canThrow: false
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
                    callee: lookup.kkListWindowedBridgeName,
                    arguments: [receiver] + arguments,
                    result: transformResult,
                    canThrow: false
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
                callee: kkName,
                arguments: [receiver] + arguments,
                result: result,
                canThrow: false
            ))
            state.tagResult(.sequence, result)
            return true
        }

        if callee == lookup.toListName, arguments.isEmpty {
            if state.contains(.sequence, receiver) {
                if let result {
                    let toListResult = module.arena.appendTemporary(type: nil
                    )
                    loweredBody.append(.call(
                        callee: lookup.kkSequenceToListName,
                        arguments: [receiver],
                        result: toListResult,
                        canThrow: true
                    ))
                    state.tagListResult(result, temporary: toListResult)
                    loweredBody.append(.copy(from: toListResult, to: result))
                } else {
                    loweredBody.append(.call(
                        callee: lookup.kkSequenceToListName,
                        arguments: [receiver],
                        result: nil,
                        canThrow: true
                    ))
                }
                return true
            }
        }

        if callee == lookup.constrainOnceName, arguments.isEmpty, state.contains(.sequence, receiver) {
            loweredBody.append(.call(
                callee: lookup.kkSequenceConstrainOnceName,
                arguments: [receiver],
                result: result,
                canThrow: false
            ))
            state.tagResult(.sequence, result)
            return true
        }

        if callee == lookup.toSetName, arguments.isEmpty, state.contains(.sequence, receiver) {
            let toSetResult = module.arena.appendTemporary(type: nil
            )
            loweredBody.append(.call(
                callee: lookup.kkSequenceToSetName,
                arguments: [receiver],
                result: toSetResult,
                canThrow: false
            ))
            if let result {
                state.tagResult(.set, result, temporary: toSetResult)
                loweredBody.append(.copy(from: toSetResult, to: result))
            }
            return true
        }

        if callee == lookup.toMapName, arguments.isEmpty, state.contains(.sequence, receiver) {
            let toMapResult = module.arena.appendTemporary(type: nil
            )
            let thrownExpr = origThrownResult ?? module.arena.appendTemporary(type: nil)
            loweredBody.append(.call(
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

        if callee == lookup.flattenName, arguments.isEmpty, state.contains(.sequence, receiver) {
            loweredBody.append(.call(
                callee: lookup.kkSequenceFlattenName,
                arguments: [receiver],
                result: result,
                canThrow: false
            ))
            state.tagResult(.sequence, result)
            return true
        }

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

        let sequencePlusMinusCallees = SequencePlusMinusRuntimeCallees(
            plus: lookup.kkSequencePlusName,
            minus: lookup.kkSequenceMinusName,
            ofSingle: lookup.kkSequenceOfSingleName
        )

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

        if callee == lookup.plusElementName, arguments.count == 1, state.contains(.sequence, receiver) {
            loweredBody.append(.call(
                callee: lookup.kkSequencePlusElementName,
                arguments: [receiver, arguments[0]],
                result: result,
                canThrow: false
            ))
            state.tagResult(.sequence, result)
            return true
        }

        // Iterable.minusElement(element) returns a List, even when the receiver
        // is tracked through the generic Iterable interface.
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
}
