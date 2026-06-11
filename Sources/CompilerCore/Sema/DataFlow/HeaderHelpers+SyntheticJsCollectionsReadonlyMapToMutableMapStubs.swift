/// Synthetic Kotlin/JS collections `JsReadonlyMap<K, V>` conversion surfaces.
extension DataFlowSemaPhase {
    func registerSyntheticJsCollectionsReadonlyMapToMutableMapStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let pkg = ensurePackage(
            path: ["kotlin", "js", "collections"],
            symbols: symbols,
            interner: interner
        )
        let collectionsPkg = ensurePackage(
            path: ["kotlin", "collections"],
            symbols: symbols,
            interner: interner
        )
        let readonlyMap = ensureJsReadonlyMapForToMutableMap(
            packageFQName: pkg,
            symbols: symbols,
            types: types,
            interner: interner
        )
        guard let mutableMapSymbol = symbols.lookup(fqName: collectionsPkg + [interner.intern("MutableMap")]) else {
            return
        }

        let keyType = types.make(.typeParam(TypeParamType(
            symbol: readonlyMap.keyTypeParameterSymbol,
            nullability: .nonNull
        )))
        let valueType = types.make(.typeParam(TypeParamType(
            symbol: readonlyMap.valueTypeParameterSymbol,
            nullability: .nonNull
        )))
        let receiverType = types.make(.classType(ClassType(
            classSymbol: readonlyMap.symbol,
            args: [.invariant(keyType), .out(valueType)],
            nullability: .nonNull
        )))
        let returnType = types.make(.classType(ClassType(
            classSymbol: mutableMapSymbol,
            args: [.invariant(keyType), .invariant(valueType)],
            nullability: .nonNull
        )))

        registerJsReadonlyMapToMutableMapMember(
            ownerSymbol: readonlyMap.symbol,
            ownerType: receiverType,
            returnType: returnType,
            keyTypeParamSymbol: readonlyMap.keyTypeParameterSymbol,
            valueTypeParamSymbol: readonlyMap.valueTypeParameterSymbol,
            symbols: symbols,
            interner: interner
        )
    }

    private func ensureJsReadonlyMapForToMutableMap(
        packageFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> (symbol: SymbolID, keyTypeParameterSymbol: SymbolID, valueTypeParameterSymbol: SymbolID) {
        let interfaceName = interner.intern("JsReadonlyMap")
        let interfaceFQName = packageFQName + [interfaceName]
        let interfaceSymbol = ensureInterfaceSymbol(
            named: "JsReadonlyMap",
            in: packageFQName,
            symbols: symbols,
            interner: interner
        )
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: interfaceSymbol)
        }
        appendJsCollectionsReadonlyMapToMutableMapAnnotation(to: interfaceSymbol, symbols: symbols)

        let keyTypeParamSymbol = ensureJsReadonlyMapToMutableMapTypeParameter(
            named: "K",
            in: interfaceFQName,
            owner: interfaceSymbol,
            symbols: symbols,
            interner: interner
        )
        let valueTypeParamSymbol = ensureJsReadonlyMapToMutableMapTypeParameter(
            named: "V",
            in: interfaceFQName,
            owner: interfaceSymbol,
            symbols: symbols,
            interner: interner
        )
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

    private func ensureJsReadonlyMapToMutableMapTypeParameter(
        named name: String,
        in ownerFQName: [InternedString],
        owner: SymbolID,
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID {
        let typeParamName = interner.intern(name)
        let typeParamFQName = ownerFQName + [typeParamName]
        let typeParamSymbol: SymbolID
        if let existing = symbols.lookup(fqName: typeParamFQName),
           symbols.symbol(existing)?.kind == .typeParameter {
            typeParamSymbol = existing
        } else {
            typeParamSymbol = symbols.define(
                kind: .typeParameter,
                name: typeParamName,
                fqName: typeParamFQName,
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
        }
        symbols.setParentSymbol(owner, for: typeParamSymbol)
        return typeParamSymbol
    }

    private func registerJsReadonlyMapToMutableMapMember(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        returnType: TypeID,
        keyTypeParamSymbol: SymbolID,
        valueTypeParamSymbol: SymbolID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let functionName = interner.intern("toMutableMap")
        let functionFQName = ownerInfo.fqName + [functionName]
        let externalLinkName = "kk_js_map_toMutableMap"
        let typeParameterSymbols = [keyTypeParamSymbol, valueTypeParamSymbol]

        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbol in
            guard let signature = symbols.functionSignature(for: symbol) else {
                return false
            }
            return signature.receiverType == ownerType
                && signature.parameterTypes.isEmpty
                && signature.returnType == returnType
                && signature.typeParameterSymbols == typeParameterSymbols
                && signature.classTypeParameterCount == 2
        }) {
            symbols.setExternalLinkName(externalLinkName, for: existing)
            appendJsCollectionsReadonlyMapToMutableMapAnnotation(to: existing, symbols: symbols)
            return
        }

        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: functionSymbol)
        symbols.setExternalLinkName(externalLinkName, for: functionSymbol)
        appendJsCollectionsReadonlyMapToMutableMapAnnotation(to: functionSymbol, symbols: symbols)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: ownerType,
                parameterTypes: [],
                returnType: returnType,
                typeParameterSymbols: typeParameterSymbols,
                classTypeParameterCount: 2
            ),
            for: functionSymbol
        )
    }

    private func appendJsCollectionsReadonlyMapToMutableMapAnnotation(
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
