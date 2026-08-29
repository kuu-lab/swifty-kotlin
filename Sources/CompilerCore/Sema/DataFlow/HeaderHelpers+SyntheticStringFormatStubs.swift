extension DataFlowSemaPhase {
    func registerSyntheticStringFormatStubs(context: SyntheticStringStubContext, localeType: TypeID,
        stringClassSymbol: SymbolID, nullableStringType: TypeID) {
        let (symbols, types, interner, kotlinTextPkg) = (context.symbols, context.types, context.interner, context.kotlinTextPkg); let (kotlinRootPkg, stringType) = (context.kotlinRootPkg, context.stringType)
        // --- STDLIB-I18N-COMMON-001: companion (static) method, not an extension ---
        let stringCompanionFQName = ensureStringCompanionSymbol(
            ownerSymbol: stringClassSymbol,
            symbols: symbols,
            interner: interner
        )
        registerStringCompanionMethod(
            named: "format",
            externalLinkName: "__kk_string_format_flat",
            returnType: stringType,
            parameters: [
                (name: "format", type: stringType),
                (name: "args", type: types.nullableAnyType),
            ],
            isVararg: [false, true],
            companionFQName: stringCompanionFQName,
            symbols: symbols,
            interner: interner
        )
        registerStringCompanionMethod(
            named: "format",
            externalLinkName: "__kk_string_format_locale_flat",
            returnType: stringType,
            parameters: [
                (name: "locale", type: types.makeNullable(localeType)),
                (name: "format", type: stringType),
                (name: "args", type: types.nullableAnyType),
            ],
            isVararg: [false, false, true],
            companionFQName: stringCompanionFQName,
            symbols: symbols,
            interner: interner
        )
        // --- STDLIB-TEXT-TYPE-004: String.Companion.CASE_INSENSITIVE_ORDER ---
        // BUG-154: registered as a companion (static) member of String, matching
        // real Kotlin's `String.Companion.CASE_INSENSITIVE_ORDER`. There is no
        // top-level `kotlin.text.CASE_INSENSITIVE_ORDER`, so a bare reference must
        // stay unresolved. Reads route through the object-member read path
        // (`loadGlobal`) backed by the object-parented synthetic external-property
        // global initializer, which calls `kk_string_case_insensitive_order()`
        // once at module init -- giving referential identity via a single global.
        let comparatorFQName = kotlinRootPkg + [interner.intern("Comparator")]
        if let comparatorSymbol = symbols.lookup(fqName: comparatorFQName) {
            let caseInsensitiveOrderType = types.make(.classType(ClassType(
                classSymbol: comparatorSymbol,
                args: [.invariant(stringType)],
                nullability: .nonNull
            )))
            registerSyntheticCompanionExternalProperty(
                named: "CASE_INSENSITIVE_ORDER",
                companionFQName: stringCompanionFQName,
                returnType: caseInsensitiveOrderType,
                externalLinkName: "kk_string_case_insensitive_order",
                symbols: symbols,
                interner: interner
            )
        }
        // --- STDLIB-I18N-COMMON-001: String.format instance extension method ---
        // Kotlin: "...".format(vararg args: Any?) -> String
        // Receiver is the format string; routes to __kk_string_format_flat.
        registerSyntheticStringExtensionFunction(
            named: "format",
            externalLinkName: "__kk_string_format_flat",
            receiverType: stringType,
            parameters: [
                ("args", types.nullableAnyType, false, true),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )
        // KSP-401: String?.orEmpty() is bundled Kotlin source.

        // KSP-413: CharSequence?.contentEquals is bundled Kotlin source
        // (Stdlib/kotlin/text/StringComparison.kt).

        // --- STDLIB-TEXT-FN-011: shares kk_string_concat with the `+` operator ---
        registerSyntheticStringExtensionFunction(
            named: "concat",
            externalLinkName: "kk_string_concat_flat",
            receiverType: stringType,
            parameters: [
                ("str", stringType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-TEXT-FN-043: String?.plus(other: Any?) ---
        // `operator fun String.plus(other: Any?): String` and the nullable-receiver
        // variant `operator fun String?.plus(other: Any?): String`. Both delegate to
        // kk_string_plus which converts receiver and argument via runtimeElementToString.
        // Primitive `other` values are boxed by the ABI lowering pass before the call,
        // so runtimeElementToString correctly renders Boolean/Char/Float/Double.
        registerSyntheticStringExtensionFunction(
            named: "plus",
            externalLinkName: "kk_string_plus",
            receiverType: stringType,
            parameters: [
                ("other", types.nullableAnyType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticStringExtensionFunction(
            named: "plus",
            externalLinkName: "kk_string_plus",
            receiverType: nullableStringType,
            parameters: [
                ("other", types.nullableAnyType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

    }
}
