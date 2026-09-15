import Foundation
typealias SyntheticStringStubContext = (symbols: SymbolTable, types: TypeSystem, interner: StringInterner, kotlinTextPkg: [InternedString], kotlinRootPkg: [InternedString], stringType: TypeID, charSequenceSymbol: SymbolID, charSequenceType: TypeID, boolType: TypeID, intType: TypeID, longType: TypeID, charType: TypeID, nullableCharType: TypeID, listStringType: TypeID)
extension DataFlowSemaPhase {
    func registerSyntheticStringStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinTextPkg = ensureKotlinTextPackage(symbols: symbols, interner: interner)
        let kotlinRootPkg = ensurePackage(path: ["kotlin"], symbols: symbols, interner: interner)
        let stringType = types.stringType
        // String is a compiler/runtime nominal shell. The bundled source owns
        // CharSequence whenever it is available; the fallback keeps bootstrap
        // contexts that intentionally omit bundled stdlib headers functional.
        let charSequenceSymbol = symbols.lookup(
            fqName: kotlinRootPkg + [interner.intern("CharSequence")]
        ) ?? ensureInterfaceSymbol(
            named: "CharSequence",
            in: kotlinRootPkg,
            symbols: symbols,
            interner: interner
        )
        let charSequenceType = types.make(.classType(ClassType(
            classSymbol: charSequenceSymbol, args: [], nullability: .nonNull
        )))
        types.charSequenceInterfaceSymbol = charSequenceSymbol
        if let kotlinRootPkgSymbol = symbols.lookup(fqName: kotlinRootPkg) {
            symbols.setParentSymbol(kotlinRootPkgSymbol, for: charSequenceSymbol)
        }
        let boolType = types.make(.primitive(.boolean, .nonNull))
        let intType = types.intType
        let longType = types.make(.primitive(.long, .nonNull))
        let charType = types.make(.primitive(.char, .nonNull))
        let nullableCharType = types.make(.primitive(.char, .nullable))
        let listStringType = makeListOfStringType(symbols: symbols, types: types, interner: interner)
        let context: SyntheticStringStubContext = (symbols, types, interner, kotlinTextPkg, kotlinRootPkg, stringType, charSequenceSymbol, charSequenceType, boolType, intType, longType, charType, nullableCharType, listStringType)
        // KSP-717: `Locale` is source-backed (`java/util/Locale.kt`,
        // predeclared in Phase.swift before this registration runs). Only the
        // still-synthetic `String.Companion.format(locale, ...)` overload
        // below needs a `localeType` reference to it.
        let javaUtilPkg = ensurePackage(path: ["java", "util"], symbols: symbols, interner: interner)
        let localeSymbol = ensureClassSymbol(named: "Locale", in: javaUtilPkg, symbols: symbols, interner: interner)
        let localeType = types.make(.classType(ClassType(
            classSymbol: localeSymbol, args: [], nullability: .nonNull
        )))
        registerSyntheticStringCoreStubs(context: context)
        let nullableStringType = registerSyntheticStringQueryStubs(context: context)
        let stringClassSymbol = registerSyntheticStringEncodingStubs(context: context)
        registerSyntheticStringFormatStubs(context: context, localeType: localeType,
            stringClassSymbol: stringClassSymbol, nullableStringType: nullableStringType)
    }
    private func ensureKotlinTextPackage(
        symbols: SymbolTable,
        interner: StringInterner
    ) -> [InternedString] {
        let kotlinTextPkg: [InternedString] = [interner.intern("kotlin"), interner.intern("text")]
        if symbols.lookup(fqName: kotlinTextPkg) == nil {
            _ = symbols.define(
                kind: .package,
                name: interner.intern("text"),
                fqName: kotlinTextPkg,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        return kotlinTextPkg
    }
}
