import RuntimeABI

/// List transform members that are not yet source-backed (e.g. `sum`, `distinctBy`)
/// extracted from `HeaderHelpers+SyntheticListStubs.swift`.
/// KSP-421 source-backed transforms (`map`, `mapIndexed`, `mapNotNull`,
/// `flatMap`, `flatMapIndexed`, `flatten`, and `*To` variants) are no longer
/// registered here.
/// KSP-427 source-backed transforms (`take`, `takeLast`, `drop`, `dropLast`,
/// `slice`, `subList`) are no longer registered here.
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

        registerMember(
            name: "sortedDescending",
            parameterTypes: [],
            externalLinkName: "kk_list_sortedDescending",
            typeParameterUpperBoundsList: [comparableElementBounds]
        )
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
