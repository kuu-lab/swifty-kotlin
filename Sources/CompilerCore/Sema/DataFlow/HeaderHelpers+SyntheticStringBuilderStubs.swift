/// Synthetic signatures for the source-backed StringBuilder type.
///
/// The Kotlin stdlib source owns StringBuilder behavior. These signatures keep
/// Sema contexts that do not load the bundled source directly from losing the
/// type surface, but they intentionally do not attach kk_string_builder_* links
/// to public API members.
func ensureKotlinTextStringBuilderSymbol(symbols: SymbolTable, interner: StringInterner) -> SymbolID {
    let kotlinPkg = [interner.intern("kotlin")]
    let kotlinTextPkg = kotlinPkg + [interner.intern("text")]
    _ = ensureSyntheticPackage(fqName: kotlinPkg, symbols: symbols)
    _ = ensureSyntheticPackage(fqName: kotlinTextPkg, symbols: symbols)

    let stringBuilderName = interner.intern("StringBuilder")
    let stringBuilderFQName = kotlinTextPkg + [stringBuilderName]
    if let existing = symbols.lookup(fqName: stringBuilderFQName) {
        return existing
    }
    return symbols.define(
        kind: .class,
        name: stringBuilderName,
        fqName: stringBuilderFQName,
        declSite: nil,
        visibility: .public,
        flags: [.synthetic]
    )
}

extension DataFlowSemaPhase {
    func patchSourceBackedStringBuilderSupertypes(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinTextPkg = ensureKotlinTextPackage(symbols: symbols, interner: interner)
        let sbName = interner.intern("StringBuilder")
        guard let sbSymbol = symbols.lookup(fqName: kotlinTextPkg + [sbName]) else {
            return
        }
        patchStringBuilderSupertypes(
            sbSymbol: sbSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    func registerSyntheticStringBuilderStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinTextPkg = ensureKotlinTextPackage(symbols: symbols, interner: interner)
        let sbSymbol = ensureClassSymbol(named: "StringBuilder", in: kotlinTextPkg, symbols: symbols, interner: interner)
        let sbType = types.make(.classType(ClassType(
            classSymbol: sbSymbol, args: [], nullability: .nonNull
        )))
        patchStringBuilderSupertypes(
            sbSymbol: sbSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )

        let stringType = types.stringType
        let nullableStringType = types.makeNullable(stringType)
        let nullableAnyType = types.makeNullable(types.anyType)
        let intType = types.intType
        let charType = types.make(.primitive(.char, .nonNull))
        let booleanType = types.make(.primitive(.boolean, .nonNull))
        let longType = types.make(.primitive(.long, .nonNull))
        let floatType = types.make(.primitive(.float, .nonNull))
        let doubleType = types.make(.primitive(.double, .nonNull))
        let kotlinPkg = ensurePackage(path: ["kotlin"], symbols: symbols, interner: interner)
        let charSequenceSymbol = ensureInterfaceSymbol(
            named: "CharSequence",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        let charSequenceType = types.make(.classType(ClassType(
            classSymbol: charSequenceSymbol,
            args: [],
            nullability: .nonNull
        )))
        let nullableCharSequenceType = types.makeNullable(charSequenceType)

        registerStringBuilderMemberProperty(
            named: "length",
            ownerSymbol: sbSymbol,
            returnType: intType,
            symbols: symbols,
            interner: interner
        )

        registerStringBuilderMemberFunction(
            named: "get",
            ownerSymbol: sbSymbol,
            ownerType: sbType,
            parameters: [("index", intType, false, false)],
            returnType: charType,
            symbols: symbols,
            interner: interner,
            extraFlags: [.operatorFunction]
        )
        registerStringBuilderMemberFunction(
            named: "subSequence",
            ownerSymbol: sbSymbol,
            ownerType: sbType,
            parameters: [("startIndex", intType, false, false), ("endIndex", intType, false, false)],
            returnType: charSequenceType,
            symbols: symbols,
            interner: interner
        )

        let appendOverloads: [[(String, TypeID, Bool, Bool)]] = [
            [("value", charType, false, false)],
            [("value", nullableCharSequenceType, false, false)],
            [
                ("value", nullableCharSequenceType, false, false),
                ("startIndex", intType, false, false),
                ("endIndex", intType, false, false),
            ],
            [("value", nullableStringType, false, false)],
            [("value", booleanType, false, false)],
            [("value", intType, false, false)],
            [("value", longType, false, false)],
            [("value", floatType, false, false)],
            [("value", doubleType, false, false)],
            [("value", nullableStringType, false, true)],
            [("value", nullableAnyType, false, true)],
        ]
        for overload in appendOverloads {
            registerStringBuilderMemberFunction(
                named: "append",
                ownerSymbol: sbSymbol,
                ownerType: sbType,
                parameters: overload,
                returnType: sbType,
                symbols: symbols,
                interner: interner
            )
        }

        registerStringBuilderMemberFunction(
            named: "appendLine",
            ownerSymbol: sbSymbol,
            ownerType: sbType,
            parameters: [("value", nullableAnyType, false, false)],
            returnType: sbType,
            symbols: symbols,
            interner: interner
        )
        registerStringBuilderMemberFunction(
            named: "appendLine",
            ownerSymbol: sbSymbol,
            ownerType: sbType,
            parameters: [],
            returnType: sbType,
            symbols: symbols,
            interner: interner
        )

        let insertOverloads: [[(String, TypeID, Bool, Bool)]] = [
            [("index", intType, false, false), ("value", nullableAnyType, false, false)],
            [("index", intType, false, false), ("value", nullableStringType, false, false)],
            [("index", intType, false, false), ("value", charType, false, false)],
            [("index", intType, false, false), ("value", booleanType, false, false)],
            [("index", intType, false, false), ("value", intType, false, false)],
            [("index", intType, false, false), ("value", longType, false, false)],
            [("index", intType, false, false), ("value", floatType, false, false)],
            [("index", intType, false, false), ("value", doubleType, false, false)],
        ]
        for overload in insertOverloads {
            registerStringBuilderMemberFunction(
                named: "insert",
                ownerSymbol: sbSymbol,
                ownerType: sbType,
                parameters: overload,
                returnType: sbType,
                symbols: symbols,
                interner: interner
            )
        }

        for name in ["delete", "deleteRange"] {
            registerStringBuilderMemberFunction(
                named: name,
                ownerSymbol: sbSymbol,
                ownerType: sbType,
                parameters: [("startIndex", intType, false, false), ("endIndex", intType, false, false)],
                returnType: sbType,
                symbols: symbols,
                interner: interner
            )
        }

        for name in ["clear", "reverse"] {
            registerStringBuilderMemberFunction(
                named: name,
                ownerSymbol: sbSymbol,
                ownerType: sbType,
                parameters: [],
                returnType: sbType,
                symbols: symbols,
                interner: interner
            )
        }

        for name in ["deleteCharAt", "deleteAt"] {
            registerStringBuilderMemberFunction(
                named: name,
                ownerSymbol: sbSymbol,
                ownerType: sbType,
                parameters: [("index", intType, false, false)],
                returnType: sbType,
                symbols: symbols,
                interner: interner
            )
        }

        registerStringBuilderMemberFunction(
            named: "appendRange",
            ownerSymbol: sbSymbol,
            ownerType: sbType,
            parameters: [
                ("value", charSequenceType, false, false),
                ("startIndex", intType, false, false),
                ("endIndex", intType, false, false),
            ],
            returnType: sbType,
            symbols: symbols,
            interner: interner
        )
        registerStringBuilderMemberFunction(
            named: "insertRange",
            ownerSymbol: sbSymbol,
            ownerType: sbType,
            parameters: [
                ("index", intType, false, false),
                ("value", charSequenceType, false, false),
                ("startIndex", intType, false, false),
                ("endIndex", intType, false, false),
            ],
            returnType: sbType,
            symbols: symbols,
            interner: interner
        )
        registerStringBuilderMemberFunction(
            named: "setRange",
            ownerSymbol: sbSymbol,
            ownerType: sbType,
            parameters: [
                ("startIndex", intType, false, false),
                ("endIndex", intType, false, false),
                ("value", stringType, false, false),
            ],
            returnType: sbType,
            symbols: symbols,
            interner: interner
        )
        registerStringBuilderMemberFunction(
            named: "replace",
            ownerSymbol: sbSymbol,
            ownerType: sbType,
            parameters: [
                ("start", intType, false, false),
                ("end", intType, false, false),
                ("str", stringType, false, false),
            ],
            returnType: sbType,
            symbols: symbols,
            interner: interner
        )
        registerStringBuilderMemberFunction(
            named: "setCharAt",
            ownerSymbol: sbSymbol,
            ownerType: sbType,
            parameters: [("index", intType, false, false), ("value", charType, false, false)],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )
        registerStringBuilderMemberFunction(
            named: "set",
            ownerSymbol: sbSymbol,
            ownerType: sbType,
            parameters: [("index", intType, false, false), ("value", charType, false, false)],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner,
            extraFlags: [.operatorFunction]
        )

        registerStringBuilderMemberFunction(
            named: "capacity",
            ownerSymbol: sbSymbol,
            ownerType: sbType,
            parameters: [],
            returnType: intType,
            symbols: symbols,
            interner: interner
        )
        registerStringBuilderMemberFunction(
            named: "ensureCapacity",
            ownerSymbol: sbSymbol,
            ownerType: sbType,
            parameters: [("minimumCapacity", intType, false, false)],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )
        registerStringBuilderMemberFunction(
            named: "trimToSize",
            ownerSymbol: sbSymbol,
            ownerType: sbType,
            parameters: [],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )
        registerStringBuilderMemberFunction(
            named: "toString",
            ownerSymbol: sbSymbol,
            ownerType: sbType,
            parameters: [],
            returnType: stringType,
            symbols: symbols,
            interner: interner
        )
    }

    private func patchStringBuilderSupertypes(
        sbSymbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinTextPkg = ensureKotlinTextPackage(symbols: symbols, interner: interner)
        let kotlinPkg = ensurePackage(path: ["kotlin"], symbols: symbols, interner: interner)
        let appendableSymbol = ensureInterfaceSymbol(
            named: "Appendable",
            in: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )
        let charSequenceSymbol = ensureInterfaceSymbol(
            named: "CharSequence",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        if let kotlinTextPkgSymbol = symbols.lookup(fqName: kotlinTextPkg) {
            symbols.setParentSymbol(kotlinTextPkgSymbol, for: appendableSymbol)
        }
        if let kotlinPkgSymbol = symbols.lookup(fqName: kotlinPkg) {
            symbols.setParentSymbol(kotlinPkgSymbol, for: charSequenceSymbol)
        }
        symbols.setDirectSupertypes([appendableSymbol, charSequenceSymbol], for: sbSymbol)
        types.setNominalDirectSupertypes([appendableSymbol, charSequenceSymbol], for: sbSymbol)
        if let ownerInfo = symbols.symbol(sbSymbol) {
            let lengthName = interner.intern("length")
            for candidate in symbols.lookupAll(fqName: ownerInfo.fqName + [lengthName]) {
                guard symbols.symbol(candidate)?.kind == .property else {
                    continue
                }
                symbols.setExternalLinkName("kk_string_builder_length_prop", for: candidate)
            }
        }
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

    private func registerStringBuilderMemberFunction(
        named name: String,
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        parameters: [(name: String, type: TypeID, hasDefault: Bool, isVararg: Bool)],
        returnType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner,
        extraFlags: SymbolFlags = []
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let functionName = interner.intern(name)
        let functionFQName = ownerInfo.fqName + [functionName]
        let expectedParameterTypes = parameters.map(\.type)
        let expectedParameterVarargs = parameters.map(\.isVararg)
        if symbols.lookupAll(fqName: functionFQName).contains(where: { symbolID in
            guard let existingSignature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return existingSignature.receiverType == ownerType
                && existingSignature.parameterTypes == parameters.map(\.type)
                && existingSignature.valueParameterIsVararg == parameters.map(\.isVararg)
        }) {
            return
        }

        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: SymbolFlags.synthetic.union(extraFlags)
        )
        symbols.setParentSymbol(ownerSymbol, for: functionSymbol)

        var parameterTypes: [TypeID] = []
        var parameterSymbols: [SymbolID] = []
        var parameterDefaults: [Bool] = []
        var parameterVarargs: [Bool] = []

        for parameter in parameters {
            let parameterName = interner.intern(parameter.name)
            let parameterSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: functionFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(functionSymbol, for: parameterSymbol)
            parameterTypes.append(parameter.type)
            parameterSymbols.append(parameterSymbol)
            parameterDefaults.append(parameter.hasDefault)
            parameterVarargs.append(parameter.isVararg)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: ownerType,
                parameterTypes: parameterTypes,
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: parameterSymbols,
                valueParameterHasDefaultValues: parameterDefaults,
                valueParameterIsVararg: parameterVarargs,
                typeParameterSymbols: []
            ),
            for: functionSymbol
        )
    }

    private func registerStringBuilderMemberProperty(
        named name: String,
        ownerSymbol: SymbolID,
        returnType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let propertyName = interner.intern(name)
        let propertyFQName = ownerInfo.fqName + [propertyName]
        if let existing = symbols.lookupAll(fqName: propertyFQName).first(where: { symbolID in
            symbols.symbol(symbolID)?.kind == .property
        }) {
            symbols.setPropertyType(returnType, for: existing)
            if name == "length" {
                symbols.setExternalLinkName("kk_string_builder_length_prop", for: existing)
            }
            return
        }

        let propertySymbol = symbols.define(
            kind: .property,
            name: propertyName,
            fqName: propertyFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: propertySymbol)
        symbols.setPropertyType(returnType, for: propertySymbol)
        if name == "length" {
            symbols.setExternalLinkName("kk_string_builder_length_prop", for: propertySymbol)
        }
    }
}
