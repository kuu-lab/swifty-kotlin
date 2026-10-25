extension DataFlowSemaPhase {
    func registerCoroutineContextHierarchy(context: inout SyntheticCoroutineRegistryContext) {
        let symbols = context.symbols
        let types = context.types
        let interner = context.interner
        let bundledIndex = context.bundledIndex
        let kotlinCoroutinesPkg = context.kotlinCoroutinesPkg
        let coroutinesPkg = context.coroutinesPkg
        let jobSymbol = context.jobSymbol!
        let deferredSymbol = context.deferredSymbol!

        let coroutineContextSymbol = ensureInterfaceSymbol(
            named: "CoroutineContext",
            in: kotlinCoroutinesPkg,
            symbols: symbols,
            interner: interner
        )
        let coroutineContextType = types.make(.classType(ClassType(
            classSymbol: coroutineContextSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(coroutineContextType, for: coroutineContextSymbol)

        let coroutineContextFQName = kotlinCoroutinesPkg + [interner.intern("CoroutineContext")]
        let coroutineContextElementSymbol = ensureInterfaceSymbol(
            named: "Element",
            in: coroutineContextFQName,
            symbols: symbols,
            interner: interner,
            visibility: .public
        )
        symbols.setParentSymbol(coroutineContextSymbol, for: coroutineContextElementSymbol)
        let coroutineContextElementType = types.make(.classType(ClassType(
            classSymbol: coroutineContextElementSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(coroutineContextElementType, for: coroutineContextElementSymbol)
        symbols.setDirectSupertypes([coroutineContextSymbol], for: coroutineContextElementSymbol)
        types.setNominalDirectSupertypes([coroutineContextSymbol], for: coroutineContextElementSymbol)
        if !symbols.isSourceBackedSymbol(jobSymbol) {
            symbols.setDirectSupertypes([coroutineContextElementSymbol], for: jobSymbol)
            types.setNominalDirectSupertypes([coroutineContextElementSymbol], for: jobSymbol)
        }
        if !symbols.isSourceBackedSymbol(deferredSymbol) {
            symbols.setDirectSupertypes([jobSymbol], for: deferredSymbol)
            types.setNominalDirectSupertypes([jobSymbol], for: deferredSymbol)
        }

        if !bundledIndex.contains(ownerFQName: kotlinCoroutinesPkg + [interner.intern("CoroutineContext")], name: interner.intern("isActive"), arity: 0) {
            // `kotlinx.coroutines.isActive`: an extension on CoroutineContext (not just
            // CoroutineScope/Job) so `currentCoroutineContext().isActive` resolves.
            // Mirrors `this[Job]?.isActive ?: true` -- a context with no Job element is
            // considered active.
            registerSyntheticObjectProperty(
                ownerSymbol: coroutineContextSymbol,
                ownerType: coroutineContextType,
                name: "isActive",
                propertyType: types.booleanType,
                externalLinkName: "kk_context_is_active",
                symbols: symbols,
                interner: interner
            )
        }

        // NonCancellable is referenced bare (not via member access), so it
        // resolves through the object-with-externalLinkName path in ExprLowerer.
        let nonCancellableSymbol = ensureSyntheticObjectSymbol(
            named: "NonCancellable",
            in: coroutinesPkg,
            symbols: symbols,
            interner: interner
        )
        let nonCancellableType = types.make(.classType(ClassType(
            classSymbol: nonCancellableSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(nonCancellableType, for: nonCancellableSymbol)
        // KSP-1568: NonCancellable is now a bundled `object : AbstractCoroutineContextElement(Key)`
        // (Stdlib/kotlinx/coroutines/NonCancellable.kt) implementing the
        // degenerate always-active Job surface in source. The bundled decl is
        // reused by ensureSyntheticObjectSymbol above and keeps the
        // `kk_non_cancellable_instance` external link name so bare references
        // still materialize the runtime job handle. Graft `Job` onto its
        // supertypes so `val j: Job = NonCancellable` / Job-typed parameters
        // conform, preferring the bundled AbstractCoroutineContextElement as
        // the element supertype so the inherited `key` member keeps
        // resolving.
        let nonCancellableElementSupertype = symbols.lookup(
            fqName: kotlinCoroutinesPkg + [interner.intern("AbstractCoroutineContextElement")]
        ) ?? coroutineContextElementSymbol
        symbols.setDirectSupertypes([nonCancellableElementSupertype, jobSymbol], for: nonCancellableSymbol)
        types.setNominalDirectSupertypes([nonCancellableElementSupertype, jobSymbol], for: nonCancellableSymbol)
        symbols.setExternalLinkName("kk_non_cancellable_instance", for: nonCancellableSymbol)

        let coroutineContextKeySymbol = ensureInterfaceSymbol(
            named: "Key",
            in: coroutineContextFQName,
            symbols: symbols,
            interner: interner,
            visibility: .public
        )
        symbols.setParentSymbol(coroutineContextSymbol, for: coroutineContextKeySymbol)
        let coroutineContextKeyTypeParamName = interner.intern("E")
        let coroutineContextKeyTypeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: coroutineContextKeyTypeParamName,
            fqName: coroutineContextFQName + [interner.intern("Key"), interner.intern("$synthetic"), coroutineContextKeyTypeParamName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(coroutineContextKeySymbol, for: coroutineContextKeyTypeParamSymbol)
        types.setNominalTypeParameterSymbols([coroutineContextKeyTypeParamSymbol], for: coroutineContextKeySymbol)
        types.setNominalTypeParameterVariances([.invariant], for: coroutineContextKeySymbol)
        let coroutineContextKeyTypeParamType = types.make(.typeParam(TypeParamType(
            symbol: coroutineContextKeyTypeParamSymbol,
            nullability: .nonNull
        )))
        symbols.setTypeParameterUpperBounds([coroutineContextElementType], for: coroutineContextKeyTypeParamSymbol)
        let coroutineContextKeyType = types.make(.classType(ClassType(
            classSymbol: coroutineContextKeySymbol,
            args: [.invariant(coroutineContextKeyTypeParamType)],
            nullability: .nonNull
        )))
        symbols.setPropertyType(coroutineContextKeyType, for: coroutineContextKeySymbol)

        let coroutineContextKeyTypeParamBound = coroutineContextElementType

        do {
            let functionName = interner.intern("get")
            let functionFQName = coroutineContextFQName + [functionName]
            if symbols.lookup(fqName: functionFQName) == nil,
               !bundledIndex.contains(ownerFQName: coroutineContextFQName, name: functionName, arity: 1)
            {
                let functionSymbol = symbols.define(
                    kind: .function,
                    name: functionName,
                    fqName: functionFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
                symbols.setParentSymbol(coroutineContextSymbol, for: functionSymbol)
                let functionTypeParamName = interner.intern("E")
                let functionTypeParamSymbol = symbols.define(
                    kind: .typeParameter,
                    name: functionTypeParamName,
                    fqName: functionFQName + [interner.intern("$synthetic"), functionTypeParamName],
                    declSite: nil,
                    visibility: .private,
                    flags: [.synthetic]
                )
                let functionTypeParamType = types.make(.typeParam(TypeParamType(
                    symbol: functionTypeParamSymbol,
                    nullability: .nonNull
                )))
                symbols.setTypeParameterUpperBounds([coroutineContextKeyTypeParamBound], for: functionTypeParamSymbol)

                let keyType = types.make(.classType(ClassType(
                    classSymbol: coroutineContextKeySymbol,
                    args: [.invariant(functionTypeParamType)],
                    nullability: .nonNull
                )))
                let keyParamName = interner.intern("key")
                let keyParamSymbol = symbols.define(
                    kind: .valueParameter,
                    name: keyParamName,
                    fqName: functionFQName + [keyParamName],
                    declSite: nil,
                    visibility: .private,
                    flags: [.synthetic]
                )
                symbols.setParentSymbol(functionSymbol, for: keyParamSymbol)
                symbols.setFunctionSignature(
                    FunctionSignature(
                        parameterTypes: [keyType],
                        returnType: types.makeNullable(functionTypeParamType),
                        valueParameterSymbols: [keyParamSymbol],
                        valueParameterHasDefaultValues: [false],
                        valueParameterIsVararg: [false],
                        typeParameterSymbols: [functionTypeParamSymbol],
                        typeParameterUpperBoundsList: [[coroutineContextKeyTypeParamBound]]
                    ),
                    for: functionSymbol
                )
                symbols.setExternalLinkName("kk_context_get", for: functionSymbol)
            }
        }

        do {
            let functionName = interner.intern("fold")
            let functionFQName = coroutineContextFQName + [functionName]
            if symbols.lookup(fqName: functionFQName) == nil,
               !bundledIndex.contains(ownerFQName: coroutineContextFQName, name: functionName, arity: 2)
            {
                let functionSymbol = symbols.define(
                    kind: .function,
                    name: functionName,
                    fqName: functionFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
                symbols.setParentSymbol(coroutineContextSymbol, for: functionSymbol)
                let rTypeParamName = interner.intern("R")
                let rTypeParamSymbol = symbols.define(
                    kind: .typeParameter,
                    name: rTypeParamName,
                    fqName: functionFQName + [interner.intern("$synthetic"), rTypeParamName],
                    declSite: nil,
                    visibility: .private,
                    flags: [.synthetic]
                )
                let rType = types.make(.typeParam(TypeParamType(
                    symbol: rTypeParamSymbol,
                    nullability: .nonNull
                )))
                let operationType = types.make(.functionType(FunctionType(
                    params: [rType, coroutineContextElementType],
                    returnType: rType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
                let initialParamName = interner.intern("initial")
                let initialParamSymbol = symbols.define(
                    kind: .valueParameter,
                    name: initialParamName,
                    fqName: functionFQName + [initialParamName],
                    declSite: nil,
                    visibility: .private,
                    flags: [.synthetic]
                )
                let operationParamName = interner.intern("operation")
                let operationParamSymbol = symbols.define(
                    kind: .valueParameter,
                    name: operationParamName,
                    fqName: functionFQName + [operationParamName],
                    declSite: nil,
                    visibility: .private,
                    flags: [.synthetic]
                )
                symbols.setParentSymbol(functionSymbol, for: initialParamSymbol)
                symbols.setParentSymbol(functionSymbol, for: operationParamSymbol)
                symbols.setFunctionSignature(
                    FunctionSignature(
                        parameterTypes: [rType, operationType],
                        returnType: rType,
                        valueParameterSymbols: [initialParamSymbol, operationParamSymbol],
                        valueParameterHasDefaultValues: [false, false],
                        valueParameterIsVararg: [false, false],
                        typeParameterSymbols: [rTypeParamSymbol]
                    ),
                    for: functionSymbol
                )
                symbols.setExternalLinkName("kk_context_fold", for: functionSymbol)
            }
        }

        do {
            let functionName = interner.intern("minusKey")
            let functionFQName = coroutineContextFQName + [functionName]
            if symbols.lookup(fqName: functionFQName) == nil,
               !bundledIndex.contains(ownerFQName: coroutineContextFQName, name: functionName, arity: 1)
            {
                let functionSymbol = symbols.define(
                    kind: .function,
                    name: functionName,
                    fqName: functionFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
                symbols.setParentSymbol(coroutineContextSymbol, for: functionSymbol)
                let keyType = types.make(.classType(ClassType(
                    classSymbol: coroutineContextKeySymbol,
                    args: [.star],
                    nullability: .nonNull
                )))
                let keyParamName = interner.intern("key")
                let keyParamSymbol = symbols.define(
                    kind: .valueParameter,
                    name: keyParamName,
                    fqName: functionFQName + [keyParamName],
                    declSite: nil,
                    visibility: .private,
                    flags: [.synthetic]
                )
                symbols.setParentSymbol(functionSymbol, for: keyParamSymbol)
                symbols.setFunctionSignature(
                    FunctionSignature(
                        parameterTypes: [keyType],
                        returnType: coroutineContextType,
                        valueParameterSymbols: [keyParamSymbol],
                        valueParameterHasDefaultValues: [false],
                        valueParameterIsVararg: [false]
                    ),
                    for: functionSymbol
                )
                symbols.setExternalLinkName("kk_context_minusKey", for: functionSymbol)
            }
        }

        context.coroutineContextSymbol = coroutineContextSymbol
        context.coroutineContextType = coroutineContextType
        context.coroutineContextFQName = coroutineContextFQName
        context.coroutineContextElementSymbol = coroutineContextElementSymbol
        context.coroutineContextKeySymbol = coroutineContextKeySymbol
    }

    func registerCoroutineContextElements(context: inout SyntheticCoroutineRegistryContext) {
        let symbols = context.symbols
        let types = context.types
        let interner = context.interner
        let bundledIndex = context.bundledIndex
        let kotlinCoroutinesPkg = context.kotlinCoroutinesPkg
        let coroutineContextSymbol = context.coroutineContextSymbol!
        let coroutineContextType = context.coroutineContextType!
        let rootCancellationType = context.rootCancellationType!
        let coroutinesPkg = context.coroutinesPkg
        let coroutineContextElementSymbol = context.coroutineContextElementSymbol!
        let coroutineContextKeySymbol = context.coroutineContextKeySymbol!
        let dispatcherSymbol = context.dispatcherSymbol!
        let continuationInterceptorSymbol = context.continuationInterceptorSymbol!
        let kotlinCoroutineContextType = context.kotlinCoroutineContextType!
        let throwableType = context.throwableType!

        if !bundledIndex.contains(ownerFQName: kotlinCoroutinesPkg + [interner.intern("CoroutineContext")], name: interner.intern("cancel"), arity: 1) {
            let coroutineContextMembers = coroutineMemberRows(of: coroutineContextSymbol, type: coroutineContextType, symbols: symbols, interner: interner)
            coroutineContextMembers.fn("cancel", "kk_context_cancel_no_cause", ret: types.unitType, flags: [.synthetic])
            coroutineContextMembers.fn("cancel", "kk_context_cancel", [(name: "cause", type: types.makeNullable(rootCancellationType))], ret: types.unitType, flags: [.synthetic])
        }

        let coroutineNameSymbol = ensureClassSymbol(
            named: "CoroutineName",
            in: coroutinesPkg,
            symbols: symbols,
            interner: interner
        )
        let coroutineNameType = types.make(.classType(ClassType(
            classSymbol: coroutineNameSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(coroutineNameType, for: coroutineNameSymbol)
        let coroutineNameFQName = coroutinesPkg + [interner.intern("CoroutineName")]
        let hasBundledCoroutineName = bundledIndex.containsNominal(fqName: coroutineNameFQName)
        if !hasBundledCoroutineName {
            symbols.setDirectSupertypes([coroutineContextElementSymbol], for: coroutineNameSymbol)
            types.setNominalDirectSupertypes([coroutineContextElementSymbol], for: coroutineNameSymbol)
        }

        let coroutineExceptionHandlerSymbol = ensureClassSymbol(
            named: "CoroutineExceptionHandler",
            in: coroutinesPkg,
            symbols: symbols,
            interner: interner
        )
        let coroutineExceptionHandlerType = types.make(.classType(ClassType(
            classSymbol: coroutineExceptionHandlerSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(coroutineExceptionHandlerType, for: coroutineExceptionHandlerSymbol)
        // KUU-1405: CoroutineExceptionHandler is a CoroutineContext.Element
        // (kotlinx declares `interface CoroutineExceptionHandler :
        // CoroutineContext.Element`), which its companion Key must satisfy
        // for `ctx[CoroutineExceptionHandler]` to type-check.
        symbols.setDirectSupertypes([coroutineContextElementSymbol, coroutineContextSymbol], for: coroutineExceptionHandlerSymbol)
        types.setNominalDirectSupertypes([coroutineContextElementSymbol, coroutineContextSymbol], for: coroutineExceptionHandlerSymbol)

        // KUU-1405: The companion `Key` materializes the `kk_exception_handler_key`
        // singleton so `ctx[CoroutineExceptionHandler]` / `minusKey` resolve like Job.Key.
        if symbols.companionObjectSymbol(for: coroutineExceptionHandlerSymbol) == nil {
            let keyName = interner.intern("Key")
            let keyFQName = coroutinesPkg
                + [interner.intern("CoroutineExceptionHandler"), keyName]
            let cehKeySymbol = symbols.lookup(fqName: keyFQName) ?? symbols.define(
                kind: .object,
                name: keyName,
                fqName: keyFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .static]
            )
            symbols.setParentSymbol(coroutineExceptionHandlerSymbol, for: cehKeySymbol)
            symbols.setCompanionObjectSymbol(cehKeySymbol, for: coroutineExceptionHandlerSymbol)
            symbols.setDirectSupertypes([coroutineContextKeySymbol], for: cehKeySymbol)
            types.setNominalDirectSupertypes([coroutineContextKeySymbol], for: cehKeySymbol)
            symbols.setSupertypeTypeArgs(
                [.invariant(coroutineExceptionHandlerType)],
                for: cehKeySymbol,
                supertype: coroutineContextKeySymbol
            )
            types.setNominalSupertypeTypeArgs(
                [.invariant(coroutineExceptionHandlerType)],
                for: cehKeySymbol,
                supertype: coroutineContextKeySymbol
            )
            let cehKeyType = types.make(.classType(ClassType(
                classSymbol: cehKeySymbol,
                args: [],
                nullability: .nonNull
            )))
            symbols.setPropertyType(cehKeyType, for: cehKeySymbol)
            symbols.setExternalLinkName("kk_exception_handler_key", for: cehKeySymbol)
        }

        if !symbols.isSourceBackedSymbol(dispatcherSymbol) {
            symbols.setDirectSupertypes([coroutineContextSymbol, continuationInterceptorSymbol], for: dispatcherSymbol)
            types.setNominalDirectSupertypes([coroutineContextSymbol, continuationInterceptorSymbol], for: dispatcherSymbol)
        }

        let flowBuilderLambdaType = types.make(.functionType(FunctionType(
            params: [],
            returnType: types.unitType,
            isSuspend: true,
            nullability: .nonNull
        )))

        // The bundled constructor allocates the runtime-owned name handle.
        if !hasBundledCoroutineName {
            registerSyntheticCoroutineTopLevelFunction(
                named: "CoroutineName",
                packageFQName: coroutinesPkg,
                parameters: [(name: "name", type: types.stringType)],
                returnType: coroutineNameType,
                externalLinkName: "kk_coroutine_name_create",
                symbols: symbols,
                interner: interner
            )
            registerSyntheticCoroutineConstructor(
                ownerSymbol: coroutineNameSymbol,
                ownerType: coroutineNameType,
                externalLinkName: "kk_coroutine_name_create",
                parameters: [(name: "name", type: types.stringType)],
                symbols: symbols,
                interner: interner
            )
        }

        registerSyntheticCoroutineTopLevelFunction(
            named: "CoroutineExceptionHandler",
            packageFQName: coroutinesPkg,
            parameters: [(name: "handler", type: types.make(.functionType(FunctionType(
                params: [kotlinCoroutineContextType, throwableType],
                returnType: types.unitType,
                isSuspend: false,
                nullability: .nonNull
            ))))],
            returnType: coroutineExceptionHandlerType,
            externalLinkName: "kk_exception_handler_create",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCoroutineConstructor(
            ownerSymbol: coroutineExceptionHandlerSymbol,
            ownerType: coroutineExceptionHandlerType,
            externalLinkName: "kk_exception_handler_create",
            parameters: [(name: "handler", type: types.make(.functionType(FunctionType(
                params: [kotlinCoroutineContextType, throwableType],
                returnType: types.unitType,
                isSuspend: false,
                nullability: .nonNull
            ))))],
            symbols: symbols,
            interner: interner
        )
        let coroutineExceptionHandlerMembers = coroutineMemberRows(of: coroutineExceptionHandlerSymbol, type: coroutineExceptionHandlerType, symbols: symbols, interner: interner)
        coroutineExceptionHandlerMembers.fn(
            "handleException", "kk_exception_handler_invoke", [(name: "context", type: kotlinCoroutineContextType), (name: "exception", type: throwableType)],
            ret: types.unitType
        )
        if !bundledIndex.contains(
            ownerFQName: coroutinesPkg,
            name: interner.intern("handleCoroutineException"),
            arity: 2
        ) {
            registerSyntheticCoroutineTopLevelFunction(
                named: "handleCoroutineException",
                packageFQName: coroutinesPkg,
                parameters: [
                    (name: "context", type: kotlinCoroutineContextType),
                    (name: "exception", type: throwableType),
                ],
                returnType: types.unitType,
                externalLinkName: "kk_handle_coroutine_exception",
                symbols: symbols,
                interner: interner
            )
        }

        context.coroutineNameSymbol = coroutineNameSymbol
        context.coroutineNameType = coroutineNameType
        context.hasBundledCoroutineName = hasBundledCoroutineName
        context.coroutineExceptionHandlerSymbol = coroutineExceptionHandlerSymbol
        context.coroutineExceptionHandlerType = coroutineExceptionHandlerType
        context.flowBuilderLambdaType = flowBuilderLambdaType
    }

    func registerCoroutineContextPlusOperators(context: inout SyntheticCoroutineRegistryContext) {
        let symbols = context.symbols
        let interner = context.interner
        let bundledIndex = context.bundledIndex
        let coroutineContextFQName = context.coroutineContextFQName
        let coroutineContextSymbol = context.coroutineContextSymbol!
        let coroutineContextType = context.coroutineContextType!
        let kotlinCoroutineContextType = context.kotlinCoroutineContextType!
        let dispatcherSymbol = context.dispatcherSymbol!
        let dispatcherType = context.dispatcherType!
        let hasBundledCoroutineName = context.hasBundledCoroutineName
        let coroutineNameSymbol = context.coroutineNameSymbol!
        let coroutineNameType = context.coroutineNameType!
        let coroutineExceptionHandlerSymbol = context.coroutineExceptionHandlerSymbol!
        let coroutineExceptionHandlerType = context.coroutineExceptionHandlerType!
        let jobSymbol = context.jobSymbol!
        let jobType = context.jobType!

        if !bundledIndex.contains(
            ownerFQName: coroutineContextFQName,
            name: interner.intern("plus"),
            arity: 1
        ) {
            let coroutineContextMembers = coroutineMemberRows(of: coroutineContextSymbol, type: coroutineContextType, symbols: symbols, interner: interner)
            coroutineContextMembers.fn(
                "plus", "__kk_context_plus_dispatch", [(name: "context", type: kotlinCoroutineContextType)],
                ret: kotlinCoroutineContextType, flags: [.synthetic, .operatorFunction]
            )
        }
        let dispatcherMembers = coroutineMemberRows(of: dispatcherSymbol, type: dispatcherType, symbols: symbols, interner: interner)
        dispatcherMembers.fn(
            "plus", "kk_context_plus", [(name: "context", type: kotlinCoroutineContextType)],
            ret: kotlinCoroutineContextType, flags: [.synthetic, .operatorFunction]
        )
        if !hasBundledCoroutineName {
            let coroutineNameMembers = coroutineMemberRows(of: coroutineNameSymbol, type: coroutineNameType, symbols: symbols, interner: interner)
            coroutineNameMembers.fn(
                "plus", "kk_context_plus", [(name: "context", type: kotlinCoroutineContextType)],
                ret: kotlinCoroutineContextType, flags: [.synthetic, .operatorFunction]
            )
        }
        let coroutineExceptionHandlerMembers = coroutineMemberRows(of: coroutineExceptionHandlerSymbol, type: coroutineExceptionHandlerType, symbols: symbols, interner: interner)
        coroutineExceptionHandlerMembers.fn(
            "plus", "kk_context_plus", [(name: "context", type: kotlinCoroutineContextType)],
            ret: kotlinCoroutineContextType, flags: [.synthetic, .operatorFunction]
        )
        let jobMembers = coroutineMemberRows(of: jobSymbol, type: jobType, symbols: symbols, interner: interner)
        jobMembers.fn("plus", "kk_context_plus", [(name: "context", type: kotlinCoroutineContextType)], ret: kotlinCoroutineContextType, flags: [.synthetic, .operatorFunction])
    }

    func registerEmptyCoroutineContextStub(context: inout SyntheticCoroutineRegistryContext) {
        let symbols = context.symbols
        let types = context.types
        let interner = context.interner
        let bundledIndex = context.bundledIndex
        let kotlinCoroutinesPkg = context.kotlinCoroutinesPkg
        let kotlinCoroutineContextSymbol = context.kotlinCoroutineContextSymbol!

        // KSP-1145: the public object and its six members are bundled Kotlin
        // source. Keep the synthetic object only for configurations that do
        // not inject/import that source.
        let emptyCoroutineContextFQName = kotlinCoroutinesPkg + [interner.intern("EmptyCoroutineContext")]
        let hasSourceBackedEmptyCoroutineContext = bundledIndex.contains(
            ownerFQName: emptyCoroutineContextFQName,
            name: interner.intern("fold"),
            arity: 2
        )
        if !hasSourceBackedEmptyCoroutineContext {
            let emptyCoroutineContextSymbol = ensureSyntheticObjectSymbol(
                named: "EmptyCoroutineContext",
                in: kotlinCoroutinesPkg,
                symbols: symbols,
                interner: interner
            )
            let emptyCoroutineContextType = types.make(.classType(ClassType(
                classSymbol: emptyCoroutineContextSymbol,
                args: [],
                nullability: .nonNull
            )))
            symbols.setPropertyType(emptyCoroutineContextType, for: emptyCoroutineContextSymbol)
            symbols.setDirectSupertypes([kotlinCoroutineContextSymbol], for: emptyCoroutineContextSymbol)
            types.setNominalDirectSupertypes([kotlinCoroutineContextSymbol], for: emptyCoroutineContextSymbol)
        }
    }

    func registerCoroutineCancellationExtension(context: inout SyntheticCoroutineRegistryContext) {
        let symbols = context.symbols
        let types = context.types
        let interner = context.interner
        let bundledIndex = context.bundledIndex
        let kotlinCoroutinesPkg = context.kotlinCoroutinesPkg
        let kotlinCoroutinesCancellationPkg = context.kotlinCoroutinesCancellationPkg
        let kotlinCoroutineContextType = context.kotlinCoroutineContextType!
        let rootCancellationType = context.rootCancellationType!

        if !bundledIndex.contains(ownerFQName: kotlinCoroutinesPkg + [interner.intern("CoroutineContext")], name: interner.intern("cancel"), arity: 1) {
            registerSyntheticCoroutineExtensionFunction(
                named: "cancel",
                packageFQName: kotlinCoroutinesCancellationPkg,
                receiverType: kotlinCoroutineContextType,
                externalLinkName: "kk_context_cancel",
                returnType: types.unitType,
                parameters: [(name: "cause", type: types.makeNullable(rootCancellationType))],
                symbols: symbols,
                interner: interner
            )
        }
    }
}
