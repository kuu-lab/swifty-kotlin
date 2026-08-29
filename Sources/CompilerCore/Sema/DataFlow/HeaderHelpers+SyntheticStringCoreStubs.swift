extension DataFlowSemaPhase {
    func registerSyntheticStringCoreStubs(context: SyntheticStringStubContext) {
        let (symbols, interner, kotlinTextPkg, stringType) = (context.symbols, context.interner, context.kotlinTextPkg, context.stringType); let (intType, longType, charType) = (context.intType, context.longType, context.charType)
        // KSP-404: startsWith/endsWith are bundled Kotlin source (StringPrefixSuffix.kt).
        // KSP-408: contains(String)/contains(String, ignoreCase) are bundled Kotlin
        // source (StringIndexOf.kt). The Regex overload below is unaffected.
        // String.toInt(radix: Int) (STDLIB-152)
        // SPEC-NUM-0007: String.toUByteOrNull() / toUShortOrNull() / toUIntOrNull() / toULongOrNull() — no-arg versions
        // KSP-406: subSequence/substring are bundled Kotlin source
        // (Stdlib/kotlin/text/StringSubstringSlice.kt).
        // STDLIB-420: String.toLong / toLongOrNull / toFloat / toFloatOrNull
        // Int.toString(radix: Int) / Long.toString(radix: Int) (STDLIB-152)
        registerSyntheticStringExtensionFunction(
            named: "toString",
            externalLinkName: "kk_int_toString_radix",
            receiverType: intType,
            parameters: [
                ("radix", intType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticStringExtensionFunction(
            named: "toString",
            externalLinkName: "kk_int_toString_radix",
            receiverType: longType,
            parameters: [
                ("radix", intType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )
        // KSP-408: indexOf/lastIndexOf/indexOfAny/lastIndexOfAny/findAnyOf/findLastAnyOf
        // (String, Char, CharArray and Collection<String> overloads, with startIndex /
        // ignoreCase variants) are bundled Kotlin source (StringIndexOf.kt).
        // KSP-405: take/takeLast/drop/dropLast are bundled Kotlin source
        // (StringTakeDrop.kt).
        // KSP-404: removePrefix/removeSuffix/removeSurrounding are bundled Kotlin
        // source (StringPrefixSuffix.kt).
        // KSP-407: substringBefore/After/BeforeLast/AfterLast and
        // replaceBefore/After/BeforeLast/AfterLast are bundled Kotlin source
        // (StringSearchReplace.kt).

        // KSP-487: String.matches / contains / toRegex are bundled Kotlin source (StringSearchReplace.kt).

        // --- STDLIB-140: String.get(Int): Char ---

        registerSyntheticStringExtensionFunction(
            named: "get",
            externalLinkName: "kk_string_get_flat",
            receiverType: stringType,
            parameters: [
                ("index", intType, false, false),
            ],
            returnType: charType,
            flags: [.synthetic, .operatorFunction],
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )
        // KSP-724: `CharSequence.get` is provided by bundled Kotlin source
        // (`kotlin/text/StringSubstringSlice.kt`); the synthetic extension stub
        // is no longer needed.

        // BUG-152: `subSequence` on a value statically typed as `CharSequence` is
        // provided by bundled Kotlin source (StringSubstringSlice.kt).

        // --- STDLIB-141: String.compareTo ---

        registerSyntheticStringExtensionFunction(
            named: "compareTo",
            externalLinkName: "kk_string_compareTo_member",
            receiverType: stringType,
            parameters: [
                ("other", stringType, false, false),
            ],
            returnType: intType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // KSP-413: compareTo(other, ignoreCase) is bundled Kotlin source
        // (Stdlib/kotlin/text/StringComparison.kt).

        // KSP-401: isEmpty/isBlank/ifEmpty/ifBlank are bundled Kotlin source.

        // --- STDLIB-TEXT-FN-026: String.intern ---
        registerSyntheticStringExtensionFunction(
            named: "intern",
            externalLinkName: "kk_string_intern",
            receiverType: stringType,
            parameters: [],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

    }
}
