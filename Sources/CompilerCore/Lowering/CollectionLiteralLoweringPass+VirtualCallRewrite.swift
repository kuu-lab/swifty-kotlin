import RuntimeABI

extension CollectionVirtualCallRewriteLoweringPass {
    struct VirtualCallRewriteContext {
        let module: KIRModule
        let lookup: CollectionLiteralLookupTables
        let functionBody: [KIRInstruction]
        let sema: SemaModule?
        let interner: StringInterner
    }

    /// Returns true when the callee resolves to a bundled Kotlin source declaration
    /// that should not be rewritten to a runtime `kk_*` entry point.
    ///
    /// RF-LOWER-CALL-007 moved the decision into
    /// `SourceBackedCallPreservationPolicy`, which the construction pass shares:
    /// the 102 API names both paths preserved are one set there, and the names
    /// only virtual dispatch preserves (Range/progression members, `random`)
    /// are a second. What remains here is resolving the receiver's static type,
    /// which the policy deliberately cannot do.
    private func shouldPreserveSourceBackedVirtualCall(
        symbol: SymbolID?,
        callee: InternedString,
        receiver: KIRExprID,
        context: VirtualCallRewriteContext
    ) -> Bool {
        sourceBackedPreservation.preservesVirtualCall(
            callee: callee,
            resolution: SourceBackedCalleeResolution(symbol: symbol, sema: context.sema),
            receiverArrayClassName: {
                guard let sema = context.sema,
                      let receiverType = context.module.arena.exprType(receiver),
                      let (_, receiverSymbol) = resolveClassTypeSymbol(receiverType, sema: sema)
                else {
                    return nil
                }
                return context.interner.resolve(receiverSymbol.name)
            }
        )
    }

    func rewriteVirtualCallInstruction(
        symbol: SymbolID?,
        callee: InternedString,
        receiver: KIRExprID,
        arguments: [KIRExprID],
        result: KIRExprID?,
        origCanThrow: Bool,
        origThrownResult: KIRExprID?,
        context: VirtualCallRewriteContext,
        state: inout CollectionRewriteState,
        loweredBody: inout KIRLoweringEmitContext
    ) -> Bool {
        let module = context.module
        let lookup = context.lookup

        // Handle runtime-backed collection iterators before the generic
        // source-backed preservation rule. A source-backed Iterable shell can
        // make the iterator member look like ordinary Kotlin source, while
        // the concrete list value still requires the shared list iterator ABI.
        if callee == lookup.iteratorName,
           arguments.isEmpty,
           state.listExprIDs.contains(receiver.rawValue) || state.setExprIDs.contains(receiver.rawValue)
        {
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkListIteratorName,
                arguments: [receiver],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            if let result {
                state.listIteratorExprIDs.insert(result.rawValue)
            }
            return true
        }

        // Iterator builders return runtime boxes without an Iterator itable.
        // Keep their bridge calls direct even though Iterator itself is now
        // source-backed; user-defined Iterator implementations still use the
        // normal virtual dispatch path.
        if state.iteratorBuilderExprIDs.contains(receiver.rawValue) {
            let semanticMemberName = symbol
                .flatMap { context.sema?.symbols.symbol($0)?.name }
                ?? callee
            let bridgeCallee: InternedString?
            if semanticMemberName == context.interner.intern("hasNext") {
                bridgeCallee = lookup.kkIteratorBuilderHasNextName
            } else if semanticMemberName == context.interner.intern("next") {
                bridgeCallee = lookup.kkIteratorBuilderNextName
            } else {
                bridgeCallee = nil
            }
            if let bridgeCallee {
                loweredBody.append(.call(
                    symbol: nil,
                    callee: bridgeCallee,
                    arguments: [receiver] + arguments,
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return true
            }
        }

        if shouldPreserveSourceBackedVirtualCall(
            symbol: symbol,
            callee: callee,
            receiver: receiver,
            context: context
        ) {
            return false
        }

        // LOWERING-001: If the receiver is not in any tracking set yet,
        // attempt to classify it from its static type in the KIR arena.
        // This handles non-tracked receivers such as function parameters,
        // function return values, and field loads whose concrete collection
        // kind was not determined by the factory-call pre-scan.
        classifyReceiverByStaticType(
            receiver: receiver,
            context: context,
            state: &state
        )

        if rewriteSequenceVirtualCall(
            symbol: symbol,
            callee: callee, receiver: receiver, arguments: arguments,
            result: result, origCanThrow: origCanThrow,
            origThrownResult: origThrownResult, module: module, lookup: lookup,
            context: context,
            state: &state,
            loweredBody: &loweredBody
        ) { return true }

        if rewriteListHOFVirtualCall(
            callee: callee, receiver: receiver, arguments: arguments,
            result: result, origCanThrow: origCanThrow,
            origThrownResult: origThrownResult, context: context,
            state: &state,
            loweredBody: &loweredBody
        ) { return true }

        if rewriteCollectionPropertyVirtualCall(
            callee: callee, receiver: receiver, arguments: arguments,
            result: result, lookup: lookup,
            state: state,
            loweredBody: &loweredBody
        ) { return true }

        // Runtime collection boxes do not carry generated itables, so route
        // stdlib list/set iterator calls directly to the shared iterator helper.
        if callee == lookup.iteratorName,
           arguments.isEmpty,
           state.listExprIDs.contains(receiver.rawValue) || state.setExprIDs.contains(receiver.rawValue)
        {
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkListIteratorName,
                arguments: [receiver],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            if let result {
                state.listIteratorExprIDs.insert(result.rawValue)
            }
            return true
        }

        if rewriteRangeVirtualCall(
            callee: callee, receiver: receiver, arguments: arguments,
            result: result, origCanThrow: origCanThrow,
            origThrownResult: origThrownResult, module: module, lookup: lookup,
            sema: context.sema, interner: context.interner,
            state: &state,
            loweredBody: &loweredBody
        ) { return true }

        return false
    }

    private func rewriteListHOFVirtualCall(
        callee: InternedString,
        receiver: KIRExprID,
        arguments: [KIRExprID],
        result: KIRExprID?,
        origCanThrow: Bool,
        origThrownResult: KIRExprID?,
        context: VirtualCallRewriteContext,
        state: inout CollectionRewriteState,
        loweredBody: inout KIRLoweringEmitContext
    ) -> Bool {
        let module = context.module
        let lookup = context.lookup
        if rewriteCommonListHOF(
            callee: callee, receiver: receiver, arguments: arguments,
            result: result, origCanThrow: origCanThrow,
            origThrownResult: origThrownResult, module: module, lookup: lookup,
            state: &state, loweredBody: &loweredBody
        ) { return true }

        if rewriteDestinationCollectionHOF(
            callee: callee, receiver: receiver, arguments: arguments,
            result: result, origCanThrow: origCanThrow,
            origThrownResult: origThrownResult, context: context,
            state: &state, loweredBody: &loweredBody
        ) { return true }

        if rewriteGroupSortFindHOF(
            callee: callee, receiver: receiver, arguments: arguments,
            result: result, origCanThrow: origCanThrow,
            origThrownResult: origThrownResult, context: context,
            state: &state, loweredBody: &loweredBody
        ) { return true }

        if rewriteAssociateToHOF(
            callee: callee, receiver: receiver, arguments: arguments,
            result: result, origCanThrow: origCanThrow,
            origThrownResult: origThrownResult, context: context,
            state: &state, loweredBody: &loweredBody
        ) { return true }

        if rewriteZipUnzipAndIndexedHOF(
            callee: callee, receiver: receiver, arguments: arguments,
            result: result, origCanThrow: origCanThrow,
            origThrownResult: origThrownResult, module: module, lookup: lookup,
            state: &state, loweredBody: &loweredBody
        ) { return true }

        if rewriteCountFirstLastFoldReduceHOF(
            callee: callee, receiver: receiver, arguments: arguments,
            result: result, origCanThrow: origCanThrow,
            origThrownResult: origThrownResult, module: module, lookup: lookup,
            state: &state, loweredBody: &loweredBody
        ) { return true }

        return false
    }

    // RF-LOWER-CALL-012 dropped `rewriteMapHOF`, the virtual-dispatch sibling
    // of the direct-call Map branch removed from
    // `+CallRewriteHOFCore.swift` / `+CallRewriteHandlers.swift`. It matched
    // `map` / `filter` / `forEach` / `mapValues` / `mapKeys` / `filterKeys` /
    // `filterValues` on a tracked Map receiver and rewrote to `kk_map_*`, but
    // it could never fire: those names are all bundled Kotlin extension
    // functions (`MapHOF.kt`, KSP-430), so Sema always resolves a call to them
    // statically — CallLowerer never emits a `.virtualCall` for any of these
    // names, only `.call`, so no `.virtualCall` instruction ever reaches
    // `rewriteVirtualCallInstruction` (this file's entry point) with one of
    // these callees in the first place; `shouldPreserveSourceBackedVirtualCall`
    // above is a separate, `.call`-independent reason these names are inert
    // here. `MapHOFLoweringRoutingTests` includes probes through an interface
    // property and an abstract-class method (both of which do force real
    // `virtualCall` dispatch elsewhere in the same function) to pin that the
    // Map HOF calls themselves stay direct `.call`s.

    @discardableResult
    func emitHOFCall(
        kkName: InternedString,
        receiver: KIRExprID,
        arguments: [KIRExprID],
        result: KIRExprID?,
        origCanThrow: Bool,
        origThrownResult: KIRExprID?,
        module: KIRModule,
        loweredBody: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        let hofResult = module.arena.appendTemporary(type: nil
        )
        loweredBody.append(.call(
            symbol: nil,
            callee: kkName,
            arguments: [receiver] + arguments,
            result: hofResult,
            canThrow: origCanThrow,
            thrownResult: origThrownResult
        ))
        if let result {
            loweredBody.append(.copy(from: hofResult, to: result))
        }
        return hofResult
    }

    private func rewriteCommonListHOF(
        callee: InternedString,
        receiver: KIRExprID,
        arguments: [KIRExprID],
        result: KIRExprID?,
        origCanThrow: Bool,
        origThrownResult: KIRExprID?,
        module: KIRModule,
        lookup: CollectionLiteralLookupTables,
        state: inout CollectionRewriteState,
        loweredBody: inout KIRLoweringEmitContext
    ) -> Bool {
        guard callee == lookup.mapName || callee == lookup.mapNotNullName
            || callee == lookup.forEachName || callee == lookup.onEachName
            || callee == lookup.flatMapName || callee == lookup.flatMapIndexedName
            || callee == lookup.anyName || callee == lookup.noneName
            || callee == lookup.allName
            || callee == lookup.takeWhileName || callee == lookup.dropWhileName
            || callee == lookup.takeLastWhileName || callee == lookup.dropLastWhileName
        else { return false }
        guard arguments.count == 1, state.listExprIDs.contains(receiver.rawValue),
              let kkName = lookup.collectionHOFRuntimeName(ownerKind: .list, callee: callee, arity: 1)
        else { return false }
        let needsListTag = callee == lookup.mapName
            || callee == lookup.mapNotNullName
            || callee == lookup.flatMapName
            || callee == lookup.onEachName
            || callee == lookup.takeWhileName || callee == lookup.dropWhileName
            || callee == lookup.takeLastWhileName || callee == lookup.dropLastWhileName
        let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
        loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
        let hofResult = emitHOFCall(
            kkName: kkName, receiver: receiver, arguments: arguments + [zeroExpr],
            result: result, origCanThrow: origCanThrow,
            origThrownResult: origThrownResult, module: module,
            loweredBody: &loweredBody
        )
        if needsListTag, let result {
            state.listExprIDs.insert(result.rawValue)
            state.listExprIDs.insert(hofResult.rawValue)
        }
        return true
    }

    private func rewriteGroupSortFindHOF(
        callee: InternedString,
        receiver: KIRExprID,
        arguments: [KIRExprID],
        result: KIRExprID?,
        origCanThrow: Bool,
        origThrownResult: KIRExprID?,
        context: VirtualCallRewriteContext,
        state: inout CollectionRewriteState,
        loweredBody: inout KIRLoweringEmitContext
    ) -> Bool {
        let module = context.module
        let lookup = context.lookup
        guard callee == lookup.groupByName
            || callee == lookup.associateByName || callee == lookup.associateWithName || callee == lookup.associateName
        else {
            return false
        }
        guard arguments.count == 1,
              state.listExprIDs.contains(receiver.rawValue)
        else { return false }

        let kkName: InternedString = switch callee {
        case lookup.groupByName: lookup.kkListGroupByName
        case lookup.associateByName: lookup.kkListAssociateByName
        case lookup.associateWithName: lookup.kkListAssociateWithName
        case lookup.associateName: lookup.kkListAssociateName
        default: callee
        }

        var hofArgs = arguments
        if callee != lookup.groupByName {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            hofArgs.append(zeroExpr)
        }

        let hofResult = emitHOFCall(
            kkName: kkName, receiver: receiver, arguments: hofArgs,
            result: result, origCanThrow: origCanThrow,
            origThrownResult: origThrownResult, module: module,
            loweredBody: &loweredBody
        )

        if callee == lookup.groupByName, let result {
            state.mapExprIDs.insert(result.rawValue)
            state.mapExprIDs.insert(hofResult.rawValue)
        }
        if callee == lookup.associateByName || callee == lookup.associateWithName || callee == lookup.associateName,
           let result
        {
            state.mapExprIDs.insert(result.rawValue)
            state.mapExprIDs.insert(hofResult.rawValue)
        }
        return true
    }

    // STDLIB-021: toCollection and destination collection HOFs
    private func rewriteDestinationCollectionHOF(
        callee: InternedString,
        receiver: KIRExprID,
        arguments: [KIRExprID],
        result: KIRExprID?,
        origCanThrow: Bool,
        origThrownResult: KIRExprID?,
        context: VirtualCallRewriteContext,
        state: inout CollectionRewriteState,
        loweredBody: inout KIRLoweringEmitContext
    ) -> Bool {
        let module = context.module
        let lookup = context.lookup

        if callee == lookup.toCollectionName {
            guard arguments.count == 1 else {
                return false
            }

            let destID = arguments[0]
            let kkName: InternedString
            if state.listExprIDs.contains(receiver.rawValue) {
                kkName = lookup.kkCollectionToCollectionName
            } else if state.sequenceExprIDs.contains(receiver.rawValue) {
                kkName = lookup.kkSequenceToCollectionName
            } else {
                return false
            }
            let hofResult = emitHOFCall(
                kkName: kkName,
                receiver: receiver,
                arguments: [destID],
                result: result,
                origCanThrow: false,
                origThrownResult: nil,
                module: module,
                loweredBody: &loweredBody
            )
            if let result, state.listExprIDs.contains(destID.rawValue) {
                state.listExprIDs.insert(result.rawValue)
                state.listExprIDs.insert(hofResult.rawValue)
            }
            return true
        }

        guard callee == lookup.mapToName || callee == lookup.flatMapToName
            || callee == lookup.mapNotNullToName || callee == lookup.mapIndexedToName
            || callee == lookup.mapIndexedNotNullToName
            || callee == lookup.flatMapIndexedToName || callee == lookup.associateToName
        else {
            return false
        }

        guard arguments.count == 2 || arguments.count == 3,
              state.listExprIDs.contains(receiver.rawValue)
        else {
            return false
        }

        let destID = arguments[0]
        let lambdaID = arguments[1]
        let closureRawExpr: KIRExprID
        if arguments.count == 3 {
            closureRawExpr = arguments[2]
        } else {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            closureRawExpr = zeroExpr
        }

        guard let kkName = lookup.collectionHOFRuntimeName(ownerKind: .list, callee: callee, arity: 2) else {
            return false
        }

        let hofResult = emitHOFCall(
            kkName: kkName,
            receiver: receiver,
            arguments: [destID, lambdaID, closureRawExpr],
            result: result,
            origCanThrow: origCanThrow,
            origThrownResult: origThrownResult,
            module: module,
            loweredBody: &loweredBody
        )
        if let result {
            if state.listExprIDs.contains(destID.rawValue) {
                state.listExprIDs.insert(result.rawValue)
                state.listExprIDs.insert(hofResult.rawValue)
            } else if state.mapExprIDs.contains(destID.rawValue) {
                state.mapExprIDs.insert(result.rawValue)
                state.mapExprIDs.insert(hofResult.rawValue)
            }
        }
        return true
    }

    // STDLIB-SEQ-023 / STDLIB-535/536/537: associateByTo / associateWithTo / groupByTo
    private func rewriteAssociateToHOF(
        callee: InternedString,
        receiver: KIRExprID,
        arguments: [KIRExprID],
        result: KIRExprID?,
        origCanThrow: Bool,
        origThrownResult: KIRExprID?,
        context: VirtualCallRewriteContext,
        state: inout CollectionRewriteState,
        loweredBody: inout KIRLoweringEmitContext
    ) -> Bool {
        let module = context.module
        let lookup = context.lookup
        guard callee == lookup.associateByToName || callee == lookup.associateWithToName
            || callee == lookup.groupByToName
        else {
            return false
        }
        // arguments: [destination, lambda] or [destination, lambda, closureRaw]
        guard arguments.count == 2 || arguments.count == 3,
              state.listExprIDs.contains(receiver.rawValue)
        else { return false }

        let destID = arguments[0]
        let lambdaID = arguments[1]

        let closureRawExpr: KIRExprID
        if arguments.count == 3 {
            closureRawExpr = arguments[2]
        } else {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            closureRawExpr = zeroExpr
        }

        let kkName: InternedString = switch callee {
        case lookup.associateByToName: lookup.kkListAssociateByToName
        case lookup.associateWithToName: lookup.kkListAssociateWithToName
        case lookup.groupByToName: lookup.kkListGroupByToName
        default: callee
        }

        let hofResult = emitHOFCall(
            kkName: kkName, receiver: receiver,
            arguments: [destID, lambdaID, closureRawExpr],
            result: result, origCanThrow: origCanThrow,
            origThrownResult: origThrownResult, module: module,
            loweredBody: &loweredBody
        )
        if let result {
            state.mapExprIDs.insert(result.rawValue)
            state.mapExprIDs.insert(hofResult.rawValue)
        }
        return true
    }

    private func rewriteZipUnzipAndIndexedHOF(
        callee: InternedString,
        receiver: KIRExprID,
        arguments: [KIRExprID],
        result: KIRExprID?,
        origCanThrow: Bool,
        origThrownResult: KIRExprID?,
        module: KIRModule,
        lookup: CollectionLiteralLookupTables,
        state: inout CollectionRewriteState,
        loweredBody: inout KIRLoweringEmitContext
    ) -> Bool {
        guard state.listExprIDs.contains(receiver.rawValue) else { return false }

        if callee == lookup.zipName, arguments.count == 1 {
            let hofResult = module.arena.appendTemporary(type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkListZipBridgeName,
                arguments: [receiver] + arguments,
                result: hofResult,
                canThrow: false,
                thrownResult: nil
            ))
            if let result {
                state.listExprIDs.insert(result.rawValue)
                state.listExprIDs.insert(hofResult.rawValue)
                loweredBody.append(.copy(from: hofResult, to: result))
            }
            return true
        }

        if callee == lookup.zipName, arguments.count == 2 || arguments.count == 3 {
            let otherID = arguments[0]
            let lambdaID = arguments[1]
            let closureRawID: KIRExprID
            if arguments.count == 3 {
                closureRawID = arguments[2]
            } else {
                let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
                loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                closureRawID = zeroExpr
            }
            let hofResult = module.arena.appendTemporary(type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkListZipTransformBridgeName,
                arguments: [receiver, otherID, lambdaID, closureRawID],
                result: hofResult,
                canThrow: origCanThrow,
                thrownResult: origThrownResult
            ))
            if let result {
                state.listExprIDs.insert(result.rawValue)
                state.listExprIDs.insert(hofResult.rawValue)
                loweredBody.append(.copy(from: hofResult, to: result))
            }
            return true
        }

        // zipWithNext() — no-arg
        if callee == lookup.zipWithNextName, arguments.isEmpty {
            let hofResult = module.arena.appendTemporary(type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkListZipWithNextBridgeName,
                arguments: [receiver],
                result: hofResult,
                canThrow: false,
                thrownResult: nil
            ))
            if let result {
                state.listExprIDs.insert(result.rawValue)
                state.listExprIDs.insert(hofResult.rawValue)
                loweredBody.append(.copy(from: hofResult, to: result))
            }
            return true
        }

        // zipWithNext(transform) — HOF
        if callee == lookup.zipWithNextName, arguments.count == 1 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            let hofResult = emitHOFCall(
                kkName: lookup.kkListZipWithNextTransformBridgeName,
                receiver: receiver,
                arguments: arguments + [zeroExpr],
                result: result,
                origCanThrow: origCanThrow,
                origThrownResult: origThrownResult,
                module: module,
                loweredBody: &loweredBody
            )
            if let result {
                state.listExprIDs.insert(result.rawValue)
                state.listExprIDs.insert(hofResult.rawValue)
            }
            return true
        }

        // KSP-626: withIndex / forEachIndexed are bundled Kotlin source, not bridges.
        if callee == lookup.mapIndexedName
            || callee == lookup.mapIndexedNotNullName || callee == lookup.onEachIndexedName
            || callee == lookup.flatMapIndexedName,
            arguments.count == 1,
            let kkName = lookup.collectionHOFRuntimeName(ownerKind: .list, callee: callee, arity: 1) {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            let hofResult = emitHOFCall(
                kkName: kkName,
                receiver: receiver,
                arguments: arguments + [zeroExpr],
                result: result,
                origCanThrow: origCanThrow,
                origThrownResult: origThrownResult,
                module: module,
                loweredBody: &loweredBody
            )
            if callee == lookup.mapIndexedName || callee == lookup.mapIndexedNotNullName
                || callee == lookup.onEachIndexedName || callee == lookup.flatMapIndexedName,
                let result {
                state.listExprIDs.insert(result.rawValue)
                state.listExprIDs.insert(hofResult.rawValue)
            }
            return true
        }

        if callee == lookup.unzipName, arguments.isEmpty {
            let hofResult = module.arena.appendTemporary(type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkListUnzipName,
                arguments: [receiver],
                result: hofResult,
                canThrow: false,
                thrownResult: nil
            ))
            if let result {
                loweredBody.append(.copy(from: hofResult, to: result))
            }
            return true
        }

        return false
    }

    private func rewriteCountFirstLastFoldReduceHOF(
        callee: InternedString,
        receiver: KIRExprID,
        arguments: [KIRExprID],
        result: KIRExprID?,
        origCanThrow: Bool,
        origThrownResult: KIRExprID?,
        module: KIRModule,
        lookup: CollectionLiteralLookupTables,
        state: inout CollectionRewriteState,
        loweredBody: inout KIRLoweringEmitContext
    ) -> Bool {
        guard state.listExprIDs.contains(receiver.rawValue) else { return false }

        if callee == lookup.partitionName, arguments.count == 1 {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            _ = emitHOFCall(
                kkName: lookup.kkListPartitionName, receiver: receiver, arguments: arguments + [zeroExpr],
                result: result, origCanThrow: origCanThrow,
                origThrownResult: origThrownResult, module: module,
                loweredBody: &loweredBody
            )
            return true
        }

        return false
    }

    func supportsIterableWindowedTransformReceiver(
        receiver: KIRExprID,
        context: VirtualCallRewriteContext,
        listExprIDs: Set<Int32>,
        setExprIDs: Set<Int32>,
        arrayExprIDs: Set<Int32>
    ) -> Bool {
        let raw = receiver.rawValue
        if listExprIDs.contains(raw) || setExprIDs.contains(raw) || arrayExprIDs.contains(raw) {
            return true
        }
        guard let sema = context.sema,
              let typeID = context.module.arena.exprType(receiver)
        else {
            return false
        }
        guard let (_, symbol) = resolveClassTypeSymbol(typeID, sema: sema),
              let simpleName = symbol.fqName.last
        else {
            return false
        }
        switch context.interner.resolve(simpleName) {
        case "Iterable", "Collection", "MutableCollection":
            return true
        default:
            return false
        }
    }

    private func classifyReceiverByStaticType(
        receiver: KIRExprID,
        context: VirtualCallRewriteContext,
        state: inout CollectionRewriteState
    ) {
        let raw = receiver.rawValue
        // Already classified -- skip.
        if state.listExprIDs.contains(raw) || state.setExprIDs.contains(raw)
            || state.mapExprIDs.contains(raw) || state.arrayExprIDs.contains(raw)
            || state.sequenceExprIDs.contains(raw) || state.sequenceTypeExprIDs.contains(raw)
        {
            return
        }
        guard let sema = context.sema else { return }
        guard let typeID = context.module.arena.exprType(receiver) else { return }

        let types = sema.types
        let symbols = sema.symbols
        let interner = context.interner

        let kind = types.kind(of: typeID)
        guard case let .classType(classType) = kind else { return }
        let classSymbol = classType.classSymbol
        guard let symInfo = symbols.symbol(classSymbol) else { return }

        switch trackedStaticTypeKind(of: symInfo, interner: interner) {
        case .list:
            state.listExprIDs.insert(raw)
        case .set:
            state.setExprIDs.insert(raw)
        case .map:
            state.mapExprIDs.insert(raw)
        case .array:
            state.arrayExprIDs.insert(raw)
        case .sequence:
            // RF-LOWER-STATE-009: the static type alone does not confirm a
            // RuntimeSequenceBox — see Classification.sequence's doc. Do not
            // insert into `sequenceExprIDs`, which +VirtualCallRewrite+Sequence.swift
            // reads as "confirmed runtime box" to decide whether to rewrite
            // to a `kk_sequence_*` bridge.
            state.sequenceTypeExprIDs.insert(raw)
        case .string:
            break
        case nil:
            break
        }
    }

}
