/// Synthetic nominal anchor for the bundled `kotlin.Comparator` fun interface.
///
/// KSP-725 migrates the `Comparator` interface itself to real Kotlin source
/// (`Sources/CompilerCore/Stdlib/kotlin/Comparator.kt`). This file keeps only
/// a placeholder so that other early synthetic stubs — notably
/// `String.Companion.CASE_INSENSITIVE_ORDER` and `CallTypeChecker` comparator
/// helpers — can resolve the `kotlin.Comparator` symbol before bundled header
/// collection runs. The bundled source reuses this symbol via
/// `HeaderCollection.reusableSyntheticSourceDeclarationKeys`.
extension DataFlowSemaPhase {
    func registerSyntheticComparatorStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinPkg = ensurePackage(
            path: ["kotlin"],
            symbols: symbols,
            interner: interner
        )

        // Bare `.interface` placeholder: its kind must match the real
        // `fun interface Comparator` in bundled source so header collection
        // reuses it instead of reporting a duplicate declaration.
        let comparatorSymbol = ensureInterfaceSymbol(
            named: "Comparator",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        symbols.insertFlags(.funInterface, for: comparatorSymbol)

        // Register the type parameter early so references such as
        // `Comparator<String>` can be formed before bundled source is collected.
        let tParamName = interner.intern("T")
        let comparatorName = interner.intern("Comparator")
        let tParamFQName = kotlinPkg + [comparatorName, tParamName]
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
        types.setNominalTypeParameterSymbols([tParamSymbol], for: comparatorSymbol)
        types.setNominalTypeParameterVariances([.in], for: comparatorSymbol)

        // Pre-register the single abstract method so that imported library
        // vtable/itable layouts can resolve `kotlin.Comparator.compare` before
        // bundled source is collected. The bundled declaration reuses this
        // placeholder through `MemberHeaderCollection` synthetic-member reuse.
        let tParamType = types.make(.typeParam(TypeParamType(
            symbol: tParamSymbol,
            nullability: .nonNull
        )))
        let compareName = interner.intern("compare")
        let compareFQName = kotlinPkg + [comparatorName, compareName]
        guard symbols.lookup(fqName: compareFQName) == nil else {
            return
        }
        let receiverType = types.make(.classType(ClassType(
            classSymbol: comparatorSymbol,
            args: [.invariant(tParamType)],
            nullability: .nonNull
        )))
        let compareSymbol = symbols.define(
            kind: .function,
            name: compareName,
            fqName: compareFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .abstractType]
        )
        symbols.setParentSymbol(comparatorSymbol, for: compareSymbol)
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
    }
}
