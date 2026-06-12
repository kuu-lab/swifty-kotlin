
/// Synthetic Kotlin/JS collections `JsReadonlyMap<K, V>` external interface surface.
extension DataFlowSemaPhase {
    func registerSyntheticJsCollectionsReadonlyMapStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let pkg = ensurePackage(
            path: ["kotlin", "js", "collections"],
            symbols: symbols,
            interner: interner
        )
        _ = ensureJsReadonlyMapForConversions(
            packageFQName: pkg,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func ensureJsReadonlyMapForConversions(
        packageFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> (symbol: SymbolID, keyTypeParameterSymbol: SymbolID, valueTypeParameterSymbol: SymbolID) {
        let interfaceFQName = packageFQName + [interner.intern("JsReadonlyMap")]
        let interfaceSymbol = ensureInterfaceSymbol(
            named: "JsReadonlyMap",
            in: packageFQName,
            symbols: symbols,
            interner: interner
        )
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: interfaceSymbol)
        }
        appendJsCollectionsReadonlyMapAnnotation(to: interfaceSymbol, symbols: symbols)

        let keyTypeParamName = interner.intern("K")
        let keyTypeParamFQName = interfaceFQName + [keyTypeParamName]
        let keyTypeParamSymbol: SymbolID
        if let existing = symbols.lookup(fqName: keyTypeParamFQName),
           symbols.symbol(existing)?.kind == .typeParameter {
            keyTypeParamSymbol = existing
        } else {
            keyTypeParamSymbol = symbols.define(
                kind: .typeParameter,
                name: keyTypeParamName,
                fqName: keyTypeParamFQName,
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
        }
        symbols.setParentSymbol(interfaceSymbol, for: keyTypeParamSymbol)

        let valueTypeParamName = interner.intern("V")
        let valueTypeParamFQName = interfaceFQName + [valueTypeParamName]
        let valueTypeParamSymbol: SymbolID
        if let existing = symbols.lookup(fqName: valueTypeParamFQName),
           symbols.symbol(existing)?.kind == .typeParameter {
            valueTypeParamSymbol = existing
        } else {
            valueTypeParamSymbol = symbols.define(
                kind: .typeParameter,
                name: valueTypeParamName,
                fqName: valueTypeParamFQName,
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
        }
        symbols.setParentSymbol(interfaceSymbol, for: valueTypeParamSymbol)

        let keyType = types.make(.typeParam(TypeParamType(
            symbol: keyTypeParamSymbol,
            nullability: .nonNull
        )))
        let valueType = types.make(.typeParam(TypeParamType(
            symbol: valueTypeParamSymbol,
            nullability: .nonNull
        )))
        let interfaceType = types.make(.classType(ClassType(
            classSymbol: interfaceSymbol,
            args: [.invariant(keyType), .out(valueType)],
            nullability: .nonNull
        )))

        types.setNominalTypeParameterSymbols([keyTypeParamSymbol, valueTypeParamSymbol], for: interfaceSymbol)
        types.setNominalTypeParameterVariances([.invariant, .out], for: interfaceSymbol)
        symbols.setPropertyType(interfaceType, for: interfaceSymbol)

        return (interfaceSymbol, keyTypeParamSymbol, valueTypeParamSymbol)
    }

    private func appendJsCollectionsReadonlyMapAnnotation(
        to symbol: SymbolID,
        symbols: SymbolTable
    ) {
        let experimentalRecord = MetadataAnnotationRecord(
            annotationFQName: "kotlin.js.ExperimentalJsCollectionsApi"
        )
        var annotations = symbols.annotations(for: symbol)
        if !annotations.contains(experimentalRecord) {
            annotations.append(experimentalRecord)
            symbols.setAnnotations(annotations, for: symbol)
        }
    }
}
