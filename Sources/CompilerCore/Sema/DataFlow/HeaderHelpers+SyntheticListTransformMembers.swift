import RuntimeABI

/// `List<E>.map` / `flatMap` / `mapNotNull` / `filter` / `mapIndexed` /
/// other transform members extracted from `HeaderHelpers+SyntheticListStubs.swift`.
extension DataFlowSemaPhase {
    func registerListTransformMembers(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        listFQName: [InternedString],
        listInterfaceSymbol: SymbolID,
        listTypeParamSymbol: SymbolID,
        listTypeParamType: TypeID,
        collectionInterfaceSymbol: SymbolID,
        bundledIndex: BundledDeclarationIndex = .empty,
        skipStats: SyntheticStubSkipStatsCollector? = nil
    ) {
        let receiverType = types.make(.classType(ClassType(
            classSymbol: listInterfaceSymbol,
            args: [.out(listTypeParamType)],
            nullability: .nonNull
        )))
        let listReturnType = receiverType
        if types.comparableInterfaceSymbol == nil {
            registerSyntheticComparableStub(symbols: symbols, types: types, interner: interner)
        }
        let comparableElementBounds: [TypeID] = if let comparableSymbol = types.comparableInterfaceSymbol {
            [types.make(.classType(ClassType(
                classSymbol: comparableSymbol,
                args: [.invariant(listTypeParamType)],
                nullability: .nonNull
            )))]
        } else {
            []
        }

        // Register a synthetic member on List. Skips only when a symbol with the
        // same fully-qualified name and matching parameter list already exists
        // (overloads with distinct signatures are all registered).
        func registerMember(
            name: String,
            parameterTypes: [TypeID],
            externalLinkName: String,
            returnTypeOverride: TypeID? = nil,
            typeParameterUpperBoundsList: [[TypeID]]? = nil,
            canThrow: Bool = false
        ) {
            let memberName = interner.intern(name)
            let memberFQName = listFQName + [memberName]
            if let types = BundledSyntheticStubRegistration.types,
               BundledSyntheticStubRegistration.shouldSkipRegistration(
                   declaredOwnerFQName: listFQName,
                   receiverType: receiverType,
                   name: memberName,
                   arity: parameterTypes.count,
                   symbols: symbols,
                   types: types,
                   interner: interner
               )
            {
                return
            }
            let alreadySameSignature = symbols.lookupAll(fqName: memberFQName).contains { symbolID in
                guard let sig = symbols.functionSignature(for: symbolID) else { return false }
                return sig.parameterTypes == parameterTypes
            }
            guard !alreadySameSignature else { return }
            registerMemberOverload(
                memberName: memberName,
                memberFQName: memberFQName,
                parameterTypes: parameterTypes,
                externalLinkName: externalLinkName,
                returnTypeOverride: returnTypeOverride,
                typeParameterUpperBoundsList: typeParameterUpperBoundsList,
                canThrow: canThrow
            )
        }

        // Register a synthetic member overload on List, checking for
        // duplicate registrations by comparing parameter signatures.
        func registerMemberOverload(
            memberName: InternedString,
            memberFQName: [InternedString],
            parameterTypes: [TypeID],
            externalLinkName: String,
            returnTypeOverride: TypeID? = nil,
            typeParameterSymbols: [SymbolID]? = nil,
            typeParameterUpperBoundsList: [[TypeID]]? = nil,
            flags: SymbolFlags = [.synthetic],
            reifiedTypeParameterIndices: Set<Int> = [],
            canThrow: Bool = false
        ) {
            if let types = BundledSyntheticStubRegistration.types,
               BundledSyntheticStubRegistration.shouldSkipRegistration(
                   declaredOwnerFQName: listFQName,
                   receiverType: receiverType,
                   name: memberName,
                   arity: parameterTypes.count,
                   symbols: symbols,
                   types: types,
                   interner: interner
               )
            {
                return
            }
            let alreadyRegistered = symbols.lookupAll(fqName: memberFQName).contains { symbolID in
                guard let sig = symbols.functionSignature(for: symbolID) else { return false }
                return sig.parameterTypes == parameterTypes
            }
            guard !alreadyRegistered else { return }
            let sourceBackedFilterNames: Set<InternedString> = [
                interner.intern("filter"),
                interner.intern("filterNot"),
                interner.intern("filterNotNull"),
                interner.intern("filterIndexed"),
                interner.intern("filterIsInstance"),
            ]
            if sourceBackedFilterNames.contains(memberName),
               shouldSkipSyntheticStub(
                   bundledIndex: bundledIndex,
                   ownerFQName: listFQName,
                   name: memberName,
                   arity: parameterTypes.count
               )
            {
                skipStats?.recordSkip(
                    ownerFQName: listFQName,
                    name: memberName,
                    arity: parameterTypes.count,
                    interner: interner
                )
                return
            }
            let memberSymbol = symbols.define(
                kind: .function,
                name: memberName,
                fqName: memberFQName,
                declSite: nil,
                visibility: .public,
                flags: flags
            )
            symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
            let resolvedExternalLinkName = StdlibSurfaceSpec.collectionHOFRuntimeLinkName(
                ownerKind: .list,
                memberName: interner.resolve(memberName),
                arity: parameterTypes.count,
                fallback: externalLinkName
            )
            symbols.setExternalLinkName(resolvedExternalLinkName, for: memberSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: parameterTypes,
                    returnType: returnTypeOverride ?? receiverType,
                    canThrow: canThrow,
                    typeParameterSymbols: typeParameterSymbols ?? [listTypeParamSymbol],
                    reifiedTypeParameterIndices: reifiedTypeParameterIndices,
                    typeParameterUpperBoundsList: typeParameterUpperBoundsList ?? [],
                    classTypeParameterCount: 1
                ),
                for: memberSymbol
            )
        }

        registerMember(name: "take", parameterTypes: [types.intType], externalLinkName: "kk_list_take", canThrow: true)
        registerMember(name: "drop", parameterTypes: [types.intType], externalLinkName: "kk_list_drop", canThrow: true)
        registerMember(name: "takeLast", parameterTypes: [types.intType], externalLinkName: "kk_list_takeLast", canThrow: true)
        registerMember(name: "dropLast", parameterTypes: [types.intType], externalLinkName: "kk_list_dropLast")
        registerMember(name: "sum", parameterTypes: [], externalLinkName: "kk_list_sum", returnTypeOverride: types.intType)
        registerMember(name: "average", parameterTypes: [], externalLinkName: "kk_list_average", returnTypeOverride: types.doubleType)
        // but is not yet wired into the compiler pipeline (RF-STDLIB-004+). Keep these stubs until then.
        registerMember(name: "reversed", parameterTypes: [], externalLinkName: "kk_list_reversed")
        registerMember(name: "asReversed", parameterTypes: [], externalLinkName: "kk_list_as_reversed")
        registerMember(
            name: "sorted",
            parameterTypes: [],
            externalLinkName: "kk_list_sorted",
            typeParameterUpperBoundsList: [comparableElementBounds]
        )
        registerMember(name: "distinct", parameterTypes: [], externalLinkName: "kk_list_distinct")
        registerMember(name: "shuffled", parameterTypes: [], externalLinkName: "kk_list_shuffled")

        // shuffled(random: Random) overload (STDLIB-531)
        // Requires kotlin.random.Random to be registered first (via
        // registerSyntheticRandomStubs which runs before collection stubs).
        do {
            let shuffledRandomName = interner.intern("shuffled")
            let shuffledRandomFQName = listFQName + [shuffledRandomName]
            let kotlinRandomPkg: [InternedString] = [interner.intern("kotlin"), interner.intern("random")]
            let randomClassName = interner.intern("Random")
            let randomFQName = kotlinRandomPkg + [randomClassName]
            if let randomSymbol = symbols.lookup(fqName: randomFQName) {
                let randomParamType = types.make(.classType(ClassType(
                    classSymbol: randomSymbol,
                    args: [],
                    nullability: .nonNull
                )))
                registerMemberOverload(
                    memberName: shuffledRandomName,
                    memberFQName: shuffledRandomFQName,
                    parameterTypes: [randomParamType],
                    externalLinkName: "kk_list_shuffled_random"
                )
            } else {
                assertionFailure("kotlin.random.Random must be registered before collection stubs")
            }
        }

        let listPredicateType = types.make(.functionType(FunctionType(
            params: [listTypeParamType],
            returnType: types.booleanType,
            isSuspend: false,
            nullability: .nonNull
        )))
        registerMember(
            name: "find",
            parameterTypes: [listPredicateType],
            externalLinkName: "kk_list_find",
            returnTypeOverride: types.makeNullable(listTypeParamType)
        )

        let mapToTypeParamName = interner.intern("R")
        let mapToTypeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: mapToTypeParamName,
            fqName: listFQName + [interner.intern("mapTo"), mapToTypeParamName],
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let mapToTypeParamType = types.make(.typeParam(TypeParamType(
            symbol: mapToTypeParamSymbol, nullability: .nonNull
        )))
        let mapToDestinationType = types.make(.classType(ClassType(
            classSymbol: collectionInterfaceSymbol,
            args: [.out(mapToTypeParamType)],
            nullability: .nonNull
        )))
        registerMemberOverload(
            memberName: interner.intern("mapTo"),
            memberFQName: listFQName + [interner.intern("mapTo")],
            parameterTypes: [
                mapToDestinationType,
                types.make(.functionType(FunctionType(
                    params: [listTypeParamType],
                    returnType: mapToTypeParamType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
            ],
            externalLinkName: "kk_list_mapTo",
            returnTypeOverride: mapToDestinationType,
            typeParameterSymbols: [listTypeParamSymbol, mapToTypeParamSymbol]
        )

        let flatMapTypeParamName = interner.intern("R")
        let flatMapTypeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: flatMapTypeParamName,
            fqName: listFQName + [interner.intern("flatMap"), flatMapTypeParamName],
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let flatMapTypeParamType = types.make(.typeParam(TypeParamType(
            symbol: flatMapTypeParamSymbol, nullability: .nonNull
        )))
        let flatMapReturnType = types.make(.classType(ClassType(
            classSymbol: listInterfaceSymbol,
            args: [.out(flatMapTypeParamType)],
            nullability: .nonNull
        )))
        let flatMapLambdaReturnType = types.make(.classType(ClassType(
            classSymbol: collectionInterfaceSymbol,
            args: [.out(flatMapTypeParamType)],
            nullability: .nonNull
        )))
        registerMemberOverload(
            memberName: interner.intern("flatMap"),
            memberFQName: listFQName + [interner.intern("flatMap")],
            parameterTypes: [
                types.make(.functionType(FunctionType(
                    params: [listTypeParamType],
                    returnType: flatMapLambdaReturnType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
            ],
            externalLinkName: "kk_list_flatMap",
            returnTypeOverride: flatMapReturnType,
            typeParameterSymbols: [listTypeParamSymbol, flatMapTypeParamSymbol]
        )

        let flatMapIndexedTypeParamName = interner.intern("R")
        let flatMapIndexedTypeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: flatMapIndexedTypeParamName,
            fqName: listFQName + [interner.intern("flatMapIndexed"), flatMapIndexedTypeParamName],
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let flatMapIndexedTypeParamType = types.make(.typeParam(TypeParamType(
            symbol: flatMapIndexedTypeParamSymbol, nullability: .nonNull
        )))
        let flatMapIndexedReturnType = types.make(.classType(ClassType(
            classSymbol: listInterfaceSymbol,
            args: [.out(flatMapIndexedTypeParamType)],
            nullability: .nonNull
        )))
        let flatMapIndexedLambdaReturnType = types.make(.classType(ClassType(
            classSymbol: collectionInterfaceSymbol,
            args: [.out(flatMapIndexedTypeParamType)],
            nullability: .nonNull
        )))
        registerMemberOverload(
            memberName: interner.intern("flatMapIndexed"),
            memberFQName: listFQName + [interner.intern("flatMapIndexed")],
            parameterTypes: [
                types.make(.functionType(FunctionType(
                    params: [types.intType, listTypeParamType],
                    returnType: flatMapIndexedLambdaReturnType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
            ],
            externalLinkName: "kk_list_flatMapIndexed",
            returnTypeOverride: flatMapIndexedReturnType,
            typeParameterSymbols: [listTypeParamSymbol, flatMapIndexedTypeParamSymbol]
        )

        let flatMapToTypeParamName = interner.intern("R")
        let flatMapToTypeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: flatMapToTypeParamName,
            fqName: listFQName + [interner.intern("flatMapTo"), flatMapToTypeParamName],
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let flatMapToTypeParamType = types.make(.typeParam(TypeParamType(
            symbol: flatMapToTypeParamSymbol, nullability: .nonNull
        )))
        let flatMapToDestinationType = types.make(.classType(ClassType(
            classSymbol: collectionInterfaceSymbol,
            args: [.out(flatMapToTypeParamType)],
            nullability: .nonNull
        )))
        let flatMapToLambdaReturnType = types.make(.classType(ClassType(
            classSymbol: collectionInterfaceSymbol,
            args: [.out(flatMapToTypeParamType)],
            nullability: .nonNull
        )))
        registerMemberOverload(
            memberName: interner.intern("flatMapTo"),
            memberFQName: listFQName + [interner.intern("flatMapTo")],
            parameterTypes: [
                flatMapToDestinationType,
                types.make(.functionType(FunctionType(
                    params: [listTypeParamType],
                    returnType: flatMapToLambdaReturnType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
            ],
            externalLinkName: "kk_list_flatMapTo",
            returnTypeOverride: flatMapToDestinationType,
            typeParameterSymbols: [listTypeParamSymbol, flatMapToTypeParamSymbol]
        )

        let mapNotNullToTypeParamName = interner.intern("R")
        let mapNotNullToTypeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: mapNotNullToTypeParamName,
            fqName: listFQName + [interner.intern("mapNotNullTo"), mapNotNullToTypeParamName],
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let mapNotNullToTypeParamType = types.make(.typeParam(TypeParamType(
            symbol: mapNotNullToTypeParamSymbol, nullability: .nonNull
        )))
        let mapNotNullToDestinationType = types.make(.classType(ClassType(
            classSymbol: collectionInterfaceSymbol,
            args: [.out(mapNotNullToTypeParamType)],
            nullability: .nonNull
        )))
        registerMemberOverload(
            memberName: interner.intern("mapNotNullTo"),
            memberFQName: listFQName + [interner.intern("mapNotNullTo")],
            parameterTypes: [
                mapNotNullToDestinationType,
                types.make(.functionType(FunctionType(
                    params: [listTypeParamType],
                    returnType: types.nullableAnyType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
            ],
            externalLinkName: "kk_list_mapNotNullTo",
            returnTypeOverride: mapNotNullToDestinationType,
            typeParameterSymbols: [listTypeParamSymbol, mapNotNullToTypeParamSymbol]
        )

        let mapIndexedToTypeParamName = interner.intern("R")
        let mapIndexedToTypeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: mapIndexedToTypeParamName,
            fqName: listFQName + [interner.intern("mapIndexedTo"), mapIndexedToTypeParamName],
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let mapIndexedToTypeParamType = types.make(.typeParam(TypeParamType(
            symbol: mapIndexedToTypeParamSymbol, nullability: .nonNull
        )))
        let mapIndexedToDestinationType = types.make(.classType(ClassType(
            classSymbol: collectionInterfaceSymbol,
            args: [.out(mapIndexedToTypeParamType)],
            nullability: .nonNull
        )))
        registerMemberOverload(
            memberName: interner.intern("mapIndexedTo"),
            memberFQName: listFQName + [interner.intern("mapIndexedTo")],
            parameterTypes: [
                mapIndexedToDestinationType,
                types.make(.functionType(FunctionType(
                    params: [types.intType, listTypeParamType],
                    returnType: mapIndexedToTypeParamType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
            ],
            externalLinkName: "kk_list_mapIndexedTo",
            returnTypeOverride: mapIndexedToDestinationType,
            typeParameterSymbols: [listTypeParamSymbol, mapIndexedToTypeParamSymbol]
        )

        let flatMapIndexedToTypeParamName = interner.intern("R")
        let flatMapIndexedToTypeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: flatMapIndexedToTypeParamName,
            fqName: listFQName + [interner.intern("flatMapIndexedTo"), flatMapIndexedToTypeParamName],
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let flatMapIndexedToTypeParamType = types.make(.typeParam(TypeParamType(
            symbol: flatMapIndexedToTypeParamSymbol, nullability: .nonNull
        )))
        let flatMapIndexedToDestinationType = types.make(.classType(ClassType(
            classSymbol: collectionInterfaceSymbol,
            args: [.out(flatMapIndexedToTypeParamType)],
            nullability: .nonNull
        )))
        let flatMapIndexedToLambdaReturnType = types.make(.classType(ClassType(
            classSymbol: collectionInterfaceSymbol,
            args: [.out(flatMapIndexedToTypeParamType)],
            nullability: .nonNull
        )))
        registerMemberOverload(
            memberName: interner.intern("flatMapIndexedTo"),
            memberFQName: listFQName + [interner.intern("flatMapIndexedTo")],
            parameterTypes: [
                flatMapIndexedToDestinationType,
                types.make(.functionType(FunctionType(
                    params: [types.intType, listTypeParamType],
                    returnType: flatMapIndexedToLambdaReturnType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
            ],
            externalLinkName: "kk_list_flatMapIndexedTo",
            returnTypeOverride: flatMapIndexedToDestinationType,
            typeParameterSymbols: [listTypeParamSymbol, flatMapIndexedToTypeParamSymbol]
        )

        registerMember(
            name: "sortedDescending",
            parameterTypes: [],
            externalLinkName: "kk_list_sortedDescending",
            typeParameterUpperBoundsList: [comparableElementBounds]
        )
        registerMember(name: "subList", parameterTypes: [types.intType, types.intType], externalLinkName: "kk_list_subList")

        // STDLIB-214: List.slice(indices: IntRange) and List.slice(indices: Iterable<Int>)
        // IntRange expressions are typed as intType at the ABI level, so the IntRange overload
        // is registered with parameterType=intType.  The Iterable<Int> overload uses List<out Int>.
        // resolveCollectionFallbackCallee distinguishes the two via isRangeExpr on the argument.
        do {
            let sliceName = interner.intern("slice")
            let sliceFQName = listFQName + [sliceName]
            let listOfIntType = types.make(.classType(ClassType(
                classSymbol: listInterfaceSymbol,
                args: [.out(types.intType)],
                nullability: .nonNull
            )))
            // IntRange overload: parameterType = intType
            let existingSlice = symbols.lookupAll(fqName: sliceFQName)
            let hasIntRangeSlice = existingSlice.contains { symID in
                guard let sig = symbols.functionSignature(for: symID) else { return false }
                return sig.parameterTypes == [types.intType] &&
                    symbols.externalLinkName(for: symID) == "kk_list_slice"
            }
            if !hasIntRangeSlice {
                let sym = symbols.define(
                    kind: .function, name: sliceName, fqName: sliceFQName,
                    declSite: nil, visibility: .public, flags: [.synthetic]
                )
                symbols.setParentSymbol(listInterfaceSymbol, for: sym)
                symbols.setExternalLinkName("kk_list_slice", for: sym)
                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: receiverType, parameterTypes: [types.intType],
                        returnType: listReturnType, typeParameterSymbols: [listTypeParamSymbol],
                        classTypeParameterCount: 1
                    ),
                    for: sym
                )
            }
            // Iterable<Int> overload: parameterType = List<out Int>
            let hasIterableSlice = existingSlice.contains { symID in
                guard let sig = symbols.functionSignature(for: symID) else { return false }
                return sig.parameterTypes == [listOfIntType]
            }
            if !hasIterableSlice {
                let sym = symbols.define(
                    kind: .function, name: sliceName, fqName: sliceFQName,
                    declSite: nil, visibility: .public, flags: [.synthetic]
                )
                symbols.setParentSymbol(listInterfaceSymbol, for: sym)
                symbols.setExternalLinkName("kk_list_slice_iterable", for: sym)
                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: receiverType, parameterTypes: [listOfIntType],
                        returnType: listReturnType, typeParameterSymbols: [listTypeParamSymbol],
                        classTypeParameterCount: 1
                    ),
                    for: sym
                )
            }
        }

        // distinctBy (HOF, selector lambda)
        // Kotlin's `distinctBy` is declared as an extension on Iterable<T>:
        //   fun <T, K> Iterable<T>.distinctBy(selector: (T) -> K): List<T>
        // The compiler models this as a synthetic member on List (not Iterable) because
        // the stub system registers members on concrete collection interfaces.
        // We use `Any?` as the selector return type (erasing K) so that selectors
        // returning nullable keys (e.g., `{ it.name }` where `name` is `String?`)
        // are accepted without a type error.  The runtime compares keys by
        // handle/unboxed-value identity, so nullable vs non-null makes no behavioural
        // difference at the ABI level.
        // NOTE: The selector type `(T) -> Any?` must stay in sync with the expected
        // type in CallTypeChecker+MemberCallInference.swift (case "distinctBy").
        let distinctByName = interner.intern("distinctBy")
        let distinctByFQName = listFQName + [distinctByName]
        if symbols.lookup(fqName: distinctByFQName) == nil {
            let selectorType = types.make(.functionType(FunctionType(
                params: [listTypeParamType],
                returnType: types.nullableAnyType,
                isSuspend: false,
                nullability: .nonNull
            )))
            let memberSymbol = symbols.define(
                kind: .function,
                name: distinctByName,
                fqName: distinctByFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .inlineFunction]
            )
            symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
            symbols.setExternalLinkName("kk_list_distinctBy", for: memberSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: [selectorType],
                    returnType: listReturnType,
                    typeParameterSymbols: [listTypeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: memberSymbol
            )
        }
    }
}
