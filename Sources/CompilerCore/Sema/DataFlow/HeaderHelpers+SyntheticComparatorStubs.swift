
/// Synthetic anchor for the built-in `kotlin.Comparator` fun interface.
/// KSP-309 / KSP-461 moved every comparison helper (compareBy, compareValues*,
/// nullsFirst/nullsLast, naturalOrder/reverseOrder, reversed, then*) to bundled
/// Kotlin source; only the interface itself stays synthetic.
extension DataFlowSemaPhase {
    func registerSyntheticComparatorStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinPkg: [InternedString] = [interner.intern("kotlin")]
        let comparisonsPkg: [InternedString] = kotlinPkg + [interner.intern("comparisons")]
        _ = ensureSyntheticPackage(fqName: kotlinPkg, symbols: symbols)
        _ = ensureSyntheticPackage(fqName: comparisonsPkg, symbols: symbols)

        _ = registerComparatorInterface(
            symbols: symbols,
            types: types,
            interner: interner,
            kotlinPkg: kotlinPkg
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
}
