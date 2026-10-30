
extension CollectionLiteralLoweringSupport {
    func collectInitialCollectionExprIDs(
        function: KIRFunction,
        lookup: CollectionLiteralLookupTables,
        arena: KIRArena,
        sema: SemaModule?,
        interner: StringInterner,
        state: inout CollectionRewriteState
    ) {
        seedCollectionExprIDsFromStaticTypes(
            function: function,
            lookup: lookup,
            arena: arena,
            sema: sema,
            state: &state
        )

        var charValuedExprIDs: Set<Int32> = []
        var ulongValuedExprIDs: Set<Int32> = []
        for instruction in function.body {
            switch instruction {
            case let .call(_, callee, _, result, _, _, _, _):
                if callee == lookup.kkBoxCharName, let result {
                    charValuedExprIDs.insert(result.rawValue)
                }
            case let .constValue(result, .charLiteral):
                charValuedExprIDs.insert(result.rawValue)
            case let .constValue(result, .ulongLiteral):
                ulongValuedExprIDs.insert(result.rawValue)
            case let .copy(from, to):
                if charValuedExprIDs.contains(from.rawValue) {
                    charValuedExprIDs.insert(to.rawValue)
                }
                if ulongValuedExprIDs.contains(from.rawValue) {
                    ulongValuedExprIDs.insert(to.rawValue)
                }
            default:
                break
            }
        }

        if let sema {
            seedULongValuedExprIDsFromStaticTypes(
                function: function,
                arena: arena,
                sema: sema,
                ulongValuedExprIDs: &ulongValuedExprIDs
            )
        }

        for instruction in function.body {
            switch instruction {
            case let .call(symbol, callee, arguments, result, _, _, _, _):
                handleCallInstruction(
                    symbol: symbol, callee: callee, arguments: arguments, result: result,
                    arena: arena, sema: sema, interner: interner,
                    lookup: lookup, charValuedExprIDs: charValuedExprIDs,
                    ulongValuedExprIDs: ulongValuedExprIDs,
                    state: &state
                )
            case let .virtualCall(symbol, callee, receiver, _, result, _, _, _):
                handleVirtualCallInstruction(
                    symbol: symbol, callee: callee, receiver: receiver, result: result,
                    lookup: lookup, sema: sema,
                    state: &state
                )
            case let .copy(from, to):
                state.seedCopy(from: from, to: to)
                // Branches of an `if`/`when` that reuse the same expression
                // slot can each seed a different, mutually exclusive
                // Sequence provenance; the union above cannot tell that
                // apart from agreeing evidence (RF-LOWER-STATE-009).
                state.resolveSequenceProvenanceConflicts(at: to)
            case let .constValue(result, .stringLiteral):
                state.stringExprIDs.insert(result.rawValue)
            default:
                break
            }
        }
    }

    private func handleCallInstruction(
        symbol: SymbolID?,
        callee: InternedString,
        arguments: [KIRExprID],
        result: KIRExprID?,
        arena: KIRArena,
        sema: SemaModule?,
        interner: StringInterner,
        lookup: CollectionLiteralLookupTables,
        charValuedExprIDs: Set<Int32>,
        ulongValuedExprIDs: Set<Int32>,
        state: inout CollectionRewriteState
    ) {
        classifyFactoryCall(
            symbol: symbol, callee: callee, result: result, lookup: lookup,
            arena: arena, sema: sema, interner: interner,
            state: &state
        )
        if let result,
           callee == lookup.kkOpRangeToName || callee == lookup.kkOpRangeUntilName
           || callee == lookup.kkOpULongRangeUntilName
           || callee == lookup.kkOpDownToName || callee == lookup.kkOpStepName
        {
            state.rangeExprIDs.insert(result.rawValue)
            if arguments.contains(where: { charValuedExprIDs.contains($0.rawValue) }) {
                state.charRangeExprIDs.insert(result.rawValue)
            }
            if arguments.contains(where: { ulongValuedExprIDs.contains($0.rawValue) }) {
                state.ulongRangeExprIDs.insert(result.rawValue)
            }
            if callee == lookup.kkOpStepName, !arguments.isEmpty,
               state.charRangeExprIDs.contains(arguments[0].rawValue)
            {
                state.charRangeExprIDs.insert(result.rawValue)
            }
            if callee == lookup.kkOpStepName, !arguments.isEmpty,
               state.ulongRangeExprIDs.contains(arguments[0].rawValue)
            {
                state.ulongRangeExprIDs.insert(result.rawValue)
            }
        }
        if let result, lookup.stringProducingCallees.contains(callee) {
            state.stringExprIDs.insert(result.rawValue)
        }
        // KSP-441: Sequence factories whose source body is just a bridge to a
        // runtime __kk_* / kk_* entry return a RuntimeSequenceBox handle.  Track
        // those results so source Sequence HOFs route to the runtime helpers.
        if let result, lookup.sequenceRuntimeBridgeReturningNames.contains(callee) {
            state.sequenceExprIDs.insert(result.rawValue)
        }
        // KUU-3850: The public `kotlin.sequences` factories cannot join the
        // name set above because `generateSequence` is overload-sensitive —
        // its `(seedFunction, nextFunction)` overload constructs a source
        // `object : Sequence` while every other overload returns the
        // RuntimeSequenceBox produced by private `__kk_sequence_*` bridges.
        // Classify them from the resolved declaration instead.
        if let result, let sema, let symbol,
           let decl = sema.symbols.symbol(symbol),
           let classification = classifySequenceFactoryDecl(
               decl,
               symbol: symbol,
               sema: sema,
               interner: interner
           )
        {
            switch classification {
            case .sequence:
                state.sequenceExprIDs.insert(result.rawValue)
            case .sequenceSourceObject:
                state.sequenceSourceObjectExprIDs.insert(result.rawValue)
            default:
                break
            }
        }
        propagateCollectionOperation(
            callee: callee, arguments: arguments, result: result, lookup: lookup,
            state: &state
        )
        // KSP-453: Source-backed IntRange/IntProgression HOFs are emitted as
        // ordinary .call instructions. Track their results so downstream list
        // operations (size, isEmpty, etc.) still lower correctly.
        if let result, !arguments.isEmpty, state.rangeExprIDs.contains(arguments[0].rawValue) {
            let listProducingRangeHOFs: Set<InternedString> = [
                lookup.toListName, lookup.mapName, lookup.mapIndexedName, lookup.mapNotNullName,
                lookup.filterName, lookup.filterIndexedName, lookup.filterNotName,
                lookup.chunkedName, lookup.windowedName, lookup.takeName, lookup.dropName, lookup.sortedName,
            ]
            if listProducingRangeHOFs.contains(callee) {
                state.listExprIDs.insert(result.rawValue)
            }
        }
    }

    private func classifyFactoryCall(
        symbol: SymbolID?,
        callee: InternedString,
        result: KIRExprID?,
        lookup: CollectionLiteralLookupTables,
        arena: KIRArena,
        sema: SemaModule?,
        interner: StringInterner,
        state: inout CollectionRewriteState
    ) {
        guard let result else { return }
        let mutableMapConstructorName = stdlibMutableMapConstructorName(
            symbol: symbol,
            callee: callee,
            result: result,
            lookup: lookup,
            arena: arena,
            sema: sema,
            interner: interner
        )
        if lookup.mutableSetConstructorNames.contains(callee),
           !isStdlibCollectionConstructor(
               symbol: symbol, className: callee, result: result,
               arena: arena, sema: sema, interner: interner
           ) {
            return
        }
        if lookup.mutableMapConstructorNames.contains(callee), mutableMapConstructorName == nil {
            return
        }
        if lookup.listFactoryNames.contains(callee) || lookup.mutableListConstructorNames.contains(callee)
            || callee == lookup.kkListOfName
            || callee == lookup.kkArrayListOfName
            || callee == lookup.kkStringSplitName
            || callee == lookup.kkArrayToListName
        {
            state.listExprIDs.insert(result.rawValue)
        } else if lookup.setFactoryNames.contains(callee) || lookup.mutableSetConstructorNames.contains(callee)
                    || callee == lookup.kkSetOfName
                    || callee == lookup.kkLinkedHashSetOfName
                    || callee == lookup.kkSetOfNotNullName
                    // java.util.TreeSet construction and the sortedSetOf factory
                    // produce RuntimeSetBox results — KUU-1361.
                    || callee == lookup.treeSetName
                    || callee == lookup.sortedSetOfName
                    || callee == lookup.kkTreeSetNewName
                    || callee == lookup.kkTreeSetNewCollectionName
                    || callee == lookup.kkTreeSetNewSortedSetName {
            state.setExprIDs.insert(result.rawValue)
        } else if lookup.mapFactoryNames.contains(callee) || mutableMapConstructorName != nil
                    || callee == lookup.kkMapOfName
                    // java.util.TreeMap construction and the sortedMapOf
                    // factory produce RuntimeMapBox results — KUU-1361.
                    || callee == lookup.treeMapName
                    || callee == lookup.sortedMapOfName
                    || callee == lookup.kkTreeMapNewName
                    || callee == lookup.kkTreeMapNewMapName
                    || callee == lookup.kkTreeMapNewSortedMapName {
            state.mapExprIDs.insert(result.rawValue)
        } else if lookup.arrayOfFactoryNames.contains(callee)
            || callee == lookup.kkArrayNewName
            // CallLowerer may already lower intArrayOf/arrayOf to kk_array_of before this pass.
            || callee == lookup.kkArrayOfName
        {
            state.arrayExprIDs.insert(result.rawValue)
        }
    }

    /// Symbol-level classification for the public `kotlin.sequences`
    /// factories, which are overload-sensitive and therefore cannot live in
    /// `sequenceRuntimeBridgeReturningNames` (KUU-3850):
    ///  - `generateSequence`: only `(seedFunction: () -> T?, nextFunction)`
    ///    constructs a source `object : Sequence`; it is the two-parameter
    ///    overload whose first parameter is function-typed. Every other
    ///    overload delegates to a private `__kk_sequence_*` bridge and returns
    ///    a RuntimeSequenceBox.
    ///  - `sequenceOf` / `emptySequence`: all overloads return a box.
    ///  - `Sequence { iterator() }`: constructs `object : Sequence`.
    private func classifySequenceFactoryDecl(
        _ decl: SemanticSymbol,
        symbol: SymbolID,
        sema: SemaModule,
        interner: StringInterner
    ) -> CollectionLiteralLoweringSupport.Classification? {
        guard decl.kind == .function,
              decl.fqName.count == 3,
              decl.fqName[0] == interner.intern("kotlin"),
              decl.fqName[1] == interner.intern("sequences")
        else {
            return nil
        }
        let simpleName = decl.fqName[2]
        if simpleName == interner.intern("generateSequence") {
            if let signature = sema.symbols.functionSignature(for: symbol),
               signature.parameterTypes.count == 2,
               let firstParameter = signature.parameterTypes.first,
               case .functionType = sema.types.kind(of: firstParameter)
            {
                return .sequenceSourceObject
            }
            return .sequence
        }
        if simpleName == interner.intern("sequenceOf")
            || simpleName == interner.intern("emptySequence")
        {
            return .sequence
        }
        if simpleName == interner.intern("Sequence") {
            return .sequenceSourceObject
        }
        return nil
    }

    private func propagateCollectionOperation(
        callee: InternedString,
        arguments: [KIRExprID],
        result: KIRExprID?,
        lookup: CollectionLiteralLookupTables,
        state: inout CollectionRewriteState
    ) {
        guard let result, !arguments.isEmpty else { return }
        let src = arguments[0].rawValue
        // KSP-441〜447: Sequence パイプラインは source 化済み。runtime sequence handle の追跡は不要。
        if callee == lookup.groupByName || callee == lookup.associateByName
            || callee == lookup.associateWithName || callee == lookup.associateName
            || callee == lookup.associateByToName || callee == lookup.associateWithToName
            || callee == lookup.groupByToName,
            state.listExprIDs.contains(src)
        {
            state.mapExprIDs.insert(result.rawValue)
        } else if callee == lookup.mapName, state.mapExprIDs.contains(src) {
            state.listExprIDs.insert(result.rawValue)
        } else if callee == lookup.filterName, state.mapExprIDs.contains(src) {
            state.mapExprIDs.insert(result.rawValue)
        } else if callee == lookup.mapValuesName || callee == lookup.mapKeysName
                    || callee == lookup.filterKeysName || callee == lookup.filterValuesName,
                  state.mapExprIDs.contains(src) {
            state.mapExprIDs.insert(result.rawValue)
        } else if callee == lookup.toListName, state.mapExprIDs.contains(src) {
            state.listExprIDs.insert(result.rawValue)
        } else if callee == lookup.takeName || callee == lookup.dropName
            || callee == lookup.reversedName || callee == lookup.asReversedName || callee == lookup.sortedName || callee == lookup.distinctName
            || callee == lookup.shuffledName
            || callee == lookup.scanName || callee == lookup.runningFoldName,
            state.listExprIDs.contains(src)
        {
            state.listExprIDs.insert(result.rawValue)
        }
        // withIndex returns IndexingIterable, not List — do not add to state.listExprIDs
    }

    private func handleVirtualCallInstruction(
        symbol: SymbolID?,
        callee: InternedString,
        receiver: KIRExprID,
        result: KIRExprID?,
        lookup: CollectionLiteralLookupTables,
        sema: SemaModule?,
        state: inout CollectionRewriteState
    ) {
        if callee == lookup.asSequenceName
        {
            if let result {
                let isSourceBacked = {
                    guard let sema, let symbol, sema.symbols.symbol(symbol) != nil else { return false }
                    return sema.symbols.isSourceBackedSymbol(symbol)
                }()
                if !isSourceBacked {
                    state.sequenceExprIDs.insert(result.rawValue)
                } else if let sema, let symbol,
                          isKnownSourceObjectConstructingAsSequenceReceiver(
                              symbol: symbol, sema: sema, lookup: lookup
                          )
                {
                    // Confirmed by reading the resolved overload's body
                    // (Iterable/Iterator/CharSequence/Map.asSequence): it
                    // constructs a fresh source `object : Sequence<T>`.
                    // Array's overload and the Sequence identity overload
                    // are deliberately excluded — see the helper's doc.
                    state.sequenceSourceObjectExprIDs.insert(result.rawValue)
                }
            }
            return
        }
        if callee == lookup.kkStringSplitName
        {
            if let result { state.listExprIDs.insert(result.rawValue) }
            return
        }

        let receiverRaw = receiver.rawValue
        if state.sequenceExprIDs.contains(receiverRaw) {
            if callee == lookup.toListName {
                if let result { state.listExprIDs.insert(result.rawValue) }
            } else if callee == lookup.mapName || callee == lookup.filterName || callee == lookup.takeName
                || callee == lookup.flatMapName || callee == lookup.flatMapIndexedName || callee == lookup.dropName
                || callee == lookup.distinctName || callee == lookup.zipName
                || callee == lookup.shuffledName
            {
                if let result { state.sequenceExprIDs.insert(result.rawValue) }
            }
            return
        }

        if state.mapExprIDs.contains(receiverRaw) {
            if callee == lookup.mapName || callee == lookup.toListName {
                if let result { state.listExprIDs.insert(result.rawValue) }
            } else if callee == lookup.filterName || callee == lookup.mapValuesName || callee == lookup.mapKeysName
                        || callee == lookup.filterKeysName || callee == lookup.filterValuesName {
                if let result { state.mapExprIDs.insert(result.rawValue) }
            }
            return
        }

        if state.listExprIDs.contains(receiverRaw) {
            if callee == lookup.groupByName || callee == lookup.associateByName
                || callee == lookup.associateWithName || callee == lookup.associateName
                || callee == lookup.associateByToName || callee == lookup.associateWithToName
                || callee == lookup.groupByToName
            {
                if let result { state.mapExprIDs.insert(result.rawValue) }
            } else if callee == lookup.takeName || callee == lookup.dropName
                || callee == lookup.reversedName || callee == lookup.asReversedName || callee == lookup.sortedName || callee == lookup.distinctName
                || callee == lookup.shuffledName
                || callee == lookup.scanName || callee == lookup.runningFoldName
            {
                if let result { state.listExprIDs.insert(result.rawValue) }
            }
            // withIndex returns IndexingIterable, not List — do not add to state.listExprIDs
        }

        if state.rangeExprIDs.contains(receiverRaw) {
            if callee == lookup.reversedName {
                if let result {
                    state.rangeExprIDs.insert(result.rawValue)
                    if state.charRangeExprIDs.contains(receiverRaw) {
                        state.charRangeExprIDs.insert(result.rawValue)
                    }
                    if state.ulongRangeExprIDs.contains(receiverRaw) {
                        state.ulongRangeExprIDs.insert(result.rawValue)
                    }
                }
            } else if callee == lookup.toListName || callee == lookup.mapName {
                if let result { state.listExprIDs.insert(result.rawValue) }
            }
        }

        if state.stringExprIDs.contains(receiverRaw) {
            if callee == lookup.mapName || callee == lookup.filterName, let result {
                state.stringExprIDs.insert(result.rawValue)
            }
        }
    }

    private func collectReferencedExprIDs(function: KIRFunction) -> Set<Int32> {
        var referencedExprIDs: Set<Int32> = []
        for instruction in function.body {
            switch instruction {
            case let .call(_, _, arguments, result, _, _, _, _):
                for arg in arguments { referencedExprIDs.insert(arg.rawValue) }
                if let result { referencedExprIDs.insert(result.rawValue) }
            case let .virtualCall(_, _, receiver, arguments, result, _, _, _):
                referencedExprIDs.insert(receiver.rawValue)
                for arg in arguments { referencedExprIDs.insert(arg.rawValue) }
                if let result { referencedExprIDs.insert(result.rawValue) }
            case let .copy(from, to):
                referencedExprIDs.insert(from.rawValue)
                referencedExprIDs.insert(to.rawValue)
            case let .constValue(result, _):
                referencedExprIDs.insert(result.rawValue)
            case let .returnValue(expr):
                referencedExprIDs.insert(expr.rawValue)
            default:
                break
            }
        }
        return referencedExprIDs
    }

    /// Handles expressions whose concrete collection kind cannot be determined
    /// from factory/call patterns alone, such as function parameters typed as
    /// `List<T>` or return values from user-defined functions returning
    /// `Set<T>`.
    private func seedCollectionExprIDsFromStaticTypes(
        function: KIRFunction,
        lookup: CollectionLiteralLookupTables,
        arena: KIRArena,
        sema: SemaModule?,
        state: inout CollectionRewriteState
    ) {
        guard let sema else { return }
        let types = sema.types
        let symbols = sema.symbols

        let referencedExprIDs = collectReferencedExprIDs(function: function)

        for rawID in referencedExprIDs {
            let exprID = KIRExprID(rawValue: rawID)
            guard let typeID = arena.exprType(exprID) else { continue }
            // Already classified by factory-call scan — skip.
            if state.listExprIDs.contains(rawID) || state.setExprIDs.contains(rawID)
                || state.mapExprIDs.contains(rawID) || state.arrayExprIDs.contains(rawID)
                || state.sequenceExprIDs.contains(rawID) || state.stringExprIDs.contains(rawID)
                || state.sequenceTypeExprIDs.contains(rawID)
            {
                continue
            }
            classifyExprByTypeID(
                expr: exprID, typeID: typeID,
                types: types, symbols: symbols, lookup: lookup,
                state: &state
            )
        }
    }

    private func seedULongValuedExprIDsFromStaticTypes(
        function: KIRFunction,
        arena: KIRArena,
        sema: SemaModule,
        ulongValuedExprIDs: inout Set<Int32>
    ) {
        let referencedExprIDs = collectReferencedExprIDs(function: function)

        for rawID in referencedExprIDs {
            let exprID = KIRExprID(rawValue: rawID)
            guard let typeID = arena.exprType(exprID),
                  sema.types.makeNonNullable(typeID) == sema.types.ulongType
            else {
                continue
            }
            ulongValuedExprIDs.insert(rawID)
        }
    }

    private func classifyExprByTypeID(
        expr: KIRExprID,
        typeID: TypeID,
        types: TypeSystem,
        symbols: SymbolTable,
        lookup: CollectionLiteralLookupTables,
        state: inout CollectionRewriteState
    ) {
        let kind = types.kind(of: typeID)
        if case .stringStruct = kind {
            state.tag(expr, as: .string)
            return
        }
        guard case let .classType(classType) = kind else { return }

        let classSymbol = classType.classSymbol
        guard let symInfo = symbols.symbol(classSymbol),
              let trackedKind = trackedStaticTypeKind(of: symInfo, lookup: lookup)
        else {
            return
        }
        state.tag(expr, as: trackedKind)
    }
}
