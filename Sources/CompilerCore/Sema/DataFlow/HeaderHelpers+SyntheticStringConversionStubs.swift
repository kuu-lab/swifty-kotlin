extension DataFlowSemaPhase {
    func registerSyntheticStringConversionStubs(context: SyntheticStringStubContext) -> TypeID {
        let (symbols, types, interner, kotlinTextPkg) = (context.symbols, context.types, context.interner, context.kotlinTextPkg); let (stringType, charSequenceType, boolType, intType) = (context.stringType, context.charSequenceType, context.boolType, context.intType)
        // --- STDLIB-TEXT-TYPE-004: String.CASE_INSENSITIVE_ORDER comparator ---
        // BUG-154: In real Kotlin this is `String.Companion.CASE_INSENSITIVE_ORDER`
        // (accessed as `String.CASE_INSENSITIVE_ORDER`), *not* a top-level
        // `kotlin.text.CASE_INSENSITIVE_ORDER`. It is registered as a member of
        // String's companion object below (see STDLIB-TEXT-TYPE-004 companion
        // block, after `stringClassSymbol` is established).
        // KSP-724: `String.length` is provided by bundled Kotlin source
        // (`kotlin/String.kt`) and `CharSequence.length` is provided by the
        // bundled `kotlin/CharSequence.kt` interface; synthetic extension stubs
        // for `length` are no longer needed.
        // lowercase() — migrated to BundledStdlib (MIGRATION-TEXT-005)
        // uppercase() — migrated to BundledStdlib (MIGRATION-TEXT-005)
        // --- STDLIB-TEXT-FN-010: CharSequence.codePointCount ---
        //
        // Kotlin/JVM defines the range in UTF-16 code units. KSwiftK's general
        // String indexing helpers are scalar-oriented, so this family is backed
        // by dedicated runtime entries.
        registerSyntheticStringExtensionFunction(
            named: "codePointCount",
            externalLinkName: "__kk_string_codePointCount",
            receiverType: charSequenceType,
            parameters: [],
            returnType: intType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticStringExtensionFunction(
            named: "codePointCount",
            externalLinkName: "__kk_string_codePointCount_from",
            receiverType: charSequenceType,
            parameters: [
                ("startIndex", intType, false, false),
            ],
            returnType: intType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticStringExtensionFunction(
            named: "codePointCount",
            externalLinkName: "__kk_string_codePointCount_range",
            receiverType: charSequenceType,
            parameters: [
                ("startIndex", intType, true, false),
                ("endIndex", intType, false, false),
            ],
            returnType: intType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )
        // capitalize() — migrated to BundledStdlib (MIGRATION-TEXT-005)
        let javaUtilPkg = ensurePackage(
            path: ["java", "util"],
            symbols: symbols,
            interner: interner
        )
        let javaUtilPkgSymbol = symbols.lookup(fqName: javaUtilPkg)
        let localeSymbol = ensureClassSymbol(
            named: "Locale",
            in: javaUtilPkg,
            symbols: symbols,
            interner: interner
        )
        if let javaUtilPkgSymbol {
            symbols.setParentSymbol(javaUtilPkgSymbol, for: localeSymbol)
        }
        let localeType = types.make(.classType(ClassType(
            classSymbol: localeSymbol, args: [], nullability: .nonNull
        )))
        symbols.setPropertyType(localeType, for: localeSymbol)
        registerSyntheticLocaleConstructor(
            ownerSymbol: localeSymbol,
            ownerType: localeType,
            parameters: [("identifier", stringType)],
            externalLinkName: "kk_locale_new_flat",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticLocaleConstructor(
            ownerSymbol: localeSymbol,
            ownerType: localeType,
            parameters: [("language", stringType), ("country", stringType)],
            externalLinkName: "kk_locale_new_language_country_flat",
            symbols: symbols,
            interner: interner
        )

        // MIGRATION-TEXT-005: private primitives called from bundled Kotlin wrappers.
        registerSyntheticStringExtensionFunction(
            named: "__kk_lowercase_locale",
            externalLinkName: "__kk_lowercase_locale",
            receiverType: stringType,
            parameters: [
                ("locale", localeType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "__kk_uppercase_locale",
            externalLinkName: "__kk_uppercase_locale",
            receiverType: stringType,
            parameters: [
                ("locale", localeType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // KSP-413: locale-aware compareTo stays a runtime bridge (ICU/Foundation
        // collation), demoted to `__kk_` so only bundled stdlib source
        // (StringComparison.kt) reaches it.
        registerSyntheticStringExtensionFunction(
            named: "__kk_string_compareTo_locale",
            externalLinkName: "__kk_string_compareTo_locale",
            receiverType: stringType,
            parameters: [
                ("other", stringType, false, false),
                ("locale", localeType, false, false),
            ],
            returnType: intType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        let normalizationFormSymbol = ensureClassSymbol(
            named: "NormalizationForm",
            in: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )
        let normalizationFormType = types.make(.classType(ClassType(
            classSymbol: normalizationFormSymbol, args: [], nullability: .nonNull
        )))
        symbols.setPropertyType(normalizationFormType, for: normalizationFormSymbol)

        let normalizationFormsSymbol = ensureSyntheticObjectSymbol(
            named: "NormalizationForms",
            in: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )
        let normalizationFormsType = types.make(.classType(ClassType(
            classSymbol: normalizationFormsSymbol, args: [], nullability: .nonNull
        )))
        symbols.setPropertyType(normalizationFormsType, for: normalizationFormsSymbol)

        for formName in ["NFC", "NFD", "NFKC", "NFKD"] {
            registerSyntheticObjectProperty(
                ownerSymbol: normalizationFormsSymbol,
                ownerType: normalizationFormsType,
                name: formName,
                propertyType: normalizationFormType,
                symbols: symbols,
                interner: interner
            )
        }

        registerSyntheticStringExtensionFunction(
            named: "normalize",
            externalLinkName: "__kk_string_normalize_flat",
            receiverType: stringType,
            parameters: [
                ("form", normalizationFormType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "isNormalized",
            externalLinkName: "__kk_string_isNormalized_flat",
            receiverType: stringType,
            parameters: [
                ("form", normalizationFormType, false, false),
            ],
            returnType: boolType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        return localeType
    }

    func registerSyntheticObjectProperty(
        ownerSymbol: SymbolID,
        ownerType _: TypeID,
        name: String,
        propertyType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let propertyName = interner.intern(name)
        let propertyFQName = ownerInfo.fqName + [propertyName]
        guard symbols.lookup(fqName: propertyFQName) == nil else {
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
        symbols.setPropertyType(propertyType, for: propertySymbol)
    }

    func registerSyntheticLocaleConstructor(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        parameters: [(name: String, type: TypeID)],
        externalLinkName: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let initName = interner.intern("<init>")
        let ctorFQName = ownerInfo.fqName + [initName]
        let hasMatchingConstructor = symbols.lookupAll(fqName: ctorFQName).contains { symbolID in
            guard let symbol = symbols.symbol(symbolID),
                  symbol.kind == .constructor,
                  let signature = symbols.functionSignature(for: symbolID)
            else {
                return false
            }
            return signature.parameterTypes == parameters.map(\.type)
        }
        guard !hasMatchingConstructor else {
            return
        }

        let ctorSymbol = symbols.define(
            kind: .constructor,
            name: initName,
            fqName: ctorFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: ctorSymbol)
        symbols.setExternalLinkName(externalLinkName, for: ctorSymbol)

        var valueParameterSymbols: [SymbolID] = []
        for parameter in parameters {
            let parameterName = interner.intern(parameter.name)
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: ctorFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(ctorSymbol, for: paramSymbol)
            valueParameterSymbols.append(paramSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: parameters.map(\.type),
                returnType: ownerType,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count)
            ),
            for: ctorSymbol
        )
    }
}
