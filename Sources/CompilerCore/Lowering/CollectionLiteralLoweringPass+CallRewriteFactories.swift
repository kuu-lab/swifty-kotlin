
extension CollectionLiteralConstructionLoweringPass {

    /// Registers the rewritten result's nominal vtable implementations when the
    /// factory produced a concrete-class collection box. See the call-site
    /// comment in `lowerCallInstruction` for why the box needs them.
    func appendFactoryResultVtableRegistrations(
        result: KIRExprID?,
        module: KIRModule,
        ctx: KIRContext,
        loweredBody: inout KIRLoweringEmitContext
    ) {
        guard let result,
              let sema = ctx.sema,
              let resultType = module.arena.exprType(result),
              let resolved = resolveClassTypeSymbol(resultType, sema: sema),
              resolved.symbol.kind == .class
        else { return }
        appendFactoryObjectVtableMethodRegistrations(
            objectValue: result,
            nominalSymbol: resolved.symbol.id,
            sema: sema,
            arena: module.arena,
            interner: ctx.interner,
            instructions: &loweredBody
        )
    }

    /// Rewrites collection factories, builder DSL calls, and tuple constructor shims.
    func rewriteFactoryAndBuilderCall(
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
        if rewriteSequenceBuilderCall(
            symbol: symbol,
            callee: callee,
            arguments: arguments,
            result: result,
            canThrow: canThrow,
            thrownResult: thrownResult,
            module: module,
            ctx: ctx,
            lookup: lookup,
            state: &state,
            loweredBody: &loweredBody
        ) {
            return true
        }

        // --- Rewrite list factories to runtime helpers. ---
        // Keep the Kotlin-source declarations visible to sema, but preserve the
        // runtime lowering path for primitive boxing and tracked collection IDs.
        if lookup.listFactoryNames.contains(callee),
           isStdlibCollectionFactory(symbol: symbol, lookup: lookup, ctx: ctx) {
            let count = arguments.count
            if count == 0 && callee != lookup.mutableListOfName && callee != lookup.arrayListOfName {
                if callee == lookup.emptyArrayName {
                    // emptyArray() -> kk_empty_array()
                    loweredBody.append(.call(
                        symbol: nil,
                        callee: lookup.kkEmptyArrayName,
                        arguments: [],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                } else {
                    // emptyList(), listOf() -> kk_emptyList()
                    loweredBody.append(.call(
                        symbol: nil,
                        callee: lookup.kkEmptyListName,
                        arguments: [],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                }
            } else if count == 0 {
                // mutableListOf()/arrayListOf() -> fresh instance via the
                // corresponding tagged list bridge.
                let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
                loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                let nullExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
                loweredBody.append(.constValue(result: nullExpr, value: .intLiteral(0)))
                let runtimeCallee = callee == lookup.arrayListOfName
                    || callee == lookup.mutableListOfName
                    ? lookup.kkArrayListOfName
                    : lookup.kkListOfName
                loweredBody.append(.call(
                    symbol: nil,
                    callee: runtimeCallee,
                    arguments: [nullExpr, zeroExpr],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
            } else {
                // listOf(a, b, c), mutableListOf(a, b, c), arrayListOf(a, b, c) -> kk_list_of
                let countExpr = module.arena.appendExpr(.intLiteral(Int64(count)), type: nil)
                loweredBody.append(.constValue(result: countExpr, value: .intLiteral(Int64(count))))
                let arrayExpr = module.arena.appendTemporary(type: nil
                )
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkArrayNewName,
                    arguments: [countExpr],
                    result: arrayExpr,
                    canThrow: false,
                    thrownResult: nil
                ))
                for (i, arg) in arguments.enumerated() {
                    let idxExpr = module.arena.appendExpr(.intLiteral(Int64(i)), type: nil)
                    loweredBody.append(.constValue(result: idxExpr, value: .intLiteral(Int64(i))))
                    let storedArg: KIRExprID
                    if let types = ctx.sema?.types,
                       let argType = module.arena.exprType(arg),
                       let boxCallee = primitiveBoxCalleeName(
                           for: argType,
                           types: types,
                           symbols: ctx.sema?.symbols,
                           interner: ctx.interner
                       )
                    {
                        let boxedResult = module.arena.appendTemporary(type: types.anyType)
                        emitBoxCallWithValueClassTag(
                            boxCallee: boxCallee,
                            value: arg,
                            rawSourceKind: types.kind(of: argType),
                            result: boxedResult,
                            resultType: types.anyType,
                            types: types,
                            symbols: ctx.sema?.symbols,
                            interner: ctx.interner,
                            arena: module.arena,
                            into: &loweredBody
                        )
                        storedArg = boxedResult
                    } else {
                        storedArg = arg
                    }
                    let setResult = module.arena.appendTemporary(type: nil
                    )
                    loweredBody.append(.call(
                        symbol: nil,
                        callee: lookup.kkArraySetName,
                        arguments: [arrayExpr, idxExpr, storedArg],
                        result: setResult,
                        canThrow: false,
                        thrownResult: nil
                    ))
                }
                let runtimeCallee = callee == lookup.arrayListOfName
                    || callee == lookup.mutableListOfName
                    ? lookup.kkArrayListOfName
                    : lookup.kkListOfName
                loweredBody.append(.call(
                    symbol: nil,
                    callee: runtimeCallee,
                    arguments: [arrayExpr, countExpr],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
            }
            return true
        }

        // --- Rewrite ArrayList()/HashSet()/LinkedHashSet()/HashMap()/LinkedHashMap() constructors ---
        // 0 args → empty collection; 1 int arg (capacity) → empty collection;
        // 1 collection arg → copy.
        if isStdlibArrayListConstructor(symbol: symbol, callee: callee, lookup: lookup, ctx: ctx) {
            if arguments.count == 1,
               isCollectionCopyConstructorArgument(arguments[0], module: module, ctx: ctx) {
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkCollectionToArrayListName,
                    arguments: [arguments[0]],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                if let result { state.listExprIDs.insert(result.rawValue) }
                return true
            }

            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            let nullExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: nullExpr, value: .intLiteral(0)))
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkArrayListOfName,
                arguments: [nullExpr, zeroExpr],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return true
        }

        let isHashSetConstructor = isHashSetConstructor(
            callee: callee,
            symbol: symbol,
            result: result,
            module: module,
            lookup: lookup,
            ctx: ctx
        )
        if lookup.mutableSetConstructorNames.contains(callee) || isHashSetConstructor {
            if arguments.count == 1,
               isCollectionCopyConstructorArgument(arguments[0], module: module, ctx: ctx) {
                loweredBody.append(.call(
                    symbol: nil,
                    callee: isHashSetConstructor
                        ? lookup.kkIterableToHashSetName
                        : lookup.kkIterableToMutableSetName,
                    arguments: [arguments[0]],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                if let result { state.setExprIDs.insert(result.rawValue) }
                return true
            }

            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            let nullExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: nullExpr, value: .intLiteral(0)))
            // `mutableSetConstructorNames` holds only HashSet and LinkedHashSet,
            // so the non-HashSet case here is LinkedHashSet() / LinkedHashSet(capacity).
            loweredBody.append(.call(
                symbol: nil,
                callee: isHashSetConstructor
                    ? lookup.kkHashSetOfName
                    : lookup.kkLinkedHashSetOfName,
                arguments: [nullExpr, zeroExpr],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return true
        }

        if lookup.mutableMapConstructorNames.contains(callee) {
            // KUU-556: LinkedHashMap is now a real HashMap subclass, so its
            // constructor gets its own runtime tag (kkLinkedHashMapOfName)
            // instead of sharing the generic kkMapOfName every other mutable
            // map factory still uses.
            let constructorCallee = callee == lookup.hashMapName
                ? lookup.kkHashMapOfName
                : lookup.kkLinkedHashMapOfName
            // Create an empty mutable map first
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            let nullExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: nullExpr, value: .intLiteral(0)))
            let nullExpr2 = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: nullExpr2, value: .intLiteral(0)))

            if arguments.count == 1, state.mapExprIDs.contains(arguments[0].rawValue) {
                // Copy constructor: HashMap(otherMap) — only when arg is map-typed
                // 1. Create empty map into the result
                loweredBody.append(.call(
                    symbol: nil,
                    callee: constructorCallee,
                    arguments: [nullExpr, nullExpr2, zeroExpr],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                // 2. putAll from source map (result is Unit, discarded)
                let putAllResult = module.arena.appendTemporary(type: nil
                )
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkMutableMapPutAllName,
                    arguments: result.map { [$0, arguments[0]] } ?? [arguments[0]],
                    result: putAllResult,
                    canThrow: false,
                    thrownResult: nil
                ))
            } else {
                // 0 args, capacity arg (Int), or unknown arg type → empty map
                loweredBody.append(.call(
                    symbol: nil,
                    callee: constructorCallee,
                    arguments: [nullExpr, nullExpr2, zeroExpr],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
            }
            return true
        }

        // RF-LOWER-CALL-012 follow-up dropped the `map.count(predicate)` ->
        // `kk_map_count` branch that used to sit here. It was unreachable:
        // `Stdlib/kotlin/collections/MapHOF.kt` provides
        // `Map<K, V>.count(predicate)` as bundled Kotlin source, and
        // The historical synthetic Map registration path also skipped the
        // competing synthetic `count` member whenever
        // `bundledIndex.contains(ownerFQName: mapFQName, name: "count",
        // arity: 1)` is true, which it is here — so there is no non-source-backed
        // symbol this call could ever resolve to. This branch runs inside
        // `rewriteFactoryAndBuilderCall`, which `lowerCallInstruction` calls
        // *before* the source-backed preservation gate, so unlike the
        // Map HOF branches CALL-012 removed, this one could not rely on that
        // later short-circuit and instead carried its own inline
        // `isSourceBackedBundledFunction` check — which was therefore always
        // true for a resolved call, keeping the branch itself dead the same
        // way. `kk_map_count` has no `@_cdecl` in `Sources/Runtime` (only a
        // `Tests/RuntimeTests/RuntimeCollectionHOF430MapShims.swift` test
        // shim, like the other RF-LOWER-CALL-012 targets), so reaching it
        // would have broken at runtime. `MapCountLoweringRoutingTests` pins
        // the routing.

        // --- Rewrite set factories to runtime helpers. ---
        if lookup.setFactoryNames.contains(callee),
           isStdlibCollectionFactory(symbol: symbol, lookup: lookup, ctx: ctx) {
            let count = arguments.count
            if count == 0
                && callee != lookup.mutableSetOfName
                && callee != lookup.hashSetOfName
                && callee != lookup.linkedSetOfName {
                // emptySet(), setOf(), setOfNotNull() -> __kk_emptySet()
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkEmptySetName,
                    arguments: [],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
            } else if count == 0 {
                // Mutable/hash/linked set factories produce a fresh instance via
                // the shared set storage, each keeping its own nominal tag:
                // hashSetOf is a HashSet, mutableSetOf/linkedSetOf a LinkedHashSet
                // (BUG-254 -- `__kk_set_of` is shared with the read-only `setOf`,
                // so it must stay on the `Set` identity).
                let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
                loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                let nullExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
                loweredBody.append(.constValue(result: nullExpr, value: .intLiteral(0)))
                loweredBody.append(.call(
                    symbol: nil,
                    callee: callee == lookup.hashSetOfName
                        ? lookup.kkHashSetOfName
                        : lookup.kkLinkedHashSetOfName,
                    arguments: [nullExpr, zeroExpr],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
            } else {
                let countExpr = module.arena.appendExpr(.intLiteral(Int64(count)), type: nil)
                loweredBody.append(.constValue(result: countExpr, value: .intLiteral(Int64(count))))
                let arrayExpr = module.arena.appendTemporary(type: nil
                )
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkArrayNewName,
                    arguments: [countExpr],
                    result: arrayExpr,
                    canThrow: false,
                    thrownResult: nil
                ))
                for (i, arg) in arguments.enumerated() {
                    let idxExpr = module.arena.appendExpr(.intLiteral(Int64(i)), type: nil)
                    loweredBody.append(.constValue(result: idxExpr, value: .intLiteral(Int64(i))))
                    let storedArg: KIRExprID
                    if let types = ctx.sema?.types,
                       let argType = module.arena.exprType(arg),
                       let boxCallee = primitiveBoxCalleeName(
                           for: argType,
                           types: types,
                           symbols: ctx.sema?.symbols,
                           interner: ctx.interner
                       )
                    {
                        let boxedResult = module.arena.appendTemporary(type: types.anyType)
                        emitBoxCallWithValueClassTag(
                            boxCallee: boxCallee,
                            value: arg,
                            rawSourceKind: types.kind(of: argType),
                            result: boxedResult,
                            resultType: types.anyType,
                            types: types,
                            symbols: ctx.sema?.symbols,
                            interner: ctx.interner,
                            arena: module.arena,
                            into: &loweredBody
                        )
                        storedArg = boxedResult
                    } else {
                        storedArg = arg
                    }
                    let setResult = module.arena.appendTemporary(type: nil
                    )
                    loweredBody.append(.call(
                        symbol: nil,
                        callee: lookup.kkArraySetName,
                        arguments: [arrayExpr, idxExpr, storedArg],
                        result: setResult,
                        canThrow: false,
                        thrownResult: nil
                    ))
                }
                let runtimeCallee = callee == lookup.hashSetOfName
                    ? lookup.kkHashSetOfName
                    : callee == lookup.setOfNotNullName
                    ? lookup.kkSetOfNotNullName
                    : callee == lookup.mutableSetOfName || callee == lookup.linkedSetOfName
                    ? lookup.kkLinkedHashSetOfName
                    : lookup.kkSetOfName
                loweredBody.append(.call(
                    symbol: nil,
                    callee: runtimeCallee,
                    arguments: [arrayExpr, countExpr],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
            }
            if let result { state.setExprIDs.insert(result.rawValue) }
            return true
        }

        // --- Rewrite map factories to runtime helpers. ---
        if lookup.mapFactoryNames.contains(callee),
           isStdlibCollectionFactory(symbol: symbol, lookup: lookup, ctx: ctx) {
            let count = arguments.count
            if count == 0
                && callee != lookup.mutableMapOfName
                && callee != lookup.hashMapOfName
                && callee != lookup.linkedMapOfName {
                // emptyMap(), mapOf() -> kk_emptyMap()
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkEmptyMapName,
                    arguments: [],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
            } else if count == 0 {
                // mutableMapOf()/hashMapOf() -> fresh instance via kk_map_of(null, null, 0).
                // linkedMapOf() -> kk_linked_hash_map_of instead (KUU-556: it's
                // declared to return LinkedHashMap<K, V>, now a real HashMap
                // subclass with its own runtime tag; hashMapOf()/mutableMapOf()
                // keep the pre-existing generic tag -- a known, separately
                // tracked gap, not introduced by this change).
                let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
                loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                let nullKeysExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
                loweredBody.append(.constValue(result: nullKeysExpr, value: .intLiteral(0)))
                let nullValsExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
                loweredBody.append(.constValue(result: nullValsExpr, value: .intLiteral(0)))
                loweredBody.append(.call(
                    symbol: nil,
                    callee: callee == lookup.linkedMapOfName ? lookup.kkLinkedHashMapOfName : lookup.kkMapOfName,
                    arguments: [nullKeysExpr, nullValsExpr, zeroExpr],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
            } else {
                // mapOf(pair1, pair2, ...), mutableMapOf(...), hashMapOf(...), linkedMapOf(...) -> kk_map_of
                let countExpr = module.arena.appendExpr(.intLiteral(Int64(count)), type: nil)
                loweredBody.append(.constValue(result: countExpr, value: .intLiteral(Int64(count))))
                let keysArrayExpr = module.arena.appendTemporary(type: nil
                )
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkArrayNewName,
                    arguments: [countExpr],
                    result: keysArrayExpr,
                    canThrow: false,
                    thrownResult: nil
                ))
                let valuesArrayExpr = module.arena.appendTemporary(type: nil
                )
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkArrayNewName,
                    arguments: [countExpr],
                    result: valuesArrayExpr,
                    canThrow: false,
                    thrownResult: nil
                ))
                for (i, arg) in arguments.enumerated() {
                    let idxExpr = module.arena.appendExpr(.intLiteral(Int64(i)), type: nil)
                    loweredBody.append(.constValue(result: idxExpr, value: .intLiteral(Int64(i))))
                    let keyExpr = module.arena.appendTemporary(type: nil
                    )
                    loweredBody.append(.call(
                        symbol: nil,
                        callee: lookup.kkPairFirstName,
                        arguments: [arg],
                        result: keyExpr,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    let valueExpr = module.arena.appendTemporary(type: nil
                    )
                    loweredBody.append(.call(
                        symbol: nil,
                        callee: lookup.kkPairSecondName,
                        arguments: [arg],
                        result: valueExpr,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    let setResult = module.arena.appendTemporary(type: nil
                    )
                    loweredBody.append(.call(
                        symbol: nil,
                        callee: lookup.kkArraySetName,
                        arguments: [keysArrayExpr, idxExpr, keyExpr],
                        result: setResult,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    let setResult2 = module.arena.appendTemporary(type: nil
                    )
                    loweredBody.append(.call(
                        symbol: nil,
                        callee: lookup.kkArraySetName,
                        arguments: [valuesArrayExpr, idxExpr, valueExpr],
                        result: setResult2,
                        canThrow: false,
                        thrownResult: nil
                    ))
                }
                loweredBody.append(.call(
                    symbol: nil,
                    // KUU-556: linkedMapOf(pairs) also gets its own runtime tag;
                    // see the count == 0 branch above for the rationale.
                    callee: callee == lookup.linkedMapOfName ? lookup.kkLinkedHashMapOfName : lookup.kkMapOfName,
                    arguments: [keysArrayExpr, valuesArrayExpr, countExpr],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
            }
            return true
        }

        // Sequence factories are lowered through their bundled Kotlin source.

        // The builder DSL rewrite to `__kk_build_*` runtime helpers (STDLIB-002)
        // is gone: RF-LOWER-CALL-004 (list), -005 (set) and -006 (map) removed
        // every arm, so `buildList` / `buildSet` / `buildMap` all lower through
        // `CollectionBuilders.kt`; no legacy Builder DSL predicate or lookup
        // is needed at this entry point anymore.

        return false
    }
}
