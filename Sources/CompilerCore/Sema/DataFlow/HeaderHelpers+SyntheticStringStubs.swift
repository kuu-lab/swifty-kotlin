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
        let localeType = registerSyntheticStringConversionStubs(context: context)
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
    func patchSourceBackedCharIteratorReturnType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let charIteratorFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("CharIterator"),
        ]
        guard let charIteratorSymbol = symbols.lookup(fqName: charIteratorFQName) else {
            return
        }
        let charIteratorType = types.make(.classType(ClassType(
            classSymbol: charIteratorSymbol,
            args: [],
            nullability: .nonNull
        )))
        let stringType = types.stringType
        let charSequenceType: TypeID? = types.charSequenceInterfaceSymbol.map { charSequenceSymbol in
            types.make(.classType(ClassType(
                classSymbol: charSequenceSymbol,
                args: [],
                nullability: .nonNull
            )))
        }

        let iteratorFQName = [interner.intern("kotlin"), interner.intern("text"), interner.intern("iterator")]
        for functionSymbol in symbols.lookupAll(fqName: iteratorFQName) {
            guard let signature = symbols.functionSignature(for: functionSymbol),
                  signature.parameterTypes.isEmpty,
                  let receiver = signature.receiverType,
                  receiver == stringType || receiver == charSequenceType
            else {
                continue
            }
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: signature.receiverType,
                    parameterTypes: signature.parameterTypes,
                    returnType: charIteratorType,
                    isSuspend: signature.isSuspend,
                    canThrow: signature.canThrow,
                    valueParameterSymbols: signature.valueParameterSymbols,
                    valueParameterHasDefaultValues: signature.valueParameterHasDefaultValues,
                    valueParameterIsVararg: signature.valueParameterIsVararg,
                    valueParameterAllowsNonLocalReturn: signature.valueParameterAllowsNonLocalReturn,
                    typeParameterSymbols: signature.typeParameterSymbols,
                    reifiedTypeParameterIndices: signature.reifiedTypeParameterIndices,
                    typeParameterUpperBoundsList: signature.typeParameterUpperBoundsList,
                    classTypeParameterCount: signature.classTypeParameterCount
                ),
                for: functionSymbol
            )
        }
    }

    /// KSP-626: `IndexedValue` is declared in bundled Kotlin source, so its
    /// symbol does not exist while the `CharSequence.withIndex()` stub is
    /// registered. Rewrite the placeholder `Iterable<Any>` return type once
    /// header collection has defined the source-backed class.
    func patchSourceBackedIndexedValueReturnType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let collectionsPkg = [interner.intern("kotlin"), interner.intern("collections")]
        guard let indexedValueSymbol = symbols.lookup(fqName: collectionsPkg + [interner.intern("IndexedValue")]),
              let iterableSymbol = symbols.lookup(fqName: collectionsPkg + [interner.intern("Iterable")])
        else {
            return
        }
        let indexedValueCharType = types.make(.classType(ClassType(
            classSymbol: indexedValueSymbol,
            args: [.out(types.charType)],
            nullability: .nonNull
        )))
        let iterableIndexedValueCharType = types.make(.classType(ClassType(
            classSymbol: iterableSymbol,
            args: [.out(indexedValueCharType)],
            nullability: .nonNull
        )))

        let stringType = types.stringType
        let charSequenceType: TypeID? = types.charSequenceInterfaceSymbol.map { charSequenceSymbol in
            types.make(.classType(ClassType(
                classSymbol: charSequenceSymbol,
                args: [],
                nullability: .nonNull
            )))
        }

        let withIndexFQName = [interner.intern("kotlin"), interner.intern("text"), interner.intern("withIndex")]
        for functionSymbol in symbols.lookupAll(fqName: withIndexFQName) {
            guard let signature = symbols.functionSignature(for: functionSymbol),
                  signature.parameterTypes.isEmpty,
                  let receiver = signature.receiverType,
                  receiver == stringType || receiver == charSequenceType
            else {
                continue
            }
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: signature.receiverType,
                    parameterTypes: signature.parameterTypes,
                    returnType: iterableIndexedValueCharType,
                    isSuspend: signature.isSuspend,
                    canThrow: signature.canThrow,
                    valueParameterSymbols: signature.valueParameterSymbols,
                    valueParameterHasDefaultValues: signature.valueParameterHasDefaultValues,
                    valueParameterIsVararg: signature.valueParameterIsVararg,
                    valueParameterAllowsNonLocalReturn: signature.valueParameterAllowsNonLocalReturn,
                    typeParameterSymbols: signature.typeParameterSymbols,
                    reifiedTypeParameterIndices: signature.reifiedTypeParameterIndices,
                    typeParameterUpperBoundsList: signature.typeParameterUpperBoundsList,
                    classTypeParameterCount: signature.classTypeParameterCount
                ),
                for: functionSymbol
            )
        }
    }
}
