
/// Synthetic stdlib stubs split from `HeaderHelpers+SyntheticComparableAndCollectionStubs.swift`:
/// List indexed members, IndexedValue<T>, and ArrayDeque<T>.
///
/// Split out to isolate merge conflicts between parallel stdlib PRs adding new
/// entries to this package.
extension DataFlowSemaPhase {

    func registerListIndexedMembers(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        listFQName: [InternedString],
        listInterfaceSymbol: SymbolID,
        listTypeParamSymbol: SymbolID,
        listTypeParamType: TypeID,
        bundledIndex: BundledDeclarationIndex = .empty,
        skipStats: SyntheticStubSkipStatsCollector? = nil
    ) {
        let receiverType = types.make(.classType(ClassType(
            classSymbol: listInterfaceSymbol,
            args: [.out(listTypeParamType)],
            nullability: .nonNull
        )))

        // KSP-626: withIndex / forEachIndexed are bundled Kotlin source
        // (Stdlib/kotlin/collections/Iterators.kt).
        let listSymbol = listInterfaceSymbol

        // mapIndexed(transform: (Int, E) -> R): List<R>
        let mapIndexedName = interner.intern("mapIndexed")
        let mapIndexedFQName = listFQName + [mapIndexedName]
        if let types = BundledSyntheticStubRegistration.types,
           !BundledSyntheticStubRegistration.shouldSkipRegistration(
               declaredOwnerFQName: listFQName,
               receiverType: receiverType,
               name: mapIndexedName,
               arity: 1,
               symbols: symbols,
               types: types,
               interner: interner
           ),
           symbols.lookup(fqName: mapIndexedFQName) == nil
        {
            // mapIndexed is tricky because of the generic R.
            // For synthetic stub, we might simplify to List<Any?> or just have it resolve via fallback if generic R is hard to define here.
            // But let's try to define a local type parameter R for the function.
            let rName = interner.intern("R")
            let rFQName = mapIndexedFQName + [rName]
            let rSymbol = symbols.define(
                kind: .typeParameter,
                name: rName,
                fqName: rFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
            let rType = types.make(.typeParam(TypeParamType(symbol: rSymbol, nullability: .nonNull)))

            let transformType = types.make(.functionType(FunctionType(
                params: [types.intType, listTypeParamType],
                returnType: rType,
                isSuspend: false,
                nullability: .nonNull
            )))
            let listRType = types.make(.classType(ClassType(
                classSymbol: listSymbol,
                args: [.out(rType)],
                nullability: .nonNull
            )))

            let memberSymbol = symbols.define(
                kind: .function,
                name: mapIndexedName,
                fqName: mapIndexedFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .inlineFunction]
            )
            symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
            symbols.setExternalLinkName("kk_list_mapIndexed", for: memberSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: [transformType],
                    returnType: listRType,
                    typeParameterSymbols: [listTypeParamSymbol, rSymbol],
                    classTypeParameterCount: 1 // Only List's E is class-level
                ),
                for: memberSymbol
            )
        }

        // mapIndexedNotNull(transform: (Int, E) -> R?): List<R>
        let mapIndexedNotNullName = interner.intern("mapIndexedNotNull")
        let mapIndexedNotNullFQName = listFQName + [mapIndexedNotNullName]
        if let types = BundledSyntheticStubRegistration.types,
           !BundledSyntheticStubRegistration.shouldSkipRegistration(
               declaredOwnerFQName: listFQName,
               receiverType: receiverType,
               name: mapIndexedNotNullName,
               arity: 1,
               symbols: symbols,
               types: types,
               interner: interner
           ),
           symbols.lookup(fqName: mapIndexedNotNullFQName) == nil {
            let rName = interner.intern("R")
            let rFQName = mapIndexedNotNullFQName + [rName]
            let rSymbol = symbols.define(
                kind: .typeParameter,
                name: rName,
                fqName: rFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
            let rType = types.make(.typeParam(TypeParamType(symbol: rSymbol, nullability: .nonNull)))
            let nullableRType = types.make(.typeParam(TypeParamType(symbol: rSymbol, nullability: .nullable)))

            let transformType = types.make(.functionType(FunctionType(
                params: [types.intType, listTypeParamType],
                returnType: nullableRType,
                isSuspend: false,
                nullability: .nonNull
            )))
            let listRType = types.make(.classType(ClassType(
                classSymbol: listSymbol,
                args: [.out(rType)],
                nullability: .nonNull
            )))

            let memberSymbol = symbols.define(
                kind: .function,
                name: mapIndexedNotNullName,
                fqName: mapIndexedNotNullFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .inlineFunction]
            )
            symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
            symbols.setExternalLinkName("kk_list_mapIndexedNotNull", for: memberSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: [transformType],
                    returnType: listRType,
                    typeParameterSymbols: [listTypeParamSymbol, rSymbol],
                    classTypeParameterCount: 1
                ),
                for: memberSymbol
            )
        }

        // foldIndexed(initial: R, operation: (Int, R, T) -> R): R
        let foldIndexedName = interner.intern("foldIndexed")
        let foldIndexedFQName = listFQName + [foldIndexedName]
        if let types = BundledSyntheticStubRegistration.types,
           !BundledSyntheticStubRegistration.shouldSkipRegistration(
               declaredOwnerFQName: listFQName,
               receiverType: receiverType,
               name: foldIndexedName,
               arity: 2,
               symbols: symbols,
               types: types,
               interner: interner
           ),
           symbols.lookup(fqName: foldIndexedFQName) == nil {
            let rName = interner.intern("R")
            let rFQName = foldIndexedFQName + [rName]
            let rSymbol = symbols.define(kind: .typeParameter, name: rName, fqName: rFQName, declSite: nil, visibility: .private, flags: [])
            let rType = types.make(.typeParam(TypeParamType(symbol: rSymbol, nullability: .nonNull)))
            let operationType = types.make(.functionType(FunctionType(params: [types.intType, rType, listTypeParamType], returnType: rType, isSuspend: false, nullability: .nonNull)))
            let memberSymbol = symbols.define(kind: .function, name: foldIndexedName, fqName: foldIndexedFQName, declSite: nil, visibility: .public, flags: [.synthetic, .inlineFunction])
            symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
            symbols.setExternalLinkName("kk_list_foldIndexed", for: memberSymbol)
            symbols.setFunctionSignature(FunctionSignature(receiverType: receiverType, parameterTypes: [rType, operationType], returnType: rType, typeParameterSymbols: [listTypeParamSymbol, rSymbol], classTypeParameterCount: 1), for: memberSymbol)
        }

        // reduceIndexed(operation: (Int, S, T) -> S): S
        let reduceIndexedName = interner.intern("reduceIndexed")
        let reduceIndexedFQName = listFQName + [reduceIndexedName]
        if let types = BundledSyntheticStubRegistration.types,
           !BundledSyntheticStubRegistration.shouldSkipRegistration(
               declaredOwnerFQName: listFQName,
               receiverType: receiverType,
               name: reduceIndexedName,
               arity: 1,
               symbols: symbols,
               types: types,
               interner: interner
           ),
           symbols.lookup(fqName: reduceIndexedFQName) == nil {
            let sName = interner.intern("S")
            let sFQName = reduceIndexedFQName + [sName]
            let sSymbol = symbols.define(kind: .typeParameter, name: sName, fqName: sFQName, declSite: nil, visibility: .private, flags: [])
            let sType = types.make(.typeParam(TypeParamType(symbol: sSymbol, nullability: .nonNull)))
            let operationType = types.make(.functionType(FunctionType(params: [types.intType, sType, listTypeParamType], returnType: sType, isSuspend: false, nullability: .nonNull)))
            let memberSymbol = symbols.define(kind: .function, name: reduceIndexedName, fqName: reduceIndexedFQName, declSite: nil, visibility: .public, flags: [.synthetic, .inlineFunction])
            symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
            symbols.setExternalLinkName("kk_list_reduceIndexed", for: memberSymbol)
            symbols.setFunctionSignature(FunctionSignature(receiverType: receiverType, parameterTypes: [operationType], returnType: sType, typeParameterSymbols: [listTypeParamSymbol, sSymbol], classTypeParameterCount: 1), for: memberSymbol)
        }

        // reduceIndexedOrNull(operation: (Int, S, T) -> S): S?
        let reduceIndexedOrNullName = interner.intern("reduceIndexedOrNull")
        let reduceIndexedOrNullFQName = listFQName + [reduceIndexedOrNullName]
        if let types = BundledSyntheticStubRegistration.types,
           !BundledSyntheticStubRegistration.shouldSkipRegistration(
               declaredOwnerFQName: listFQName,
               receiverType: receiverType,
               name: reduceIndexedOrNullName,
               arity: 1,
               symbols: symbols,
               types: types,
               interner: interner
           ),
           symbols.lookup(fqName: reduceIndexedOrNullFQName) == nil {
            let sName = interner.intern("S")
            let sFQName = reduceIndexedOrNullFQName + [sName]
            let sSymbol = symbols.define(kind: .typeParameter, name: sName, fqName: sFQName, declSite: nil, visibility: .private, flags: [])
            let sType = types.make(.typeParam(TypeParamType(symbol: sSymbol, nullability: .nonNull)))
            let operationType = types.make(.functionType(FunctionType(params: [types.intType, sType, listTypeParamType], returnType: sType, isSuspend: false, nullability: .nonNull)))
            let nullableAccumulatorType = types.makeNullable(sType)
            let memberSymbol = symbols.define(kind: .function, name: reduceIndexedOrNullName, fqName: reduceIndexedOrNullFQName, declSite: nil, visibility: .public, flags: [.synthetic, .inlineFunction])
            symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
            symbols.setExternalLinkName("kk_list_reduceIndexedOrNull", for: memberSymbol)
            symbols.setFunctionSignature(FunctionSignature(receiverType: receiverType, parameterTypes: [operationType], returnType: nullableAccumulatorType, typeParameterSymbols: [listTypeParamSymbol, sSymbol], classTypeParameterCount: 1), for: memberSymbol)
        }

        // runningFoldIndexed(initial: R, operation: (Int, R, T) -> R): List<R>
        let runningFoldIndexedName = interner.intern("runningFoldIndexed")
        let runningFoldIndexedFQName = listFQName + [runningFoldIndexedName]
        if let types = BundledSyntheticStubRegistration.types,
           !BundledSyntheticStubRegistration.shouldSkipRegistration(
               declaredOwnerFQName: listFQName,
               receiverType: receiverType,
               name: runningFoldIndexedName,
               arity: 2,
               symbols: symbols,
               types: types,
               interner: interner
           ),
           symbols.lookup(fqName: runningFoldIndexedFQName) == nil {
            let rName = interner.intern("R")
            let rFQName = runningFoldIndexedFQName + [rName]
            let rSymbol = symbols.define(kind: .typeParameter, name: rName, fqName: rFQName, declSite: nil, visibility: .private, flags: [])
            let rType = types.make(.typeParam(TypeParamType(symbol: rSymbol, nullability: .nonNull)))
            let operationType = types.make(.functionType(FunctionType(params: [types.intType, rType, listTypeParamType], returnType: rType, isSuspend: false, nullability: .nonNull)))
            let listRType = types.make(.classType(ClassType(classSymbol: listSymbol, args: [.out(rType)], nullability: .nonNull)))
            let memberSymbol = symbols.define(kind: .function, name: runningFoldIndexedName, fqName: runningFoldIndexedFQName, declSite: nil, visibility: .public, flags: [.synthetic, .inlineFunction])
            symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
            symbols.setExternalLinkName("kk_list_runningFoldIndexed", for: memberSymbol)
            symbols.setFunctionSignature(FunctionSignature(receiverType: receiverType, parameterTypes: [rType, operationType], returnType: listRType, typeParameterSymbols: [listTypeParamSymbol, rSymbol], classTypeParameterCount: 1), for: memberSymbol)
        }

        // runningReduceIndexed(operation: (Int, S, T) -> S): List<S>
        let runningReduceIndexedName = interner.intern("runningReduceIndexed")
        let runningReduceIndexedFQName = listFQName + [runningReduceIndexedName]
        if let types = BundledSyntheticStubRegistration.types,
           !BundledSyntheticStubRegistration.shouldSkipRegistration(
               declaredOwnerFQName: listFQName,
               receiverType: receiverType,
               name: runningReduceIndexedName,
               arity: 1,
               symbols: symbols,
               types: types,
               interner: interner
           ),
           symbols.lookup(fqName: runningReduceIndexedFQName) == nil {
            let sName = interner.intern("S")
            let sFQName = runningReduceIndexedFQName + [sName]
            let sSymbol = symbols.define(kind: .typeParameter, name: sName, fqName: sFQName, declSite: nil, visibility: .private, flags: [])
            let sType = types.make(.typeParam(TypeParamType(symbol: sSymbol, nullability: .nonNull)))
            let operationType = types.make(.functionType(FunctionType(params: [types.intType, sType, listTypeParamType], returnType: sType, isSuspend: false, nullability: .nonNull)))
            let listSType = types.make(.classType(ClassType(classSymbol: listSymbol, args: [.out(sType)], nullability: .nonNull)))
            let memberSymbol = symbols.define(kind: .function, name: runningReduceIndexedName, fqName: runningReduceIndexedFQName, declSite: nil, visibility: .public, flags: [.synthetic, .inlineFunction])
            symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
            symbols.setExternalLinkName("kk_list_runningReduceIndexed", for: memberSymbol)
            symbols.setFunctionSignature(FunctionSignature(receiverType: receiverType, parameterTypes: [operationType], returnType: listSType, typeParameterSymbols: [listTypeParamSymbol, sSymbol], classTypeParameterCount: 1), for: memberSymbol)
        }

        // scan(initial: R, operation: (R, T) -> R): List<R>
        let scanName = interner.intern("scan")
        let scanFQName = listFQName + [scanName]
        if let types = BundledSyntheticStubRegistration.types,
           !BundledSyntheticStubRegistration.shouldSkipRegistration(
               declaredOwnerFQName: listFQName,
               receiverType: receiverType,
               name: scanName,
               arity: 2,
               symbols: symbols,
               types: types,
               interner: interner
           ),
           symbols.lookup(fqName: scanFQName) == nil
        {
            let rName = interner.intern("R")
            let rFQName = scanFQName + [rName]
            let rSymbol = symbols.define(kind: .typeParameter, name: rName, fqName: rFQName, declSite: nil, visibility: .private, flags: [])
            let rType = types.make(.typeParam(TypeParamType(symbol: rSymbol, nullability: .nonNull)))
            let operationType = types.make(.functionType(FunctionType(
                params: [rType, listTypeParamType],
                returnType: rType,
                isSuspend: false,
                nullability: .nonNull
            )))
            let listRType = types.make(.classType(ClassType(classSymbol: listSymbol, args: [.out(rType)], nullability: .nonNull)))
            let memberSymbol = symbols.define(kind: .function, name: scanName, fqName: scanFQName, declSite: nil, visibility: .public, flags: [.synthetic, .inlineFunction])
            symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
            symbols.setExternalLinkName("kk_list_scan", for: memberSymbol)
            symbols.setFunctionSignature(FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [rType, operationType],
                returnType: listRType,
                typeParameterSymbols: [listTypeParamSymbol, rSymbol],
                classTypeParameterCount: 1
            ), for: memberSymbol)
        }

        // scanIndexed(initial: R, operation: (Int, R, T) -> R): List<R>
        let scanIndexedName = interner.intern("scanIndexed")
        let scanIndexedFQName = listFQName + [scanIndexedName]
        if let types = BundledSyntheticStubRegistration.types,
           !BundledSyntheticStubRegistration.shouldSkipRegistration(
               declaredOwnerFQName: listFQName,
               receiverType: receiverType,
               name: scanIndexedName,
               arity: 2,
               symbols: symbols,
               types: types,
               interner: interner
           ),
           symbols.lookup(fqName: scanIndexedFQName) == nil {
            let rName = interner.intern("R")
            let rFQName = scanIndexedFQName + [rName]
            let rSymbol = symbols.define(kind: .typeParameter, name: rName, fqName: rFQName, declSite: nil, visibility: .private, flags: [])
            let rType = types.make(.typeParam(TypeParamType(symbol: rSymbol, nullability: .nonNull)))
            let operationType = types.make(.functionType(FunctionType(params: [types.intType, rType, listTypeParamType], returnType: rType, isSuspend: false, nullability: .nonNull)))
            let listRType = types.make(.classType(ClassType(classSymbol: listSymbol, args: [.out(rType)], nullability: .nonNull)))
            let memberSymbol = symbols.define(kind: .function, name: scanIndexedName, fqName: scanIndexedFQName, declSite: nil, visibility: .public, flags: [.synthetic, .inlineFunction])
            symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
            symbols.setExternalLinkName("kk_list_scanIndexed", for: memberSymbol)
            symbols.setFunctionSignature(FunctionSignature(receiverType: receiverType, parameterTypes: [rType, operationType], returnType: listRType, typeParameterSymbols: [listTypeParamSymbol, rSymbol], classTypeParameterCount: 1), for: memberSymbol)
        }

        // foldRight(initial: R, operation: (T, acc: R) -> R): R
        let foldRightName = interner.intern("foldRight")
        let foldRightFQName = listFQName + [foldRightName]
        if let types = BundledSyntheticStubRegistration.types,
           !BundledSyntheticStubRegistration.shouldSkipRegistration(
               declaredOwnerFQName: listFQName,
               receiverType: receiverType,
               name: foldRightName,
               arity: 2,
               symbols: symbols,
               types: types,
               interner: interner
           ),
           symbols.lookup(fqName: foldRightFQName) == nil
        {
            let rName = interner.intern("R")
            let rFQName = foldRightFQName + [rName]
            let rSymbol = symbols.define(kind: .typeParameter, name: rName, fqName: rFQName, declSite: nil, visibility: .private, flags: [])
            let rType = types.make(.typeParam(TypeParamType(symbol: rSymbol, nullability: .nonNull)))
            let operationType = types.make(.functionType(FunctionType(params: [listTypeParamType, rType], returnType: rType, isSuspend: false, nullability: .nonNull)))
            let memberSymbol = symbols.define(kind: .function, name: foldRightName, fqName: foldRightFQName, declSite: nil, visibility: .public, flags: [.synthetic, .inlineFunction])
            symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
            symbols.setExternalLinkName("kk_list_foldRight", for: memberSymbol)
            symbols.setFunctionSignature(FunctionSignature(receiverType: receiverType, parameterTypes: [rType, operationType], returnType: rType, typeParameterSymbols: [listTypeParamSymbol, rSymbol], classTypeParameterCount: 1), for: memberSymbol)
        }

        // foldRightIndexed(initial: R, operation: (index: Int, T, acc: R) -> R): R
        let foldRightIndexedName = interner.intern("foldRightIndexed")
        let foldRightIndexedFQName = listFQName + [foldRightIndexedName]
        if let types = BundledSyntheticStubRegistration.types,
           !BundledSyntheticStubRegistration.shouldSkipRegistration(
               declaredOwnerFQName: listFQName,
               receiverType: receiverType,
               name: foldRightIndexedName,
               arity: 2,
               symbols: symbols,
               types: types,
               interner: interner
           ),
           symbols.lookup(fqName: foldRightIndexedFQName) == nil {
            let rName = interner.intern("R")
            let rFQName = foldRightIndexedFQName + [rName]
            let rSymbol = symbols.define(kind: .typeParameter, name: rName, fqName: rFQName, declSite: nil, visibility: .private, flags: [])
            let rType = types.make(.typeParam(TypeParamType(symbol: rSymbol, nullability: .nonNull)))
            let operationType = types.make(.functionType(FunctionType(params: [types.intType, listTypeParamType, rType], returnType: rType, isSuspend: false, nullability: .nonNull)))
            let memberSymbol = symbols.define(kind: .function, name: foldRightIndexedName, fqName: foldRightIndexedFQName, declSite: nil, visibility: .public, flags: [.synthetic, .inlineFunction])
            symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
            symbols.setExternalLinkName("kk_list_foldRightIndexed", for: memberSymbol)
            symbols.setFunctionSignature(FunctionSignature(receiverType: receiverType, parameterTypes: [rType, operationType], returnType: rType, typeParameterSymbols: [listTypeParamSymbol, rSymbol], classTypeParameterCount: 1), for: memberSymbol)
        }

        // reduceRight(operation: (T, acc: S) -> S): S
        let reduceRightName = interner.intern("reduceRight")
        let reduceRightFQName = listFQName + [reduceRightName]
        if let types = BundledSyntheticStubRegistration.types,
           !BundledSyntheticStubRegistration.shouldSkipRegistration(
               declaredOwnerFQName: listFQName,
               receiverType: receiverType,
               name: reduceRightName,
               arity: 1,
               symbols: symbols,
               types: types,
               interner: interner
           ),
           symbols.lookup(fqName: reduceRightFQName) == nil {
            let sName = interner.intern("S")
            let sFQName = reduceRightFQName + [sName]
            let sSymbol = symbols.define(kind: .typeParameter, name: sName, fqName: sFQName, declSite: nil, visibility: .private, flags: [])
            let sType = types.make(.typeParam(TypeParamType(symbol: sSymbol, nullability: .nonNull)))
            let operationType = types.make(.functionType(FunctionType(params: [listTypeParamType, sType], returnType: sType, isSuspend: false, nullability: .nonNull)))
            let memberSymbol = symbols.define(kind: .function, name: reduceRightName, fqName: reduceRightFQName, declSite: nil, visibility: .public, flags: [.synthetic, .inlineFunction])
            symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
            symbols.setExternalLinkName("kk_list_reduceRight", for: memberSymbol)
            symbols.setFunctionSignature(FunctionSignature(receiverType: receiverType, parameterTypes: [operationType], returnType: sType, typeParameterSymbols: [listTypeParamSymbol, sSymbol], classTypeParameterCount: 1), for: memberSymbol)
        }
    }

    /// Create a type parameter `R` with upper bound `Comparable<R>` for use in
    /// selector-based HOF stubs (sortedBy, sortedByDescending, maxByOrNull, etc.).
    ///
    /// When `Comparable` is not yet registered, the `R` parameter is omitted and
    /// `selectorReturnType` falls back to `Any`, avoiding an unconstrained generic.
    ///
    /// - Returns: A tuple of `(rSymbol, rType, comparableRBounds)` when the
    ///   Comparable interface is available, or `nil` when it is not.
}
