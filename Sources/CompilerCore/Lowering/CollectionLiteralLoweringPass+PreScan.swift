
extension CollectionLiteralLoweringSupport {
    func collectBuilderLambdaKinds(
        module: KIRModule,
        lookup: CollectionLiteralLookupTables,
        ctx: KIRContext
    ) -> [InternedString: InternedString] {
        var symbolToFuncName: [SymbolID: InternedString] = [:]
        for decl in module.arena.declarations {
            if case let .function(funcDecl) = decl {
                symbolToFuncName[funcDecl.symbol] = funcDecl.name
            }
        }

        var builderLambdaKinds: [InternedString: InternedString] = [:]
        for decl in module.arena.declarations {
            guard case let .function(function) = decl else { continue }

            let (exprSymbolMap, entries) = scanBuilderLambdaEntries(
                body: function.body, lookup: lookup, ctx: ctx
            )

            for entry in entries {
                if let symbol = exprSymbolMap[entry.argID] {
                    let lambdaName = ctx.interner.intern("kk_lambda_\(entry.argID)")
                    builderLambdaKinds[lambdaName] = entry.callee
                    if let funcName = symbolToFuncName[symbol] {
                        builderLambdaKinds[funcName] = entry.callee
                    }
                }
            }
        }
        return builderLambdaKinds
    }

    func isStdlibBuilderDSLCall(
        symbol: SymbolID?,
        callee: InternedString,
        lookup: CollectionLiteralLookupTables,
        ctx: KIRContext
    ) -> Bool {
        guard lookup.builderDSLNames.contains(callee) else {
            return false
        }
        guard let symbol else {
            return true
        }
        guard let sema = ctx.sema,
              let semanticSymbol = sema.symbols.symbol(symbol)
        else {
            return false
        }
        if semanticSymbol.flags.contains(.synthetic) {
            return true
        }
        if sema.symbols.externalLinkName(for: symbol)?.hasPrefix("kk_build_") == true {
            return true
        }
        // Source-backed builders resolve to CollectionBuilders.kt
        // (KSP-622, KSP-623), so the legacy rewrite never applies.
        return false
    }

    private func scanBuilderLambdaEntries(
        body: [KIRInstruction],
        lookup: CollectionLiteralLookupTables,
        ctx: KIRContext
    ) -> (exprSymbolMap: [Int32: SymbolID], entries: [(argID: Int32, callee: InternedString)]) {
        var exprSymbolMap: [Int32: SymbolID] = [:]
        var entries: [(argID: Int32, callee: InternedString)] = []
        for instruction in body {
            switch instruction {
            case let .constValue(result, .symbolRef(symbol)):
                exprSymbolMap[result.rawValue] = symbol
            case let .call(symbol, callee, arguments, _, _, _, _, _):
                if isStdlibBuilderDSLCall(symbol: symbol, callee: callee, lookup: lookup, ctx: ctx),
                   !arguments.isEmpty {
                    entries.append((argID: arguments[arguments.count - 1].rawValue, callee: callee))
                }
            default:
                break
            }
        }
        return (exprSymbolMap, entries)
    }

    func collectInitialCollectionExprIDs(
        function: KIRFunction,
        lookup: CollectionLiteralLookupTables,
        arena: KIRArena,
        sema: SemaModule?,
        interner: StringInterner,
        state: inout CollectionRewriteState
    ) {
        // Seed tracking sets from static type information (LOWERING-001).
        // This covers function parameters, return values, and any expression
        // whose KIR type is a known collection class (List, MutableList, Set,
        // MutableSet, Map, MutableMap, etc.).
        seedCollectionExprIDsFromStaticTypes(
            function: function,
            arena: arena,
            sema: sema,
            interner: interner,
            state: &state
        )

        // First pass: collect char-valued and ulong-valued expression IDs to detect
        // char range and ULong range arguments (STDLIB-290, STDLIB-524).
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
            case let .call(_, callee, arguments, result, _, _, _, _):
                handleCallInstruction(
                    callee: callee, arguments: arguments, result: result,
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
            case let .constValue(result, .stringLiteral):
                state.stringExprIDs.insert(result.rawValue)
            default:
                break
            }
        }
    }

    private func handleCallInstruction(
        callee: InternedString,
        arguments: [KIRExprID],
        result: KIRExprID?,
        lookup: CollectionLiteralLookupTables,
        charValuedExprIDs: Set<Int32>,
        ulongValuedExprIDs: Set<Int32>,
        state: inout CollectionRewriteState
    ) {
        classifyFactoryCall(
            callee: callee, result: result, lookup: lookup,
            state: &state
        )
        // Classify range factory calls
        if let result,
           callee == lookup.kkOpRangeToName || callee == lookup.kkOpRangeUntilName
           || callee == lookup.kkOpULongRangeUntilName
           || callee == lookup.kkOpDownToName || callee == lookup.kkOpStepName
        {
            state.rangeExprIDs.insert(result.rawValue)
            // Detect CharRange: if any argument is a char-valued expression (STDLIB-290)
            if arguments.contains(where: { charValuedExprIDs.contains($0.rawValue) }) {
                state.charRangeExprIDs.insert(result.rawValue)
            }
            // Detect ULongRange: if any argument is a ULong-valued expression (STDLIB-524)
            if arguments.contains(where: { ulongValuedExprIDs.contains($0.rawValue) }) {
                state.ulongRangeExprIDs.insert(result.rawValue)
            }
            // step on a char range propagates char range
            if callee == lookup.kkOpStepName, !arguments.isEmpty,
               state.charRangeExprIDs.contains(arguments[0].rawValue)
            {
                state.charRangeExprIDs.insert(result.rawValue)
            }
            // step on a ULong range propagates ULong range (STDLIB-524)
            if callee == lookup.kkOpStepName, !arguments.isEmpty,
               state.ulongRangeExprIDs.contains(arguments[0].rawValue)
            {
                state.ulongRangeExprIDs.insert(result.rawValue)
            }
        }
        // STDLIB-189: Classify string-producing calls
        if let result, lookup.stringProducingCallees.contains(callee) {
            state.stringExprIDs.insert(result.rawValue)
        }
        // KSP-441: Sequence factories whose source body is just a bridge to a
        // runtime __kk_* / kk_* entry return a RuntimeSequenceBox handle.  Track
        // those results so source Sequence HOFs route to the runtime helpers.
        if let result, lookup.sequenceRuntimeBridgeReturningNames.contains(callee) {
            state.sequenceExprIDs.insert(result.rawValue)
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
            } else if callee == lookup.toIntArrayName {
                state.arrayExprIDs.insert(result.rawValue)
            }
        }
        // STDLIB-565: Classify File constructor calls.
        // KNOWN LIMITATION: Only direct File("...") / __kk_file_new constructor
        // calls are seeded here.  File receivers originating from function
        // parameters, return values, or field loads are not tracked, so their
        // member calls will fall through to the default virtualCall path.  A
        // future improvement could use the receiver's static type for dispatch
        // instead of *ExprIDs membership (same pattern as the sequence rewrite
        // limitation noted above).
        if let result,
           callee == lookup.fileConstructorName || callee == lookup.kkFileNewName
        {
            state.fileExprIDs.insert(result.rawValue)
        }
    }

    private func classifyFactoryCall(
        callee: InternedString,
        result: KIRExprID?,
        lookup: CollectionLiteralLookupTables,
        state: inout CollectionRewriteState
    ) {
        guard let result else { return }
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
                    || callee == lookup.kkSetOfNotNullName {
            state.setExprIDs.insert(result.rawValue)
        } else if lookup.mapFactoryNames.contains(callee) || lookup.mutableMapConstructorNames.contains(callee)
                    || callee == lookup.kkMapOfName {
            state.mapExprIDs.insert(result.rawValue)
        } else if lookup.arrayOfFactoryNames.contains(callee)
            || callee == lookup.kkArrayNewName
            // CallLowerer may already lower intArrayOf/arrayOf to kk_array_of before this pass.
            || callee == lookup.kkArrayOfName
        {
            state.arrayExprIDs.insert(result.rawValue)
        }
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
            || callee == lookup.scanName || callee == lookup.runningFoldName
            || callee == lookup.kkListSortedName
            || callee == lookup.kkListShuffledName
            || callee == lookup.kkListShuffledRandomName,
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
                || callee == lookup.kkListSortedName
                || callee == lookup.kkListShuffledName
                || callee == lookup.kkListShuffledRandomName
            {
                if let result { state.listExprIDs.insert(result.rawValue) }
            }
            // withIndex returns IndexingIterable, not List — do not add to state.listExprIDs
        }

        // Track range member calls that return ranges
        if state.rangeExprIDs.contains(receiverRaw) {
            if callee == lookup.reversedName {
                if let result {
                    state.rangeExprIDs.insert(result.rawValue)
                    // Propagate char range through reversed() (STDLIB-290)
                    if state.charRangeExprIDs.contains(receiverRaw) {
                        state.charRangeExprIDs.insert(result.rawValue)
                    }
                    // Propagate ULong range through reversed() (STDLIB-524)
                    if state.ulongRangeExprIDs.contains(receiverRaw) {
                        state.ulongRangeExprIDs.insert(result.rawValue)
                    }
                }
            } else if callee == lookup.toListName || callee == lookup.mapName {
                if let result { state.listExprIDs.insert(result.rawValue) }
            }
        }

        // STDLIB-189: Track string HOF results
        if state.stringExprIDs.contains(receiverRaw) {
            if callee == lookup.mapName || callee == lookup.filterName, let result {
                state.stringExprIDs.insert(result.rawValue)
            }
        }
    }

    // MARK: - Static type based collection classification (LOWERING-001)

    /// Collect expression IDs referenced in a function's body that participate
    /// in collection-type propagation. This covers instruction kinds that
    /// produce or consume collection-typed operands (call, virtualCall, copy,
    /// constValue, returnValue).
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

    /// Seed the collection tracking sets using the static type information
    /// stored in the KIR arena's `exprTypes` map.  This handles expressions
    /// whose concrete collection kind cannot be determined from factory/call
    /// patterns alone, such as function parameters typed as `List<T>` or
    /// return values from user-defined functions returning `Set<T>`.
    private func seedCollectionExprIDsFromStaticTypes(
        function: KIRFunction,
        arena: KIRArena,
        sema: SemaModule?,
        interner: StringInterner,
        state: inout CollectionRewriteState
    ) {
        guard let sema else { return }
        let types = sema.types
        let symbols = sema.symbols

        // For each expression referenced in this function's body that has
        // a TypeID in the arena, resolve the TypeKind.  If it is a classType,
        // check the classSymbol's simple name against known collection names.
        let referencedExprIDs = collectReferencedExprIDs(function: function)

        for rawID in referencedExprIDs {
            let exprID = KIRExprID(rawValue: rawID)
            guard let typeID = arena.exprType(exprID) else { continue }
            // Already classified by factory-call scan — skip.
            if state.listExprIDs.contains(rawID) || state.setExprIDs.contains(rawID)
                || state.mapExprIDs.contains(rawID) || state.arrayExprIDs.contains(rawID)
                || state.sequenceExprIDs.contains(rawID) || state.stringExprIDs.contains(rawID)
            {
                continue
            }
            classifyExprByTypeID(
                expr: exprID, typeID: typeID,
                types: types, symbols: symbols, interner: interner,
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
        interner: StringInterner,
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
              let trackedKind = trackedStaticTypeKind(of: symInfo, interner: interner)
        else {
            return
        }
        state.tag(expr, as: trackedKind)
    }
}
