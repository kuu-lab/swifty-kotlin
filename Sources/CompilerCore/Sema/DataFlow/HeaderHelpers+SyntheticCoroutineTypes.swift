/// Extracted from `registerSyntheticCoroutineStubs`
/// (HeaderHelpers+SyntheticCoroutineRegistry.swift). The extracted
/// methods thread the shared registry state through `context` so the
/// call order and side effects are unchanged.

extension DataFlowSemaPhase {
    func registerCoreCoroutineTypes(context: inout SyntheticCoroutineRegistryContext) {
        let symbols = context.symbols
        let types = context.types
        let interner = context.interner
        let kotlinPkg = context.kotlinPkg
        let kotlinCoroutinesPkg = context.kotlinCoroutinesPkg

        let kotlinCoroutineContextSymbol = ensureInterfaceSymbol(
            named: "CoroutineContext",
            in: kotlinCoroutinesPkg,
            symbols: symbols,
            interner: interner
        )
        let kotlinCoroutineContextType = types.make(.classType(ClassType(
            classSymbol: kotlinCoroutineContextSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(kotlinCoroutineContextType, for: kotlinCoroutineContextSymbol)

        let kotlinResultSymbol = ensureClassSymbol(
            named: "Result",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        let kotlinResultTypeParamName = interner.intern("T")
        let kotlinResultFQName = kotlinPkg + [interner.intern("Result")]
        let kotlinResultTypeParamFQName = kotlinResultFQName + [kotlinResultTypeParamName]
        let kotlinResultTypeParamSymbol: SymbolID = if let existing = symbols.lookup(fqName: kotlinResultTypeParamFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: kotlinResultTypeParamName,
                fqName: kotlinResultTypeParamFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        symbols.setParentSymbol(kotlinResultSymbol, for: kotlinResultTypeParamSymbol)
        let kotlinResultTType = types.make(.typeParam(TypeParamType(
            symbol: kotlinResultTypeParamSymbol,
            nullability: .nonNull
        )))
        let kotlinResultType = types.make(.classType(ClassType(
            classSymbol: kotlinResultSymbol,
            args: [.invariant(kotlinResultTType)],
            nullability: .nonNull
        )))
        types.setNominalTypeParameterSymbols([kotlinResultTypeParamSymbol], for: kotlinResultSymbol)
        types.setNominalTypeParameterVariances([.out], for: kotlinResultSymbol)
        symbols.setPropertyType(kotlinResultType, for: kotlinResultSymbol)

        let continuationSymbol = ensureInterfaceSymbol(
            named: "Continuation",
            in: kotlinCoroutinesPkg,
            symbols: symbols,
            interner: interner
        )
        if let packageSymbol = symbols.lookup(fqName: kotlinCoroutinesPkg) {
            symbols.setParentSymbol(packageSymbol, for: continuationSymbol)
        }
        let continuationInterceptorSymbol = ensureInterfaceSymbol(
            named: "ContinuationInterceptor",
            in: kotlinCoroutinesPkg,
            symbols: symbols,
            interner: interner
        )
        let suspendFunctionSymbol = ensureInterfaceSymbol(
            named: "SuspendFunction",
            in: kotlinCoroutinesPkg,
            symbols: symbols,
            interner: interner
        )
        let suspendFunctionTypeParamName = interner.intern("R")
        let suspendFunctionTypeParamFQName = kotlinCoroutinesPkg + [
            interner.intern("SuspendFunction"),
            suspendFunctionTypeParamName,
        ]
        let suspendFunctionTypeParamSymbol: SymbolID = if let existing = symbols.lookup(fqName: suspendFunctionTypeParamFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: suspendFunctionTypeParamName,
                fqName: suspendFunctionTypeParamFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        symbols.setParentSymbol(suspendFunctionSymbol, for: suspendFunctionTypeParamSymbol)
        let suspendFunctionReturnType = types.make(.typeParam(TypeParamType(
            symbol: suspendFunctionTypeParamSymbol,
            nullability: .nonNull
        )))
        let suspendFunctionType = types.make(.classType(ClassType(
            classSymbol: suspendFunctionSymbol,
            args: [.out(suspendFunctionReturnType)],
            nullability: .nonNull
        )))
        types.setNominalTypeParameterSymbols([suspendFunctionTypeParamSymbol], for: suspendFunctionSymbol)
        types.setNominalTypeParameterVariances([.out], for: suspendFunctionSymbol)
        symbols.setPropertyType(suspendFunctionType, for: suspendFunctionSymbol)
        let continuationTypeParamName = interner.intern("T")
        let continuationTypeParamFQName = kotlinCoroutinesPkg + [interner.intern("Continuation"), continuationTypeParamName]
        let continuationTypeParamSymbol: SymbolID = if let existing = symbols.lookup(fqName: continuationTypeParamFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: continuationTypeParamName,
                fqName: continuationTypeParamFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        symbols.setParentSymbol(continuationSymbol, for: continuationTypeParamSymbol)
        let continuationTType = types.make(.typeParam(TypeParamType(
            symbol: continuationTypeParamSymbol,
            nullability: .nonNull
        )))
        let continuationType = types.make(.classType(ClassType(
            classSymbol: continuationSymbol,
            args: [.invariant(continuationTType)],
            nullability: .nonNull
        )))
        types.setNominalTypeParameterSymbols([continuationTypeParamSymbol], for: continuationSymbol)
        types.setNominalTypeParameterVariances([.in], for: continuationSymbol)
        symbols.setPropertyType(continuationType, for: continuationSymbol)
        let continuationTypeParameterSymbol = continuationTypeParamSymbol
        let continuationInterceptorType = types.make(.classType(ClassType(
            classSymbol: continuationInterceptorSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(continuationInterceptorType, for: continuationInterceptorSymbol)

        let continuationFactoryTypeParamName = interner.intern("T")
        let continuationFactoryTypeParamFQName = kotlinCoroutinesPkg + [
            interner.intern("Continuation"),
            interner.intern("$factory"),
            continuationFactoryTypeParamName,
        ]
        let continuationFactoryTypeParamSymbol: SymbolID = if let existing = symbols.lookup(fqName: continuationFactoryTypeParamFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: continuationFactoryTypeParamName,
                fqName: continuationFactoryTypeParamFQName,
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
        }
        let continuationFactoryTType = types.make(.typeParam(TypeParamType(
            symbol: continuationFactoryTypeParamSymbol,
            nullability: .nonNull
        )))

        context.kotlinCoroutineContextSymbol = kotlinCoroutineContextSymbol
        context.kotlinCoroutineContextType = kotlinCoroutineContextType
        context.kotlinResultSymbol = kotlinResultSymbol
        context.continuationSymbol = continuationSymbol
        context.continuationTypeParameterSymbol = continuationTypeParameterSymbol
        context.continuationTType = continuationTType
        context.continuationType = continuationType
        context.continuationInterceptorSymbol = continuationInterceptorSymbol
        context.continuationInterceptorType = continuationInterceptorType
        context.continuationFactoryTypeParamSymbol = continuationFactoryTypeParamSymbol
        context.continuationFactoryTType = continuationFactoryTType
    }

    func registerCoroutineNominalTypes(context: inout SyntheticCoroutineRegistryContext) {
        let symbols = context.symbols
        let types = context.types
        let interner = context.interner
        let kotlinPkg = context.kotlinPkg
        let coroutinesPkg = context.coroutinesPkg
        let channelsPkg = context.channelsPkg
        let flowPkg = context.flowPkg
        let kotlinCoroutinesCancellationPkg = context.kotlinCoroutinesCancellationPkg

        let throwableSymbol = ensureClassSymbol(
            named: "Throwable",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        let throwableType = types.make(.classType(ClassType(
            classSymbol: throwableSymbol,
            args: [],
            nullability: .nonNull
        )))
        let exceptionSymbol = ensureClassSymbol(
            named: "Exception",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        let exceptionType = types.make(.classType(ClassType(
            classSymbol: exceptionSymbol,
            args: [],
            nullability: .nonNull
        )))
        let coroutineScopeSymbol = ensureInterfaceSymbol(
            named: "CoroutineScope",
            in: coroutinesPkg,
            symbols: symbols,
            interner: interner
        )
        let coroutineScopeType = types.make(.classType(ClassType(
            classSymbol: coroutineScopeSymbol,
            args: [],
            nullability: .nonNull
        )))
        let jobSymbol = ensureInterfaceSymbol(
            named: "Job",
            in: coroutinesPkg,
            symbols: symbols,
            interner: interner
        )
        let deferredSymbol = ensureInterfaceSymbol(
            named: "Deferred",
            in: coroutinesPkg,
            symbols: symbols,
            interner: interner
        )
        let flowInterfaceSymbol = ensureInterfaceSymbol(
            named: "Flow",
            in: flowPkg,
            symbols: symbols,
            interner: interner
        )
        // KSP-675: SharedFlow / MutableSharedFlow are declared by bundled Kotlin
        // source (Sources/CompilerCore/Stdlib/kotlinx/coroutines/flow/SharedFlow.kt),
        // so no synthetic symbols are registered for them here.
        // KSP-676: StateFlow / MutableStateFlow are also bundled Kotlin source
        // (StateFlow.kt), so no synthetic symbols are registered for them either.
        // KSP-499 Stage 2: give the Flow interface a real generic type parameter
        // (previously `args: []` on every ClassType use, with the element type
        // tracked only in the Sema side-tables `flowElementTypesByExpr`/`BySymbol`
        // — see SemanticsModels.swift). Flow is read-only and covariant
        // (`Flow<out T>` in kotlinx.coroutines).
        // Pattern mirrors `registerSyntheticIterableStub` in
        // HeaderHelpers+SyntheticCollectionTypeFallbacks.swift.
        func declareFlowFamilyTypeParameter(
            owner: SymbolID,
            ownerFQName: [InternedString],
            variance: TypeVariance
        ) -> SymbolID {
            let typeParamName = interner.intern("T")
            let typeParamFQName = ownerFQName + [typeParamName]
            let typeParamSymbol: SymbolID = if let existing = symbols.lookup(fqName: typeParamFQName) {
                existing
            } else {
                symbols.define(
                    kind: .typeParameter,
                    name: typeParamName,
                    fqName: typeParamFQName,
                    declSite: nil,
                    visibility: .private,
                    flags: []
                )
            }
            types.setNominalTypeParameterSymbols([typeParamSymbol], for: owner)
            types.setNominalTypeParameterVariances([variance], for: owner)
            return typeParamSymbol
        }
        let flowTypeParamSymbol = declareFlowFamilyTypeParameter(
            owner: flowInterfaceSymbol,
            ownerFQName: flowPkg + [interner.intern("Flow")],
            variance: .out
        )
        let dispatcherSymbol = ensureClassSymbol(
            named: "CoroutineDispatcher",
            in: coroutinesPkg,
            symbols: symbols,
            interner: interner
        )
        symbols.insertFlags([.openType, .abstractType], for: dispatcherSymbol)
        let channelSymbol = ensureClassSymbol(
            named: "Channel",
            in: channelsPkg,
            symbols: symbols,
            interner: interner
        )
        // KSP-1573: `Channel.Factory` companion anchor. The bundled
        // RENDEZVOUS / UNLIMITED / CONFLATED / BUFFERED / OPTIONAL_CHANNEL
        // constants in Stdlib/kotlinx/coroutines/channels/Channel.kt are
        // extension properties on this companion, so `Channel.X` and
        // `Channel.Factory.X` both resolve.
        if symbols.companionObjectSymbol(for: channelSymbol) == nil {
            let factoryName = interner.intern("Factory")
            let factoryFQName = channelsPkg
                + [interner.intern("Channel"), factoryName]
            if let existing = symbols.lookupAll(fqName: factoryFQName).first(where: { symbolID in
                guard let symbol = symbols.symbol(symbolID) else { return false }
                return symbol.kind == .object || symbol.kind == .class || symbol.kind == .interface
            }) {
                symbols.setParentSymbol(channelSymbol, for: existing)
                symbols.setCompanionObjectSymbol(existing, for: channelSymbol)
            } else {
                let factorySymbol = symbols.define(
                    kind: .object,
                    name: factoryName,
                    fqName: factoryFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic, .static]
                )
                symbols.setParentSymbol(channelSymbol, for: factorySymbol)
                symbols.setCompanionObjectSymbol(factorySymbol, for: channelSymbol)
            }
        }
        // KSP-678: `ChannelIterator<T>` is the runtime handle returned by
        // `Channel<T>.iterator()`. Registered as a synthetic handle type (like
        // Channel itself) so the bundled Kotlin iterator/hasNext/next extension
        // operators in Channels.kt can bridge to the residual
        // kk_channel_iterator{,_hasNext,_next} runtime entry points.
        let channelIteratorSymbol = ensureClassSymbol(
            named: "ChannelIterator",
            in: channelsPkg,
            symbols: symbols,
            interner: interner
        )
        let cancellationSymbol = ensureClassSymbol(
            named: "CancellationException",
            in: kotlinCoroutinesCancellationPkg,
            symbols: symbols,
            interner: interner
        )
        let cancellationIsSourceBacked = symbols.isSourceBackedSymbol(cancellationSymbol)
        let illegalStateExceptionSymbol: SymbolID?
        if cancellationIsSourceBacked {
            illegalStateExceptionSymbol = nil
        } else {
            illegalStateExceptionSymbol = ensureClassSymbol(
                named: "IllegalStateException",
                in: kotlinPkg,
                symbols: symbols,
                interner: interner
            )
        }
        let rootCancellationSymbol: SymbolID = if cancellationIsSourceBacked {
            cancellationSymbol
        } else if let existing = symbols.lookup(fqName: [interner.intern("CancellationException")]) {
            existing
        } else {
            symbols.define(
                kind: .class,
                name: interner.intern("CancellationException"),
                fqName: [interner.intern("CancellationException")],
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        let jobType = types.make(.classType(ClassType(
            classSymbol: jobSymbol,
            args: [],
            nullability: .nonNull
        )))
        // Source-backed `Deferred<out T>` (#7485 / KSP-1564) carries one
        // class-level type parameter. Residual `async` registration often runs
        // before that declaration is attached when CompilerCoreTests compile
        // the bundled stdlib from source, so `isSourceBackedSymbol` is still
        // false here. Always emit the generic shape: `await()` member matching
        // requires `ClassType.args` to agree with the parameter list once
        // source processing finishes. A raw `Deferred` (zero args) is what
        // made `async { 7 }.await()` report KSWIFTK-SEMA-0002 in the harness
        // even though the `async` call itself type-checked.
        // KUU-2673: `Deferred<out T>`'s bundled declaration always carries
        // exactly one type parameter, so an unmaterialized imported shell uses
        // the same one-argument shape instead of decoding the record just for
        // the count (the count == 0 fallback below already emits one arg).
        let deferredTypeParameterCount = symbols.hasPendingImportedNominalMetadata(for: deferredSymbol)
            ? 1
            : types.nominalTypeParameterSymbols(for: deferredSymbol).count
        let deferredTypeArgs: [TypeArg] = deferredTypeParameterCount > 0
            ? Array(repeating: .out(types.nullableAnyType), count: deferredTypeParameterCount)
            : [.out(types.nullableAnyType)]
        let deferredType = types.make(.classType(ClassType(
            classSymbol: deferredSymbol,
            args: deferredTypeArgs,
            nullability: .nonNull
        )))
        // KSP-499 Stage 2: use each class's own type parameter as the receiver
        // "self type" (matching `iterableReceiverType` in
        // HeaderHelpers+SyntheticCollectionTypeFallbacks.swift) instead of a raw,
        // argument-less ClassType. This is the generic *declaration* shape used
        // as an owner/receiver/return type placeholder throughout this file —
        // callers substitute concrete element types at actual call sites.
        let flowRawType = types.make(.classType(ClassType(
            classSymbol: flowInterfaceSymbol,
            args: [.out(types.make(.typeParam(TypeParamType(symbol: flowTypeParamSymbol, nullability: .nonNull))))],
            nullability: .nonNull
        )))
        let dispatcherType = types.make(.classType(ClassType(
            classSymbol: dispatcherSymbol,
            args: [],
            nullability: .nonNull
        )))
        let coroutineStartSymbol = ensureEnumClassSymbol(
            named: "CoroutineStart",
            in: coroutinesPkg,
            symbols: symbols,
            interner: interner
        )
        let coroutineStartType = types.make(.classType(ClassType(
            classSymbol: coroutineStartSymbol,
            args: [],
            nullability: .nonNull
        )))
        let coroutineStartFQName = coroutinesPkg + [interner.intern("CoroutineStart")]
        for entryName in ["DEFAULT", "LAZY", "ATOMIC", "UNDISPATCHED"] {
            let entryInterned = interner.intern(entryName)
            let entryFQName = coroutineStartFQName + [entryInterned]
            if symbols.lookup(fqName: entryFQName) == nil {
                let entrySymbol = symbols.define(
                    kind: .field,
                    name: entryInterned,
                    fqName: entryFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
                symbols.setParentSymbol(coroutineStartSymbol, for: entrySymbol)
                symbols.setPropertyType(coroutineStartType, for: entrySymbol)
            }
        }
        // `CoroutineStart.isLazy`: a compile-time-folded member. The enum
        // entries are symbolic markers consumed by the launch/async start-mode
        // rewrite and carry no distinct runtime value (name/ordinal/equality
        // all collapse), so the property cannot be implemented as a runtime
        // comparison. Reads lower to this external name and
        // CoroutineLoweringPass rewrites each call to a Boolean constant from
        // the referenced entry, mirroring the launcher fallback (an
        // unresolved receiver folds to `false`, i.e. non-LAZY).
        registerSyntheticObjectProperty(
            ownerSymbol: coroutineStartSymbol,
            ownerType: coroutineStartType,
            name: "isLazy",
            propertyType: types.booleanType,
            externalLinkName: "kk_coroutine_start_is_lazy",
            symbols: symbols,
            interner: interner
        )
        let channelType = types.make(.classType(ClassType(
            classSymbol: channelSymbol,
            args: [],
            nullability: .nonNull
        )))
        let channelIteratorType = types.make(.classType(ClassType(
            classSymbol: channelIteratorSymbol,
            args: [],
            nullability: .nonNull
        )))
        let cancellationType = types.make(.classType(ClassType(
            classSymbol: cancellationSymbol,
            args: [],
            nullability: .nonNull
        )))

        context.throwableSymbol = throwableSymbol
        context.throwableType = throwableType
        context.exceptionSymbol = exceptionSymbol
        context.exceptionType = exceptionType
        context.coroutineScopeSymbol = coroutineScopeSymbol
        context.coroutineScopeType = coroutineScopeType
        context.jobSymbol = jobSymbol
        context.jobType = jobType
        context.deferredSymbol = deferredSymbol
        context.deferredType = deferredType
        context.flowInterfaceSymbol = flowInterfaceSymbol
        context.flowTypeParamSymbol = flowTypeParamSymbol
        context.flowRawType = flowRawType
        context.dispatcherSymbol = dispatcherSymbol
        context.dispatcherType = dispatcherType
        context.channelSymbol = channelSymbol
        context.channelType = channelType
        context.channelIteratorSymbol = channelIteratorSymbol
        context.channelIteratorType = channelIteratorType
        context.coroutineStartSymbol = coroutineStartSymbol
        context.coroutineStartType = coroutineStartType
        context.cancellationSymbol = cancellationSymbol
        context.cancellationType = cancellationType
        context.cancellationIsSourceBacked = cancellationIsSourceBacked
        context.illegalStateExceptionSymbol = illegalStateExceptionSymbol
        context.rootCancellationSymbol = rootCancellationSymbol
    }
}
