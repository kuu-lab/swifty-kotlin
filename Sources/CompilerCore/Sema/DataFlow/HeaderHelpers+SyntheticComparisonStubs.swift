
extension DataFlowSemaPhase {
    func registerSyntheticComparisonStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinPkg: [InternedString] = [interner.intern("kotlin")]
        let comparisonsPkg: [InternedString] = kotlinPkg + [interner.intern("comparisons")]
        _ = ensureSyntheticPackage(fqName: kotlinPkg, symbols: symbols)
        let comparisonsPackageSymbol = ensureSyntheticPackage(fqName: comparisonsPkg, symbols: symbols)

        if types.comparableInterfaceSymbol == nil {
            registerSyntheticComparableStub(
                symbols: symbols,
                types: types,
                interner: interner
            )
        }

        let comparatorFQName = kotlinPkg + [interner.intern("Comparator")]
        guard let comparatorSymbol = symbols.lookup(fqName: comparatorFQName) else {
            return
        }

        registerSyntheticMaxWithComparatorStubs(
            symbols: symbols,
            types: types,
            interner: interner,
            comparisonsPkg: comparisonsPkg,
            comparisonsPackageSymbol: comparisonsPackageSymbol,
            comparatorSymbol: comparatorSymbol
        )
    }

    private func registerSyntheticComparisonFunction(
        named name: String,
        parameterTypes: [TypeID],
        returnType: TypeID,
        parameterNames: [String],
        valueParameterIsVararg: [Bool] = [],
        typeParameterSymbols: [SymbolID] = [],
        typeParameterUpperBoundsList: [[TypeID]] = [],
        packageFQName: [InternedString],
        packageSymbol: SymbolID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let functionName = interner.intern(name)
        let functionFQName = packageFQName + [functionName]
        let normalizedVararg = valueParameterIsVararg.isEmpty
            ? Array(repeating: false, count: parameterNames.count)
            : valueParameterIsVararg
        if symbols.lookupAll(fqName: functionFQName).contains(where: { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.parameterTypes == parameterTypes
                && signature.returnType == returnType
                && signature.valueParameterIsVararg == normalizedVararg
                && signature.typeParameterSymbols.count == typeParameterSymbols.count
        }) {
            return
        }

        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .inlineFunction]
        )
        symbols.setParentSymbol(packageSymbol, for: functionSymbol)

        var paramSymbols: [SymbolID] = []
        for paramName in parameterNames {
            let internedName = interner.intern(paramName)
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: internedName,
                fqName: functionFQName + [internedName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(functionSymbol, for: paramSymbol)
            paramSymbols.append(paramSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: parameterTypes,
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: paramSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: parameterNames.count),
                valueParameterIsVararg: normalizedVararg,
                typeParameterSymbols: typeParameterSymbols,
                typeParameterUpperBoundsList: typeParameterUpperBoundsList
            ),
            for: functionSymbol
        )
    }

    /// Registers the top-level `kotlin.comparisons.maxWith(comparator, a, b): T`
    /// overload (and its `minWith` sibling). The 3-arg form takes a
    /// `Comparator<in T>` and two values, returning the greater of the two
    /// (or lesser for `minWith`).
    ///
    /// STDLIB-COMP-FN-027 / STDLIB-COMP-FN-028.
    private func registerSyntheticMaxWithComparatorStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        comparisonsPkg: [InternedString],
        comparisonsPackageSymbol: SymbolID,
        comparatorSymbol: SymbolID
    ) {
        for functionName in ["maxWith", "minWith"] {
            let functionNameID = interner.intern(functionName)
            let functionFQName = comparisonsPkg + [functionNameID]
            let tParamName = interner.intern("T")
            let tParamFQName = functionFQName + [tParamName]
            let tParamSymbol = symbols.lookup(fqName: tParamFQName) ?? symbols.define(
                kind: .typeParameter,
                name: tParamName,
                fqName: tParamFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
            let tParamType = types.make(.typeParam(TypeParamType(
                symbol: tParamSymbol,
                nullability: .nonNull
            )))
            let comparatorType = types.make(.classType(ClassType(
                classSymbol: comparatorSymbol,
                args: [.in(tParamType)],
                nullability: .nonNull
            )))

            registerSyntheticComparisonFunction(
                named: functionName,
                parameterTypes: [comparatorType, tParamType, tParamType],
                returnType: tParamType,
                parameterNames: ["comparator", "a", "b"],
                typeParameterSymbols: [tParamSymbol],
                typeParameterUpperBoundsList: [[]],
                packageFQName: comparisonsPkg,
                packageSymbol: comparisonsPackageSymbol,
                symbols: symbols,
                interner: interner
            )
        }
    }
}
