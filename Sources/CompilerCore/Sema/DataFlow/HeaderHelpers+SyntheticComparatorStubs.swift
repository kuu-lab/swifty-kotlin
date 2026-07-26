
/// Synthetic stubs for Comparator and nulls comparators.
/// KSP-309 moved compareBy/compareByDescending, naturalOrder/reverseOrder,
/// reversed, and then* composition helpers to bundled Kotlin source.
extension DataFlowSemaPhase {
    func registerSyntheticComparatorStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinPkg: [InternedString] = [interner.intern("kotlin")]
        let comparisonsPkg: [InternedString] = kotlinPkg + [interner.intern("comparisons")]
        _ = ensureSyntheticPackage(fqName: kotlinPkg, symbols: symbols)
        let comparisonsPackageSymbol = ensureSyntheticPackage(fqName: comparisonsPkg, symbols: symbols)

        let comparatorSymbol = registerComparatorInterface(
            symbols: symbols,
            types: types,
            interner: interner,
            kotlinPkg: kotlinPkg
        )

        registerCompareByMultiSelector(
            symbols: symbols,
            types: types,
            interner: interner,
            comparisonsPkg: comparisonsPkg,
            comparisonsPackageSymbol: comparisonsPackageSymbol,
            comparatorSymbol: comparatorSymbol
        )

        registerNullsComparators(
            symbols: symbols,
            types: types,
            interner: interner,
            comparatorSymbol: comparatorSymbol
        )

        registerNullsFirstTopLevelWithComparator(
            symbols: symbols,
            types: types,
            interner: interner,
            comparisonsPkg: comparisonsPkg,
            comparisonsPackageSymbol: comparisonsPackageSymbol,
            comparatorSymbol: comparatorSymbol
        )

        registerNullsLastTopLevelWithComparator(
            symbols: symbols,
            types: types,
            interner: interner,
            comparisonsPkg: comparisonsPkg,
            comparisonsPackageSymbol: comparisonsPackageSymbol,
            comparatorSymbol: comparatorSymbol
        )
        registerNullsLastTopLevelComparable(
            symbols: symbols,
            types: types,
            interner: interner,
            comparisonsPkg: comparisonsPkg,
            comparisonsPackageSymbol: comparisonsPackageSymbol,
            comparatorSymbol: comparatorSymbol
        )

        registerNullsFirstTopLevelComparable(
            symbols: symbols,
            types: types,
            interner: interner,
            comparisonsPkg: comparisonsPkg,
            comparisonsPackageSymbol: comparisonsPackageSymbol,
            comparatorSymbol: comparatorSymbol
        )

    }

    private func registerComparatorInterface(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinPkg: [InternedString]
    ) -> SymbolID {
        let comparatorName = interner.intern("Comparator")
        let comparatorFQName = kotlinPkg + [comparatorName]
        let comparatorSymbol: SymbolID = if let existing = symbols.lookup(fqName: comparatorFQName) {
            existing
        } else {
            symbols.define(
                kind: .interface,
                name: comparatorName,
                fqName: comparatorFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .funInterface]
            )
        }

        // Define type parameter T for Comparator<T>
        let tParamName = interner.intern("T")
        let tParamFQName = comparatorFQName + [tParamName]
        let tParamSymbol: SymbolID = if let existing = symbols.lookup(fqName: tParamFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: tParamName,
                fqName: tParamFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        let tParamType = types.make(.typeParam(TypeParamType(
            symbol: tParamSymbol, nullability: .nonNull
        )))
        types.setNominalTypeParameterSymbols([tParamSymbol], for: comparatorSymbol)
        types.setNominalTypeParameterVariances([.in], for: comparatorSymbol)

        // compare(a: T, b: T): Int
        let compareName = interner.intern("compare")
        let compareFQName = comparatorFQName + [compareName]
        guard symbols.lookup(fqName: compareFQName) == nil else {
            return comparatorSymbol
        }
        let receiverType = types.make(.classType(ClassType(
            classSymbol: comparatorSymbol,
            args: [.invariant(tParamType)],
            nullability: .nonNull
        )))
        let aName = interner.intern("a")
        let bName = interner.intern("b")
        let aSymbol = symbols.define(
            kind: .valueParameter,
            name: aName,
            fqName: compareFQName + [aName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        let bSymbol = symbols.define(
            kind: .valueParameter,
            name: bName,
            fqName: compareFQName + [bName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        let compareSymbol = symbols.define(
            kind: .function,
            name: compareName,
            fqName: compareFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .abstractType]
        )
        symbols.setParentSymbol(comparatorSymbol, for: compareSymbol)
        symbols.setParentSymbol(compareSymbol, for: aSymbol)
        symbols.setParentSymbol(compareSymbol, for: bSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [tParamType, tParamType],
                returnType: types.intType,
                typeParameterSymbols: [tParamSymbol],
                classTypeParameterCount: 1
            ),
            for: compareSymbol
        )

        return comparatorSymbol
    }

    /// Register compareBy overloads that take 2 or 3 selectors (STDLIB-613).
    private func registerCompareByMultiSelector(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        comparisonsPkg: [InternedString],
        comparisonsPackageSymbol: SymbolID,
        comparatorSymbol: SymbolID
    ) {
        let comparatorFQName = symbols.symbol(comparatorSymbol)?.fqName ?? comparisonsPkg
        let tParamName = interner.intern("T")
        let tParamFQName = comparatorFQName + [tParamName]
        guard let tParamSymbol = symbols.lookup(fqName: tParamFQName) else { return }
        let tParamType = types.make(.typeParam(TypeParamType(
            symbol: tParamSymbol, nullability: .nonNull
        )))

        let comparatorType = types.make(.classType(ClassType(
            classSymbol: comparatorSymbol,
            args: [.invariant(tParamType)],
            nullability: .nonNull
        )))
        let selectorType = types.make(.functionType(FunctionType(
            params: [tParamType],
            returnType: types.anyType,
            isSuspend: false,
            nullability: .nonNull
        )))

        let functionName = interner.intern("compareBy")
        let functionFQName = comparisonsPkg + [functionName]

        // Register 2-selector and 3-selector overloads
        for arity in 2...3 {
            let paramTypes = Array(repeating: selectorType, count: arity)

            // Check if this overload already exists
            let extLink = arity == 2 ? "kk_comparator_from_multi_selectors" : "kk_comparator_from_multi_selectors3"
            if symbols.lookupAll(fqName: functionFQName).contains(where: { symbolID in
                guard let sig = symbols.functionSignature(for: symbolID) else { return false }
                return sig.parameterTypes == paramTypes && sig.returnType == comparatorType
            }) {
                if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
                    guard let sig = symbols.functionSignature(for: symbolID) else { return false }
                    return sig.parameterTypes == paramTypes && sig.returnType == comparatorType
                }) {
                    symbols.setExternalLinkName(extLink, for: existing)
                }
                continue
            }

            let funcSymbol = symbols.define(
                kind: .function,
                name: functionName,
                fqName: functionFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .inlineFunction]
            )
            symbols.setParentSymbol(comparisonsPackageSymbol, for: funcSymbol)
            symbols.setExternalLinkName(extLink, for: funcSymbol)

            var paramSymbols: [SymbolID] = []
            for i in 0..<arity {
                let paramName = interner.intern("selector\(i + 1)")
                // Use arity-qualified fqName to avoid collisions across overloads
                let paramInternalName = interner.intern("selector\(i + 1)_arity\(arity)")
                let paramSymbol = symbols.define(
                    kind: .valueParameter,
                    name: paramName,
                    fqName: functionFQName + [paramInternalName],
                    declSite: nil,
                    visibility: .private,
                    flags: [.synthetic]
                )
                symbols.setParentSymbol(funcSymbol, for: paramSymbol)
                paramSymbols.append(paramSymbol)
            }

            symbols.setFunctionSignature(
                FunctionSignature(
                    parameterTypes: paramTypes,
                    returnType: comparatorType,
                    isSuspend: false,
                    valueParameterSymbols: paramSymbols,
                    valueParameterHasDefaultValues: Array(repeating: false, count: arity),
                    valueParameterIsVararg: Array(repeating: false, count: arity),
                    typeParameterSymbols: [tParamSymbol],
                    typeParameterUpperBoundsList: [[]]
                ),
                for: funcSymbol
            )
        }

        let varargExtLink = "kk_comparator_from_multi_selectors_vararg"
        if symbols.lookupAll(fqName: functionFQName).contains(where: { symbolID in
            guard let sig = symbols.functionSignature(for: symbolID) else { return false }
            return sig.parameterTypes == [selectorType] &&
                sig.returnType == comparatorType &&
                sig.valueParameterIsVararg == [true]
        }) {
            if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
                guard let sig = symbols.functionSignature(for: symbolID) else { return false }
                return sig.parameterTypes == [selectorType] &&
                    sig.returnType == comparatorType &&
                    sig.valueParameterIsVararg == [true]
            }) {
                symbols.setExternalLinkName(varargExtLink, for: existing)
            }
            return
        }

        let varargFuncSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .inlineFunction]
        )
        symbols.setParentSymbol(comparisonsPackageSymbol, for: varargFuncSymbol)
        symbols.setExternalLinkName(varargExtLink, for: varargFuncSymbol)

        let selectorsParamSymbol = symbols.define(
            kind: .valueParameter,
            name: interner.intern("selectors"),
            fqName: functionFQName + [interner.intern("selectors_vararg")],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(varargFuncSymbol, for: selectorsParamSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [selectorType],
                returnType: comparatorType,
                isSuspend: false,
                valueParameterSymbols: [selectorsParamSymbol],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [true],
                typeParameterSymbols: [tParamSymbol],
                typeParameterUpperBoundsList: [[]]
            ),
            for: varargFuncSymbol
        )
    }

    private func registerNullsComparators(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        comparatorSymbol: SymbolID
    ) {
        guard let compInfo = symbols.symbol(comparatorSymbol) else { return }
        let comparatorFQName = compInfo.fqName
        let tParamName = interner.intern("T")
        let tParamFQName = comparatorFQName + [tParamName]
        guard let tParamSymbol = symbols.lookup(fqName: tParamFQName) else { return }
        let tParamType = types.make(.typeParam(TypeParamType(
            symbol: tParamSymbol, nullability: .nonNull
        )))

        let receiverType = types.make(.classType(ClassType(
            classSymbol: comparatorSymbol,
            args: [.invariant(tParamType)],
            nullability: .nonNull
        )))

        for (name, extLink) in [
            ("nullsFirst", "kk_comparator_nulls_first"),
            ("nullsLast", "kk_comparator_nulls_last"),
        ] {
            let memberName = interner.intern(name)
            let memberFQName = comparatorFQName + [memberName]
            if let existing = symbols.lookup(fqName: memberFQName) {
                symbols.setExternalLinkName(extLink, for: existing)
                continue
            }

            let memberSymbol = symbols.define(
                kind: .function,
                name: memberName,
                fqName: memberFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .inlineFunction]
            )
            symbols.setParentSymbol(comparatorSymbol, for: memberSymbol)
            symbols.setExternalLinkName(extLink, for: memberSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: [],
                    returnType: receiverType,
                    typeParameterSymbols: [tParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: memberSymbol
            )
        }
    }

    /// Register `kotlin.comparisons.nullsFirst(comparator: Comparator<in T>): Comparator<T?>`
    /// (STDLIB-COMP-FN-060). Wraps the provided comparator so that nulls compare first.
    private func registerNullsFirstTopLevelWithComparator(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        comparisonsPkg: [InternedString],
        comparisonsPackageSymbol: SymbolID,
        comparatorSymbol: SymbolID
    ) {
        let functionName = interner.intern("nullsFirst")
        let functionFQName = comparisonsPkg + [functionName]
        let extLink = "kk_comparator_nulls_first_of"

        let tParamName = interner.intern("T")
        let tParamFQName = functionFQName + [tParamName]
        let tParamSymbol: SymbolID = if let existing = symbols.lookup(fqName: tParamFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: tParamName,
                fqName: tParamFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        let tParamTypeNonNull = types.make(.typeParam(TypeParamType(
            symbol: tParamSymbol, nullability: .nonNull
        )))
        let tParamTypeNullable = types.make(.typeParam(TypeParamType(
            symbol: tParamSymbol, nullability: .nullable
        )))

        let comparatorInType = types.make(.classType(ClassType(
            classSymbol: comparatorSymbol,
            args: [.in(tParamTypeNonNull)],
            nullability: .nonNull
        )))
        let comparatorReturnType = types.make(.classType(ClassType(
            classSymbol: comparatorSymbol,
            args: [.invariant(tParamTypeNullable)],
            nullability: .nonNull
        )))

        if symbols.lookupAll(fqName: functionFQName).contains(where: { symbolID in
            guard let sig = symbols.functionSignature(for: symbolID) else { return false }
            return sig.parameterTypes == [comparatorInType] && sig.returnType == comparatorReturnType
        }) {
            if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
                guard let sig = symbols.functionSignature(for: symbolID) else { return false }
                return sig.parameterTypes == [comparatorInType] && sig.returnType == comparatorReturnType
            }) {
                symbols.setExternalLinkName(extLink, for: existing)
            }
            return
        }

        let funcSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(comparisonsPackageSymbol, for: funcSymbol)
        symbols.setExternalLinkName(extLink, for: funcSymbol)

        let comparatorParamName = interner.intern("comparator")
        let comparatorParamSymbol = symbols.define(
            kind: .valueParameter,
            name: comparatorParamName,
            fqName: functionFQName + [comparatorParamName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(funcSymbol, for: comparatorParamSymbol)

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [comparatorInType],
                returnType: comparatorReturnType,
                isSuspend: false,
                valueParameterSymbols: [comparatorParamSymbol],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [false],
                typeParameterSymbols: [tParamSymbol],
                typeParameterUpperBoundsList: [[types.anyType]]
            ),
            for: funcSymbol
        )
    }

    /// Register `kotlin.comparisons.nullsLast(comparator: Comparator<in T>): Comparator<T?>`
    /// (STDLIB-COMP-FN-062). Wraps the provided comparator so that nulls compare last.
    private func registerNullsLastTopLevelWithComparator(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        comparisonsPkg: [InternedString],
        comparisonsPackageSymbol: SymbolID,
        comparatorSymbol: SymbolID
    ) {
        let functionName = interner.intern("nullsLast")
        let functionFQName = comparisonsPkg + [functionName]
        let extLink = "kk_comparator_nulls_last_of"

        let tParamName = interner.intern("T")
        let tParamFQName = functionFQName + [tParamName]
        let tParamSymbol: SymbolID = if let existing = symbols.lookup(fqName: tParamFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: tParamName,
                fqName: tParamFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        let tParamTypeNonNull = types.make(.typeParam(TypeParamType(
            symbol: tParamSymbol, nullability: .nonNull
        )))
        let tParamTypeNullable = types.make(.typeParam(TypeParamType(
            symbol: tParamSymbol, nullability: .nullable
        )))

        let comparatorInType = types.make(.classType(ClassType(
            classSymbol: comparatorSymbol,
            args: [.in(tParamTypeNonNull)],
            nullability: .nonNull
        )))
        let comparatorReturnType = types.make(.classType(ClassType(
            classSymbol: comparatorSymbol,
            args: [.invariant(tParamTypeNullable)],
            nullability: .nonNull
        )))

        if symbols.lookupAll(fqName: functionFQName).contains(where: { symbolID in
            guard let sig = symbols.functionSignature(for: symbolID) else { return false }
            return sig.parameterTypes == [comparatorInType] && sig.returnType == comparatorReturnType
        }) {
            if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
                guard let sig = symbols.functionSignature(for: symbolID) else { return false }
                return sig.parameterTypes == [comparatorInType] && sig.returnType == comparatorReturnType
            }) {
                symbols.setExternalLinkName(extLink, for: existing)
            }
            return
        }

        let funcSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(comparisonsPackageSymbol, for: funcSymbol)
        symbols.setExternalLinkName(extLink, for: funcSymbol)

        let comparatorParamName = interner.intern("comparator")
        let comparatorParamSymbol = symbols.define(
            kind: .valueParameter,
            name: comparatorParamName,
            fqName: functionFQName + [comparatorParamName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(funcSymbol, for: comparatorParamSymbol)

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [comparatorInType],
                returnType: comparatorReturnType,
                isSuspend: false,
                valueParameterSymbols: [comparatorParamSymbol],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [false],
                typeParameterSymbols: [tParamSymbol],
                typeParameterUpperBoundsList: [[types.anyType]]
            ),
            for: funcSymbol
        )
    }

    /// Register `kotlin.comparisons.nullsFirst(): Comparator<T?>`
    /// (STDLIB-COMP-FN-059). Returns a comparator that puts nulls first and uses
    /// natural order for non-null values. No explicit Comparator argument.
    private func registerNullsFirstTopLevelComparable(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        comparisonsPkg: [InternedString],
        comparisonsPackageSymbol: SymbolID,
        comparatorSymbol: SymbolID
    ) {
        let functionName = interner.intern("nullsFirst")
        let functionFQName = comparisonsPkg + [functionName]
        let extLink = "kk_comparator_nulls_first_comparable"

        let tParamName = interner.intern("T")
        let tParamFQName = functionFQName + [interner.intern("T_comparable")]
        let tParamSymbol: SymbolID = if let existing = symbols.lookup(fqName: tParamFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: tParamName,
                fqName: tParamFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        let tParamTypeNullable = types.make(.typeParam(TypeParamType(
            symbol: tParamSymbol, nullability: .nullable
        )))

        let comparatorReturnType = types.make(.classType(ClassType(
            classSymbol: comparatorSymbol,
            args: [.invariant(tParamTypeNullable)],
            nullability: .nonNull
        )))

        if symbols.lookupAll(fqName: functionFQName).contains(where: { symbolID in
            guard let sig = symbols.functionSignature(for: symbolID) else { return false }
            return sig.parameterTypes.isEmpty && sig.returnType == comparatorReturnType
        }) {
            if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
                guard let sig = symbols.functionSignature(for: symbolID) else { return false }
                return sig.parameterTypes.isEmpty && sig.returnType == comparatorReturnType
            }) {
                symbols.setExternalLinkName(extLink, for: existing)
            }
            return
        }

        let funcSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(comparisonsPackageSymbol, for: funcSymbol)
        symbols.setExternalLinkName(extLink, for: funcSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [],
                returnType: comparatorReturnType,
                isSuspend: false,
                typeParameterSymbols: [tParamSymbol],
                typeParameterUpperBoundsList: [[]]
            ),
            for: funcSymbol
        )
    }

    /// Register `kotlin.comparisons.nullsLast(): Comparator<T?>` (STDLIB-COMP-FN-061).
    /// Comparable版（引数なし）。naturalOrder<T>() を内包し null を末尾に配置する。
    private func registerNullsLastTopLevelComparable(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        comparisonsPkg: [InternedString],
        comparisonsPackageSymbol: SymbolID,
        comparatorSymbol: SymbolID
    ) {
        let functionName = interner.intern("nullsLast")
        let functionFQName = comparisonsPkg + [functionName]
        let extLink = "kk_comparator_nulls_last_natural"

        let tParamName = interner.intern("T")
        let tParamFQName = functionFQName + [tParamName]
        let tParamSymbol: SymbolID = if let existing = symbols.lookup(fqName: tParamFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: tParamName,
                fqName: tParamFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        let tParamTypeNullable = types.make(.typeParam(TypeParamType(
            symbol: tParamSymbol, nullability: .nullable
        )))
        let comparatorReturnType = types.make(.classType(ClassType(
            classSymbol: comparatorSymbol,
            args: [.invariant(tParamTypeNullable)],
            nullability: .nonNull
        )))

        if symbols.lookupAll(fqName: functionFQName).contains(where: { symbolID in
            guard let sig = symbols.functionSignature(for: symbolID) else { return false }
            return sig.parameterTypes.isEmpty && sig.returnType == comparatorReturnType
        }) {
            if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
                guard let sig = symbols.functionSignature(for: symbolID) else { return false }
                return sig.parameterTypes.isEmpty && sig.returnType == comparatorReturnType
            }) {
                symbols.setExternalLinkName(extLink, for: existing)
            }
            return
        }

        let funcSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(comparisonsPackageSymbol, for: funcSymbol)
        symbols.setExternalLinkName(extLink, for: funcSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [],
                returnType: comparatorReturnType,
                isSuspend: false,
                typeParameterSymbols: [tParamSymbol],
                typeParameterUpperBoundsList: [[]]
            ),
            for: funcSymbol
        )
    }
}
