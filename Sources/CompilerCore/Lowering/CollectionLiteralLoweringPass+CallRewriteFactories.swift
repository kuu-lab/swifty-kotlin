
extension CollectionLiteralConstructionLoweringPass {

    func appendRuntimeArrayStorage(
        arguments: [KIRExprID],
        boxPrimitiveElements: Bool,
        module: KIRModule,
        ctx: KIRContext,
        lookup: CollectionLiteralLookupTables,
        loweredBody: inout KIRLoweringEmitContext
    ) -> (array: KIRExprID, count: KIRExprID) {
        let countExpr = module.arena.appendExpr(.intLiteral(Int64(arguments.count)), type: nil)
        loweredBody.append(.constValue(result: countExpr, value: .intLiteral(Int64(arguments.count))))
        let arrayExpr = module.arena.appendTemporary(type: nil)
        loweredBody.append(.call(
            callee: lookup.kkArrayNewName,
            arguments: [countExpr],
            result: arrayExpr,
            canThrow: false
        ))

        for (index, argument) in arguments.enumerated() {
            let indexExpr = module.arena.appendExpr(.intLiteral(Int64(index)), type: nil)
            loweredBody.append(.constValue(result: indexExpr, value: .intLiteral(Int64(index))))
            let storedArgument: KIRExprID
            if boxPrimitiveElements,
               let types = ctx.sema?.types,
               let argumentType = module.arena.exprType(argument),
               let boxCallee = primitiveBoxCalleeName(
                   for: argumentType,
                   types: types,
                   symbols: ctx.sema?.symbols,
                   interner: ctx.interner
               )
            {
                let boxedResult = module.arena.appendTemporary(type: types.anyType)
                emitBoxCallWithValueClassTag(
                    boxCallee: boxCallee,
                    value: argument,
                    rawSourceKind: types.kind(of: argumentType),
                    result: boxedResult,
                    resultType: types.anyType,
                    types: types,
                    symbols: ctx.sema?.symbols,
                    interner: ctx.interner,
                    arena: module.arena,
                    sema: ctx.sema,
                    cache: ctx.nominalDispatchCache,
                    into: &loweredBody
                )
                storedArgument = boxedResult
            } else {
                storedArgument = argument
            }

            let setResult = module.arena.appendTemporary(type: nil)
            loweredBody.append(.call(
                callee: lookup.kkArraySetName,
                arguments: [arrayExpr, indexExpr, storedArgument],
                result: setResult,
                canThrow: false
            ))
        }
        return (arrayExpr, countExpr)
    }

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
            cache: ctx.nominalDispatchCache,
            arena: module.arena,
            interner: ctx.interner,
            instructions: &loweredBody
        )
    }

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

        // Keep the Kotlin-source declarations visible to sema, but preserve the
        // runtime lowering path for primitive boxing and tracked collection IDs.
        if lookup.listFactoryNames.contains(callee),
           isStdlibCollectionFactory(symbol: symbol, lookup: lookup, ctx: ctx) {
            let count = arguments.count
            if count == 0 && callee != lookup.mutableListOfName && callee != lookup.arrayListOfName {
                if callee == lookup.emptyArrayName {
                    loweredBody.append(.call(
                        callee: lookup.kkEmptyArrayName,
                        arguments: [],
                        result: result,
                        canThrow: false
                    ))
                } else {
                    loweredBody.append(.call(
                        callee: lookup.kkEmptyListName,
                        arguments: [],
                        result: result,
                        canThrow: false
                    ))
                }
            } else if count == 0 {
                let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
                loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                let nullExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
                loweredBody.append(.constValue(result: nullExpr, value: .intLiteral(0)))
                let runtimeCallee = callee == lookup.arrayListOfName
                    || callee == lookup.mutableListOfName
                    ? lookup.kkArrayListOfName
                    : lookup.kkListOfName
                loweredBody.append(.call(
                    callee: runtimeCallee,
                    arguments: [nullExpr, zeroExpr],
                    result: result,
                    canThrow: false
                ))
            } else {
                let (arrayExpr, countExpr) = appendRuntimeArrayStorage(
                    arguments: arguments,
                    boxPrimitiveElements: true,
                    module: module,
                    ctx: ctx,
                    lookup: lookup,
                    loweredBody: &loweredBody
                )
                let runtimeCallee = callee == lookup.arrayListOfName
                    || callee == lookup.mutableListOfName
                    ? lookup.kkArrayListOfName
                    : lookup.kkListOfName
                loweredBody.append(.call(
                    callee: runtimeCallee,
                    arguments: [arrayExpr, countExpr],
                    result: result,
                    canThrow: false
                ))
            }
            return true
        }

        if isStdlibArrayListConstructor(symbol: symbol, callee: callee, lookup: lookup, ctx: ctx) {
            let constructorArguments: [KIRExprID]
            let resolvedCopyConstructor: Bool
            if let symbol, let sema = ctx.sema,
               sema.symbols.symbol(symbol)?.kind == .constructor,
               let signature = sema.symbols.functionSignature(for: symbol) {
                // Ordinary resolved constructors include the allocated receiver.
                // The replacement factory allocates its own backing storage.
                constructorArguments = arguments.count == signature.parameterTypes.count + 1
                    ? Array(arguments.dropFirst()) : arguments
                resolvedCopyConstructor = signature.parameterTypes.count == 1
                    && resolveClassTypeSymbol(signature.parameterTypes[0], sema: sema)?.symbol.fqName == [
                        lookup.kotlinName, ctx.interner.intern("collections"), ctx.interner.intern("Collection"),
                    ]
            } else {
                constructorArguments = arguments
                resolvedCopyConstructor = false
            }
            if constructorArguments.count == 1,
               resolvedCopyConstructor
                || isCollectionCopyConstructorArgument(constructorArguments[0], module: module, ctx: ctx) {
                loweredBody.append(.call(
                    callee: lookup.kkCollectionToArrayListName,
                    arguments: [constructorArguments[0]],
                    result: result,
                    canThrow: false
                ))
                if let result { state.listExprIDs.insert(result.rawValue) }
                return true
            }

            if constructorArguments.count == 1 {
                loweredBody.append(.call(
                    callee: ctx.interner.intern("__kk_array_list_new_checked"),
                    arguments: constructorArguments,
                    result: result,
                    canThrow: true,
                    thrownResult: thrownResult
                ))
                return true
            }

            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            let nullExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: nullExpr, value: .intLiteral(0)))
            loweredBody.append(.call(
                callee: lookup.kkArrayListOfName,
                arguments: [nullExpr, zeroExpr],
                result: result,
                canThrow: false
            ))
            return true
        }

        let isHashSetConstructor = isHashSetConstructor(
            callee: callee,
            symbol: symbol,
            arguments: arguments,
            result: result,
            module: module,
            lookup: lookup,
            ctx: ctx
        )
        if (lookup.mutableSetConstructorNames.contains(callee)
            && isStdlibCollectionConstructor(symbol: symbol, className: callee, result: result, module: module, ctx: ctx))
            || isHashSetConstructor {
            if arguments.count == 1,
               isCollectionCopyConstructorArgument(arguments[0], module: module, ctx: ctx) {
                loweredBody.append(.call(
                    callee: isHashSetConstructor
                        ? lookup.kkIterableToHashSetName
                        : lookup.kkIterableToMutableSetName,
                    arguments: [arguments[0]],
                    result: result,
                    canThrow: false
                ))
                if let result { state.setExprIDs.insert(result.rawValue) }
                return true
            }

            if isHashSetConstructor, (arguments.count == 1 || arguments.count == 2) {
                let loadFactor: KIRExprID
                if arguments.count == 2 {
                    loadFactor = arguments[1]
                } else {
                    let floatType = ctx.sema?.types.floatType
                    loadFactor = module.arena.appendExpr(.floatLiteral(0.75), type: floatType)
                    loweredBody.append(.constValue(result: loadFactor, value: .floatLiteral(0.75)))
                }
                loweredBody.append(.call(
                    callee: ctx.interner.intern("__kk_hash_set_new_checked"),
                    arguments: [arguments[0], loadFactor],
                    result: result,
                    canThrow: true,
                    thrownResult: thrownResult
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
                callee: isHashSetConstructor
                    ? lookup.kkHashSetOfName
                    : lookup.kkLinkedHashSetOfName,
                arguments: [nullExpr, zeroExpr],
                result: result,
                canThrow: false
            ))
            return true
        }

        if let mapConstructorName = stdlibMutableMapConstructorName(
            symbol: symbol,
            callee: callee,
            result: result,
            lookup: lookup,
            arena: module.arena,
            sema: ctx.sema,
            interner: ctx.interner
        ) {
            // KUU-556: LinkedHashMap is now a real HashMap subclass, so its
            // constructor gets its own runtime tag (kkLinkedHashMapOfName)
            // instead of sharing the generic kkMapOfName every other mutable
            // map factory still uses.
            let constructorCallee = mapConstructorName == lookup.hashMapName
                ? lookup.kkHashMapOfName
                : lookup.kkLinkedHashMapOfName
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            let nullExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: nullExpr, value: .intLiteral(0)))
            let nullExpr2 = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: nullExpr2, value: .intLiteral(0)))

            let copyArgument: KIRExprID?
            if let symbol,
               ctx.sema?.symbols.symbol(symbol)?.kind == .constructor,
               let signature = ctx.sema?.symbols.functionSignature(for: symbol) {
                if signature.parameterTypes.count == 1,
                   let argument = arguments.last,
                   state.mapExprIDs.contains(argument.rawValue) {
                    copyArgument = argument
                } else {
                    copyArgument = nil
                }
            } else if arguments.count == 1,
                      state.mapExprIDs.contains(arguments[0].rawValue) {
                copyArgument = arguments[0]
            } else {
                copyArgument = nil
            }
            if let copyArgument {
                loweredBody.append(.call(
                    callee: constructorCallee,
                    arguments: [nullExpr, nullExpr2, zeroExpr],
                    result: result,
                    canThrow: false
                ))
                let putAllResult = module.arena.appendTemporary(type: nil
                )
                loweredBody.append(.call(
                    callee: lookup.kkMutableMapPutAllName,
                    arguments: result.map { [$0, copyArgument] } ?? [copyArgument],
                    result: putAllResult,
                    canThrow: false
                ))
            } else {
                // 0 args, capacity arg (Int), or unknown arg type → empty map
                loweredBody.append(.call(
                    callee: constructorCallee,
                    arguments: [nullExpr, nullExpr2, zeroExpr],
                    result: result,
                    canThrow: false
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

        // `java.util.TreeSet()` / `TreeSet(comparator)` / `TreeSet(collection)`
        // / `TreeSet(sortedSet)` -> a sorted RuntimeSetBox. The comparator form
        // forwards its object handle raw (0 means natural ordering).
        if isTreeSetConstructor(
            callee: callee, symbol: symbol, result: result,
            module: module, lookup: lookup, ctx: ctx
        ) {
            switch treeSetConstructorKind(
                symbol: symbol, arguments: arguments, module: module,
                state: state, ctx: ctx
            ) {
            case .emptyOrComparator:
                var callArguments: [KIRExprID] = []
                // `arguments[0]` is the allocated `this`; a second element is
                // the comparator argument when present.
                if let argument = arguments.last, arguments.count >= 2 {
                    callArguments = [argument]
                } else {
                    let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
                    loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                    callArguments = [zeroExpr]
                }
                loweredBody.append(.call(
                    callee: lookup.kkTreeSetNewName,
                    arguments: callArguments, result: result,
                    canThrow: false
                ))
            case .collection:
                loweredBody.append(.call(
                    callee: lookup.kkTreeSetNewCollectionName,
                    arguments: Array(arguments.suffix(1)), result: result,
                    canThrow: false
                ))
            case .sortedSet:
                loweredBody.append(.call(
                    callee: lookup.kkTreeSetNewSortedSetName,
                    arguments: Array(arguments.suffix(1)), result: result,
                    canThrow: false
                ))
            }
            if let result {
                state.setExprIDs.insert(result.rawValue)
            }
            return true
        }

        if isTreeMapConstructor(
            callee: callee, symbol: symbol, result: result,
            module: module, lookup: lookup, ctx: ctx
        ) {
            switch treeMapConstructorKind(
                symbol: symbol, arguments: arguments, module: module,
                state: state, ctx: ctx
            ) {
            case .emptyOrComparator:
                var callArguments: [KIRExprID] = []
                if let argument = arguments.last, arguments.count >= 2 {
                    callArguments = [argument]
                } else {
                    let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
                    loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                    callArguments = [zeroExpr]
                }
                loweredBody.append(.call(
                    callee: lookup.kkTreeMapNewName,
                    arguments: callArguments, result: result,
                    canThrow: false
                ))
            case .map:
                loweredBody.append(.call(
                    callee: lookup.kkTreeMapNewMapName,
                    arguments: Array(arguments.suffix(1)), result: result,
                    canThrow: false
                ))
            case .sortedMap:
                loweredBody.append(.call(
                    callee: lookup.kkTreeMapNewSortedMapName,
                    arguments: Array(arguments.suffix(1)), result: result,
                    canThrow: false
                ))
            }
            if let result {
                state.mapExprIDs.insert(result.rawValue)
            }
            return true
        }

        if lookup.setFactoryNames.contains(callee),
           isStdlibCollectionFactory(symbol: symbol, lookup: lookup, ctx: ctx) {
            let count = arguments.count
            if count == 0
                && callee != lookup.mutableSetOfName
                && callee != lookup.hashSetOfName
                && callee != lookup.linkedSetOfName {
                loweredBody.append(.call(
                    callee: lookup.kkEmptySetName,
                    arguments: [],
                    result: result,
                    canThrow: false
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
                    callee: callee == lookup.hashSetOfName
                        ? lookup.kkHashSetOfName
                        : lookup.kkLinkedHashSetOfName,
                    arguments: [nullExpr, zeroExpr],
                    result: result,
                    canThrow: false
                ))
            } else {
                let (arrayExpr, countExpr) = appendRuntimeArrayStorage(
                    arguments: arguments,
                    boxPrimitiveElements: true,
                    module: module,
                    ctx: ctx,
                    lookup: lookup,
                    loweredBody: &loweredBody
                )
                let runtimeCallee = callee == lookup.hashSetOfName
                    ? lookup.kkHashSetOfName
                    : callee == lookup.setOfNotNullName
                    ? lookup.kkSetOfNotNullName
                    : callee == lookup.mutableSetOfName || callee == lookup.linkedSetOfName
                    ? lookup.kkLinkedHashSetOfName
                    : lookup.kkSetOfName
                loweredBody.append(.call(
                    callee: runtimeCallee,
                    arguments: [arrayExpr, countExpr],
                    result: result,
                    canThrow: false
                ))
            }
            if let result { state.setExprIDs.insert(result.rawValue) }
            return true
        }

        if lookup.mapFactoryNames.contains(callee),
           isStdlibCollectionFactory(symbol: symbol, lookup: lookup, ctx: ctx) {
            let count = arguments.count
            if count == 0
                && callee != lookup.mutableMapOfName
                && callee != lookup.hashMapOfName
                && callee != lookup.linkedMapOfName {
                loweredBody.append(.call(
                    callee: lookup.kkEmptyMapName,
                    arguments: [],
                    result: result,
                    canThrow: false
                ))
            } else if count == 0 {
                // KUU-646: `__kk_map_of` is now the read-only `Map` tag used by
                // `mapOf`. Mutable factories take the same split List/Set
                // already use: hashMapOf → HashMap, mutableMapOf/linkedMapOf →
                // LinkedHashMap (Kotlin's mutableMapOf returns LinkedHashMap).
                let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
                loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                let nullKeysExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
                loweredBody.append(.constValue(result: nullKeysExpr, value: .intLiteral(0)))
                let nullValsExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
                loweredBody.append(.constValue(result: nullValsExpr, value: .intLiteral(0)))
                let runtimeCallee: InternedString
                if callee == lookup.hashMapOfName {
                    runtimeCallee = lookup.kkHashMapOfName
                } else {
                    runtimeCallee = lookup.kkLinkedHashMapOfName
                }
                loweredBody.append(.call(
                    callee: runtimeCallee,
                    arguments: [nullKeysExpr, nullValsExpr, zeroExpr],
                    result: result,
                    canThrow: false
                ))
            } else {
                let countExpr = module.arena.appendExpr(.intLiteral(Int64(count)), type: nil)
                loweredBody.append(.constValue(result: countExpr, value: .intLiteral(Int64(count))))
                let keysArrayExpr = module.arena.appendTemporary(type: nil
                )
                loweredBody.append(.call(
                    callee: lookup.kkArrayNewName,
                    arguments: [countExpr],
                    result: keysArrayExpr,
                    canThrow: false
                ))
                let valuesArrayExpr = module.arena.appendTemporary(type: nil
                )
                loweredBody.append(.call(
                    callee: lookup.kkArrayNewName,
                    arguments: [countExpr],
                    result: valuesArrayExpr,
                    canThrow: false
                ))
                for (i, arg) in arguments.enumerated() {
                    let idxExpr = module.arena.appendExpr(.intLiteral(Int64(i)), type: nil)
                    loweredBody.append(.constValue(result: idxExpr, value: .intLiteral(Int64(i))))
                    let keyExpr = module.arena.appendTemporary(type: nil
                    )
                    loweredBody.append(.call(
                        callee: lookup.kkPairFirstName,
                        arguments: [arg],
                        result: keyExpr,
                        canThrow: false
                    ))
                    let valueExpr = module.arena.appendTemporary(type: nil
                    )
                    loweredBody.append(.call(
                        callee: lookup.kkPairSecondName,
                        arguments: [arg],
                        result: valueExpr,
                        canThrow: false
                    ))
                    let setResult = module.arena.appendTemporary(type: nil
                    )
                    loweredBody.append(.call(
                        callee: lookup.kkArraySetName,
                        arguments: [keysArrayExpr, idxExpr, keyExpr],
                        result: setResult,
                        canThrow: false
                    ))
                    let setResult2 = module.arena.appendTemporary(type: nil
                    )
                    loweredBody.append(.call(
                        callee: lookup.kkArraySetName,
                        arguments: [valuesArrayExpr, idxExpr, valueExpr],
                        result: setResult2,
                        canThrow: false
                    ))
                }
                loweredBody.append(.call(
                    callee: {
                        if callee == lookup.hashMapOfName {
                            return lookup.kkHashMapOfName
                        }
                        if callee == lookup.mutableMapOfName || callee == lookup.linkedMapOfName {
                            return lookup.kkLinkedHashMapOfName
                        }
                        return lookup.kkMapOfName
                    }(),
                    arguments: [keysArrayExpr, valuesArrayExpr, countExpr],
                    result: result,
                    canThrow: false
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
