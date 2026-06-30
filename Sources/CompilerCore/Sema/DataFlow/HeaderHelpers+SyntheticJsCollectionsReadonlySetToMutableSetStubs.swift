/// Synthetic Kotlin/JS collections `JsReadonlySet<out E>` surface and its conversion members.
extension DataFlowSemaPhase {
    func registerSyntheticJsCollectionsReadonlySetStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let pkg = ensurePackage(
            path: ["kotlin", "js", "collections"],
            symbols: symbols,
            interner: interner
        )
        let readonlySet = ensureJsReadonlySetForConversions(
            packageFQName: pkg,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerJsReadonlySetToMutableSetMember(
            symbols: symbols,
            types: types,
            interner: interner,
            readonlySetSymbol: readonlySet.symbol,
            readonlySetTypeParamSymbol: readonlySet.typeParameterSymbol
        )
        // STDLIB-JS-COLLECTIONS-FN-006
        registerJsReadonlySetToSetMember(
            readonlySetSymbol: readonlySet.symbol,
            readonlySetTypeParamSymbol: readonlySet.typeParameterSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func registerJsReadonlySetToMutableSetMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        readonlySetSymbol: SymbolID,
        readonlySetTypeParamSymbol: SymbolID
    ) {
        let kotlinCollectionsPkg = [interner.intern("kotlin"), interner.intern("collections")]
        guard let mutableSetSymbol = symbols.lookup(
            fqName: kotlinCollectionsPkg + [interner.intern("MutableSet")]
        ) else { return }
        guard let readonlySetFQName = symbols.symbol(readonlySetSymbol)?.fqName else { return }

        let memberName = interner.intern("toMutableSet")
        let memberFQName = readonlySetFQName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }

        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: readonlySetTypeParamSymbol,
            nullability: .nonNull
        )))
        let receiverType = types.make(.classType(ClassType(
            classSymbol: readonlySetSymbol,
            args: [.out(typeParamType)],
            nullability: .nonNull
        )))
        let mutableSetType = types.make(.classType(ClassType(
            classSymbol: mutableSetSymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))

        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .operatorFunction]
        )
        symbols.setParentSymbol(readonlySetSymbol, for: memberSymbol)
        symbols.setExternalLinkName("kk_js_readonly_set_toMutableSet", for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [],
                returnType: mutableSetType,
                typeParameterSymbols: [readonlySetTypeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    /// STDLIB-JS-COLLECTIONS-FN-006: Register `JsReadonlySet<E>.toSet()` returning `Set<E>`.
    ///
    /// Shares the `kk_set_to_set` runtime entry point because `JsReadonlySet` is
    /// backed by `RuntimeSetBox` at runtime — the same representation used for
    /// Kotlin's `Set`.
    private func registerJsReadonlySetToSetMember(
        readonlySetSymbol: SymbolID,
        readonlySetTypeParamSymbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        guard let readonlySetFQName = symbols.symbol(readonlySetSymbol)?.fqName else { return }
        let memberName = interner.intern("toSet")
        let memberFQName = readonlySetFQName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }

        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: readonlySetTypeParamSymbol,
            nullability: .nonNull
        )))
        let receiverType = types.make(.classType(ClassType(
            classSymbol: readonlySetSymbol,
            args: [.out(typeParamType)],
            nullability: .nonNull
        )))

        let kotlinCollectionsPkg = [interner.intern("kotlin"), interner.intern("collections")]
        guard let setSymbol = symbols.lookup(fqName: kotlinCollectionsPkg + [interner.intern("Set")]) else { return }
        let returnType = types.make(.classType(ClassType(
            classSymbol: setSymbol,
            args: [.out(typeParamType)],
            nullability: .nonNull
        )))

        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(readonlySetSymbol, for: memberSymbol)
        symbols.setExternalLinkName("kk_set_to_set", for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [],
                returnType: returnType,
                typeParameterSymbols: [readonlySetTypeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    func ensureJsReadonlySetForConversions(
        packageFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> (symbol: SymbolID, typeParameterSymbol: SymbolID) {
        let interfaceName = interner.intern("JsReadonlySet")
        let interfaceFQName = packageFQName + [interfaceName]
        let interfaceSymbol = ensureInterfaceSymbol(
            named: "JsReadonlySet",
            in: packageFQName,
            symbols: symbols,
            interner: interner
        )
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: interfaceSymbol)
        }
        appendJsCollectionsReadonlySetAnnotation(to: interfaceSymbol, symbols: symbols)

        let typeParamName = interner.intern("E")
        let typeParamFQName = interfaceFQName + [typeParamName]
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
        symbols.setParentSymbol(interfaceSymbol, for: typeParamSymbol)

        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        let interfaceType = types.make(.classType(ClassType(
            classSymbol: interfaceSymbol,
            args: [.out(typeParamType)],
            nullability: .nonNull
        )))

        types.setNominalTypeParameterSymbols([typeParamSymbol], for: interfaceSymbol)
        types.setNominalTypeParameterVariances([.out], for: interfaceSymbol)
        symbols.setPropertyType(interfaceType, for: interfaceSymbol)

        return (interfaceSymbol, typeParamSymbol)
    }

    func appendJsCollectionsReadonlySetAnnotation(
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
