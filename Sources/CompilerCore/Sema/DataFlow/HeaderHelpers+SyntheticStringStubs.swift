import Foundation

extension DataFlowSemaPhase {
    func registerSyntheticStringStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinTextPkg = SyntheticStringStubRegistration.ensureKotlinTextPackage(symbols: symbols, interner: interner)
        let kotlinRootPkg = ensurePackage(path: ["kotlin"], symbols: symbols, interner: interner)
        let stringType = types.stringType
        let charSequenceSymbol = ensureInterfaceSymbol(
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
        let appendableSymbol = ensureInterfaceSymbol(
            named: "Appendable",
            in: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )
        let appendableType = types.make(.classType(ClassType(
            classSymbol: appendableSymbol, args: [], nullability: .nonNull
        )))
        if let kotlinTextPkgSymbol = symbols.lookup(fqName: kotlinTextPkg) {
            symbols.setParentSymbol(kotlinTextPkgSymbol, for: appendableSymbol)
        }
        let boolType = types.make(.primitive(.boolean, .nonNull))
        let nullableBoolType = types.make(.primitive(.boolean, .nullable))
        let intType = types.intType
        let longType = types.make(.primitive(.long, .nonNull))
        let charType = types.make(.primitive(.char, .nonNull))
        let nullableIntType = types.make(.primitive(.int, .nullable))
        let nullableDoubleType = types.make(.primitive(.double, .nullable))
        let nullableLongType = types.make(.primitive(.long, .nullable))
        let nullableFloatType = types.make(.primitive(.float, .nullable))
        let nullableCharType = types.make(.primitive(.char, .nullable))
        let floatType = types.floatType
        let doubleType = types.doubleType
        let stringProducerType = types.make(.functionType(FunctionType(
            params: [],
            returnType: stringType,
            isSuspend: false,
            nullability: .nonNull
        )))
        let listStringType = SyntheticStringStubRegistration.makeListOfStringType(symbols: symbols, types: types, interner: interner)
        let collectionStringType = SyntheticStringStubRegistration.makeCollectionType(
            symbols: symbols,
            types: types,
            interner: interner,
            elementType: stringType
        )
        let pairIntStringType: TypeID
        if let pairSymbol = symbols.lookup(fqName: kotlinRootPkg + [interner.intern("Pair")]) {
            pairIntStringType = types.make(.classType(ClassType(
                classSymbol: pairSymbol,
                args: [.out(intType), .out(stringType)],
                nullability: .nonNull
            )))
        } else {
            pairIntStringType = types.anyType
        }
        let nullablePairIntStringType = types.makeNullable(pairIntStringType)
        let listCharType = SyntheticStringStubRegistration.makeListType(
            symbols: symbols,
            types: types,
            interner: interner,
            elementType: charType
        )
        let charArrayType = SyntheticStringStubRegistration.makeNominalType(
            symbols: symbols,
            types: types,
            fqName: [interner.intern("kotlin"), interner.intern("CharArray")]
        )
        let nullableCharSequenceType = types.makeNullable(charSequenceType)

        // --- STDLIB-TEXT-TYPE-001: kotlin.text.Appendable interface surface ---
        SyntheticStringStubRegistration.registerAppendableMemberFunction(
            named: "append",
            ownerSymbol: appendableSymbol,
            ownerType: appendableType,
            parameters: [("value", charType, false, false)],
            returnType: appendableType,
            symbols: symbols,
            interner: interner
        )
        SyntheticStringStubRegistration.registerAppendableMemberFunction(
            named: "append",
            ownerSymbol: appendableSymbol,
            ownerType: appendableType,
            parameters: [("value", nullableCharSequenceType, false, false)],
            returnType: appendableType,
            symbols: symbols,
            interner: interner
        )
        SyntheticStringStubRegistration.registerAppendableMemberFunction(
            named: "append",
            ownerSymbol: appendableSymbol,
            ownerType: appendableType,
            parameters: [
                ("value", nullableCharSequenceType, false, false),
                ("startIndex", intType, false, false),
                ("endIndex", intType, false, false),
            ],
            returnType: appendableType,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-TEXT-TYPE-003: kotlin.text.Typography object surface ---
        let typographySymbol = ensureSyntheticObjectSymbol(
            named: "Typography",
            in: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )
        let typographyType = types.make(.classType(ClassType(
            classSymbol: typographySymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(typographyType, for: typographySymbol)
        if let kotlinTextPkgSymbol = symbols.lookup(fqName: kotlinTextPkg) {
            symbols.setParentSymbol(kotlinTextPkgSymbol, for: typographySymbol)
        }
        for (name, scalar) in SyntheticStringStubRegistration.typographyCharConstants {
            SyntheticStringStubRegistration.registerTypographyCharConstant(
                ownerSymbol: typographySymbol,
                name: name,
                scalar: scalar,
                charType: charType,
                symbols: symbols,
                interner: interner
            )
        }

        // --- STDLIB-TEXT-TYPE-004: kotlin.text.CASE_INSENSITIVE_ORDER comparator ---
        let comparatorFQName = kotlinRootPkg + [interner.intern("Comparator")]
        if let comparatorSymbol = symbols.lookup(fqName: comparatorFQName) {
            let caseInsensitiveOrderType = types.make(.classType(ClassType(
                classSymbol: comparatorSymbol,
                args: [.invariant(stringType)],
                nullability: .nonNull
            )))
            SyntheticStringStubRegistration.registerSyntheticStringTopLevelProperty(
                named: "CASE_INSENSITIVE_ORDER",
                packageFQName: kotlinTextPkg,
                returnType: caseInsensitiveOrderType,
                externalLinkName: "kk_string_case_insensitive_order",
                symbols: symbols,
                interner: interner
            )
        }

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "length",
            externalLinkName: "kk_string_length",
            receiverType: stringType,
            parameters: [],
            returnType: intType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "trim",
            externalLinkName: "kk_string_trim",
            receiverType: stringType,
            parameters: [],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "lowercase",
            externalLinkName: "kk_string_lowercase",
            receiverType: stringType,
            parameters: [],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "uppercase",
            externalLinkName: "kk_string_uppercase",
            receiverType: stringType,
            parameters: [],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

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

        SyntheticStringStubRegistration.registerSyntheticLocaleConstructor(
            ownerSymbol: localeSymbol,
            ownerType: localeType,
            parameters: [("identifier", stringType)],
            externalLinkName: "kk_locale_new",
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "lowercase",
            externalLinkName: "kk_string_lowercase_locale",
            receiverType: stringType,
            parameters: [
                ("locale", localeType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "uppercase",
            externalLinkName: "kk_string_uppercase_locale",
            receiverType: stringType,
            parameters: [
                ("locale", localeType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "compareTo",
            externalLinkName: "kk_string_compareTo_locale",
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
            SyntheticStringStubRegistration.registerSyntheticObjectProperty(
                ownerSymbol: normalizationFormsSymbol,
                ownerType: normalizationFormsType,
                name: formName,
                propertyType: normalizationFormType,
                symbols: symbols,
                interner: interner
            )
        }

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "normalize",
            externalLinkName: "kk_string_normalize",
            receiverType: stringType,
            parameters: [
                ("form", normalizationFormType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "isNormalized",
            externalLinkName: "kk_string_isNormalized",
            receiverType: stringType,
            parameters: [
                ("form", normalizationFormType, false, false),
            ],
            returnType: boolType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "split",
            externalLinkName: "kk_string_split",
            receiverType: stringType,
            parameters: [
                ("delimiters", stringType, false, false),
            ],
            returnType: listStringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-TEXT-EDGE-001: split with limit / ignoreCase ---
        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "split",
            externalLinkName: "kk_string_split_limit",
            receiverType: stringType,
            parameters: [
                ("delimiters", stringType, false, false),
                ("limit", intType, false, false),
            ],
            returnType: listStringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "split",
            externalLinkName: "kk_string_split_limit",
            receiverType: stringType,
            parameters: [
                ("delimiters", stringType, false, false),
                ("ignoreCase", boolType, false, false),
            ],
            returnType: listStringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "split",
            externalLinkName: "kk_string_split_limit",
            receiverType: stringType,
            parameters: [
                ("delimiters", stringType, false, false),
                ("ignoreCase", boolType, false, false),
                ("limit", intType, false, false),
            ],
            returnType: listStringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "replace",
            externalLinkName: "kk_string_replace",
            receiverType: stringType,
            parameters: [
                ("oldValue", stringType, false, false),
                ("newValue", stringType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "startsWith",
            externalLinkName: "kk_string_startsWith",
            receiverType: stringType,
            parameters: [
                ("prefix", stringType, false, false),
            ],
            returnType: boolType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "endsWith",
            externalLinkName: "kk_string_endsWith",
            receiverType: stringType,
            parameters: [
                ("suffix", stringType, false, false),
            ],
            returnType: boolType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "contains",
            externalLinkName: "kk_string_contains_str",
            receiverType: stringType,
            parameters: [
                ("other", stringType, false, false),
            ],
            returnType: boolType,
            flags: [.synthetic, .operatorFunction],
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "toInt",
            externalLinkName: "kk_string_toInt",
            receiverType: stringType,
            parameters: [],
            returnType: intType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // String.toInt(radix: Int) (STDLIB-152)
        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "toInt",
            externalLinkName: "kk_string_toInt_radix",
            receiverType: stringType,
            parameters: [
                ("radix", intType, false, false),
            ],
            returnType: intType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "toIntOrNull",
            externalLinkName: "kk_string_toIntOrNull",
            receiverType: stringType,
            parameters: [],
            returnType: nullableIntType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "toIntOrNull",
            externalLinkName: "kk_string_toIntOrNull_radix",
            receiverType: stringType,
            parameters: [
                ("radix", intType, false, false),
            ],
            returnType: nullableIntType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "toUByteOrNull",
            externalLinkName: "kk_string_toUByteOrNull_radix",
            receiverType: stringType,
            parameters: [
                ("radix", intType, false, false),
            ],
            returnType: types.makeNullable(types.ubyteType),
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "toUShortOrNull",
            externalLinkName: "kk_string_toUShortOrNull_radix",
            receiverType: stringType,
            parameters: [
                ("radix", intType, false, false),
            ],
            returnType: types.makeNullable(types.ushortType),
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "toUIntOrNull",
            externalLinkName: "kk_string_toUIntOrNull_radix",
            receiverType: stringType,
            parameters: [
                ("radix", intType, false, false),
            ],
            returnType: types.makeNullable(types.uintType),
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "toULongOrNull",
            externalLinkName: "kk_string_toULongOrNull_radix",
            receiverType: stringType,
            parameters: [
                ("radix", intType, false, false),
            ],
            returnType: types.makeNullable(types.ulongType),
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "toDouble",
            externalLinkName: "kk_string_toDouble",
            receiverType: stringType,
            parameters: [],
            returnType: doubleType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "toDoubleOrNull",
            externalLinkName: "kk_string_toDoubleOrNull",
            receiverType: stringType,
            parameters: [],
            returnType: nullableDoubleType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // STDLIB-420: String.toLong / toLongOrNull / toFloat / toFloatOrNull
        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "toLong",
            externalLinkName: "kk_string_toLong",
            receiverType: stringType,
            parameters: [],
            returnType: longType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "toLongOrNull",
            externalLinkName: "kk_string_toLongOrNull",
            receiverType: stringType,
            parameters: [],
            returnType: nullableLongType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "toFloat",
            externalLinkName: "kk_string_toFloat",
            receiverType: stringType,
            parameters: [],
            returnType: floatType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "toFloatOrNull",
            externalLinkName: "kk_string_toFloatOrNull",
            receiverType: stringType,
            parameters: [],
            returnType: nullableFloatType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "substring",
            externalLinkName: "kk_string_substring",
            receiverType: stringType,
            parameters: [
                ("startIndex", intType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "subSequence",
            externalLinkName: "kk_string_subSequence",
            receiverType: stringType,
            parameters: [
                ("startIndex", intType, false, false),
                ("endIndex", intType, false, false),
            ],
            returnType: stringType,
            annotations: [
                MetadataAnnotationRecord(
                    annotationFQName: "kotlin.Deprecated",
                    arguments: [
                        "message = \"Use substring(startIndex, endIndex) instead.\"",
                        "replaceWith = ReplaceWith(\"substring(startIndex, endIndex)\")",
                    ]
                ),
            ],
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "substring",
            externalLinkName: "kk_string_substring",
            receiverType: stringType,
            parameters: [
                ("startIndex", intType, false, false),
                ("endIndex", intType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "format",
            externalLinkName: "kk_string_format",
            receiverType: stringType,
            parameters: [
                ("args", types.nullableAnyType, false, true),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // Int.toString(radix: Int) / Long.toString(radix: Int) (STDLIB-152)
        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
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
        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
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

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "trimIndent",
            externalLinkName: "kk_string_trimIndent",
            receiverType: stringType,
            parameters: [],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "trimMargin",
            externalLinkName: "kk_string_trimMargin_default",
            receiverType: stringType,
            parameters: [],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "trimMargin",
            externalLinkName: "kk_string_trimMargin",
            receiverType: stringType,
            parameters: [
                ("marginPrefix", stringType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "replaceIndentByMargin",
            externalLinkName: "kk_string_replaceIndentByMargin",
            receiverType: stringType,
            parameters: [
                ("newIndent", stringType, true, false),
                ("marginPrefix", stringType, true, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "indexOf",
            externalLinkName: "kk_string_indexOf",
            receiverType: stringType,
            parameters: [
                ("other", stringType, false, false),
            ],
            returnType: intType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "lastIndexOf",
            externalLinkName: "kk_string_lastIndexOf",
            receiverType: stringType,
            parameters: [
                ("other", stringType, false, false),
            ],
            returnType: intType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "indexOf",
            externalLinkName: "kk_string_indexOf_from",
            receiverType: stringType,
            parameters: [
                ("string", stringType, false, false),
                ("startIndex", intType, false, false),
            ],
            returnType: intType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-TEXT-EDGE-003: indexOf / lastIndexOf with ignoreCase ---

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "indexOf",
            externalLinkName: "kk_string_indexOf_ignoreCase",
            receiverType: stringType,
            parameters: [
                ("string", stringType, false, false),
                ("startIndex", intType, false, false),
                ("ignoreCase", boolType, false, false),
            ],
            returnType: intType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-TEXT-SEARCH-001: CharSequence.indexOfAny(chars, startIndex, ignoreCase) ---

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "indexOfAny",
            externalLinkName: "kk_string_indexOfAny_chars",
            receiverType: charSequenceType,
            parameters: [
                ("chars", charArrayType, false, false),
                ("startIndex", intType, false, false),
                ("ignoreCase", boolType, false, false),
            ],
            returnType: intType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-TEXT-SEARCH-002: CharSequence.indexOfAny(strings, startIndex, ignoreCase) ---

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "indexOfAny",
            externalLinkName: "kk_string_indexOfAny_strings",
            receiverType: charSequenceType,
            parameters: [
                ("strings", collectionStringType, false, false),
                ("startIndex", intType, false, false),
                ("ignoreCase", boolType, false, false),
            ],
            returnType: intType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-TEXT-SEARCH-003: CharSequence.lastIndexOfAny(chars, startIndex, ignoreCase) ---

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "lastIndexOfAny",
            externalLinkName: "kk_string_lastIndexOfAny_chars",
            receiverType: charSequenceType,
            parameters: [
                ("chars", charArrayType, false, false),
                ("startIndex", intType, false, false),
                ("ignoreCase", boolType, false, false),
            ],
            returnType: intType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-TEXT-SEARCH-004: CharSequence.lastIndexOfAny(strings, startIndex, ignoreCase) ---

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "lastIndexOfAny",
            externalLinkName: "kk_string_lastIndexOfAny_strings",
            receiverType: charSequenceType,
            parameters: [
                ("strings", collectionStringType, false, false),
                ("startIndex", intType, false, false),
                ("ignoreCase", boolType, false, false),
            ],
            returnType: intType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-TEXT-SEARCH-005: CharSequence.findAnyOf(strings, startIndex, ignoreCase) ---

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "findAnyOf",
            externalLinkName: "kk_string_findAnyOf",
            receiverType: charSequenceType,
            parameters: [
                ("strings", collectionStringType, false, false),
                ("startIndex", intType, false, false),
                ("ignoreCase", boolType, false, false),
            ],
            returnType: nullablePairIntStringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-TEXT-SEARCH-006: CharSequence.findLastAnyOf(strings, startIndex, ignoreCase) ---

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "findLastAnyOf",
            externalLinkName: "kk_string_findLastAnyOf",
            receiverType: charSequenceType,
            parameters: [
                ("strings", collectionStringType, false, false),
                ("startIndex", intType, false, false),
                ("ignoreCase", boolType, false, false),
            ],
            returnType: nullablePairIntStringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "lastIndexOf",
            externalLinkName: "kk_string_lastIndexOf_ignoreCase",
            receiverType: stringType,
            parameters: [
                ("string", stringType, false, false),
                ("startIndex", intType, false, false),
                ("ignoreCase", boolType, false, false),
            ],
            returnType: intType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "repeat",
            externalLinkName: "kk_string_repeat",
            receiverType: stringType,
            parameters: [
                ("count", intType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "reversed",
            externalLinkName: "kk_string_reversed",
            receiverType: stringType,
            parameters: [],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "toList",
            externalLinkName: "kk_string_toList",
            receiverType: stringType,
            parameters: [],
            returnType: listCharType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "toCharArray",
            externalLinkName: "kk_string_toCharArray",
            receiverType: stringType,
            parameters: [],
            returnType: charArrayType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // STDLIB-317: String.asIterable() — returns lazy Iterable<Char>
        let iterableCharType = SyntheticStringStubRegistration.makeIterableType(
            symbols: symbols,
            types: types,
            interner: interner,
            elementType: charType
        )
        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "asIterable",
            externalLinkName: "kk_string_asIterable",
            receiverType: stringType,
            parameters: [],
            returnType: iterableCharType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "padStart",
            externalLinkName: "kk_string_padStart_default",
            receiverType: stringType,
            parameters: [
                ("length", intType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "padStart",
            externalLinkName: "kk_string_padStart",
            receiverType: stringType,
            parameters: [
                ("length", intType, false, false),
                ("padChar", charType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "padEnd",
            externalLinkName: "kk_string_padEnd_default",
            receiverType: stringType,
            parameters: [
                ("length", intType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "padEnd",
            externalLinkName: "kk_string_padEnd",
            receiverType: stringType,
            parameters: [
                ("length", intType, false, false),
                ("padChar", charType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "drop",
            externalLinkName: "kk_string_drop",
            receiverType: stringType,
            parameters: [
                ("n", intType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "take",
            externalLinkName: "kk_string_take",
            receiverType: stringType,
            parameters: [
                ("n", intType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "dropLast",
            externalLinkName: "kk_string_dropLast",
            receiverType: stringType,
            parameters: [
                ("n", intType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "takeLast",
            externalLinkName: "kk_string_takeLast",
            receiverType: stringType,
            parameters: [
                ("n", intType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-185: removePrefix / removeSuffix / removeSurrounding ---

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "removePrefix",
            externalLinkName: "kk_string_removePrefix",
            receiverType: charSequenceType,
            parameters: [
                ("prefix", charSequenceType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "removeSuffix",
            externalLinkName: "kk_string_removeSuffix",
            receiverType: charSequenceType,
            parameters: [
                ("suffix", charSequenceType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "removeSurrounding",
            externalLinkName: "kk_string_removeSurrounding",
            receiverType: charSequenceType,
            parameters: [
                ("delimiter", charSequenceType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "removeSurrounding",
            externalLinkName: "kk_string_removeSurrounding_pair",
            receiverType: charSequenceType,
            parameters: [
                ("prefix", charSequenceType, false, false),
                ("suffix", charSequenceType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "removePrefix",
            externalLinkName: "kk_string_removePrefix",
            receiverType: stringType,
            parameters: [
                ("prefix", stringType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "removeSuffix",
            externalLinkName: "kk_string_removeSuffix",
            receiverType: stringType,
            parameters: [
                ("suffix", stringType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "removeSurrounding",
            externalLinkName: "kk_string_removeSurrounding",
            receiverType: stringType,
            parameters: [
                ("delimiter", stringType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "removeSurrounding",
            externalLinkName: "kk_string_removeSurrounding_pair",
            receiverType: stringType,
            parameters: [
                ("prefix", stringType, false, false),
                ("suffix", stringType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-186: substringBefore / substringAfter / substringBeforeLast / substringAfterLast ---

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "substringBefore",
            externalLinkName: "kk_string_substringBefore",
            receiverType: stringType,
            parameters: [
                ("delimiter", stringType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "substringAfter",
            externalLinkName: "kk_string_substringAfter",
            receiverType: stringType,
            parameters: [
                ("delimiter", stringType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "substringBeforeLast",
            externalLinkName: "kk_string_substringBeforeLast",
            receiverType: stringType,
            parameters: [
                ("delimiter", stringType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "substringAfterLast",
            externalLinkName: "kk_string_substringAfterLast",
            receiverType: stringType,
            parameters: [
                ("delimiter", stringType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-TEXT-REPLACE-001: String.replaceAfter(delimiter, replacement, missingDelimiterValue) ---

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "replaceAfter",
            externalLinkName: "kk_string_replaceAfter",
            receiverType: stringType,
            parameters: [
                ("delimiter", stringType, false, false),
                ("replacement", stringType, false, false),
                ("missingDelimiterValue", stringType, true, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "replaceAfter",
            externalLinkName: "kk_string_replaceAfter_char",
            receiverType: stringType,
            parameters: [
                ("delimiter", charType, false, false),
                ("replacement", stringType, false, false),
                ("missingDelimiterValue", stringType, true, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-TEXT-REPLACE-002: String.replaceAfterLast(delimiter, replacement, missingDelimiterValue) ---

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "replaceAfterLast",
            externalLinkName: "kk_string_replaceAfterLast",
            receiverType: stringType,
            parameters: [
                ("delimiter", stringType, false, false),
                ("replacement", stringType, false, false),
                ("missingDelimiterValue", stringType, true, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "replaceAfterLast",
            externalLinkName: "kk_string_replaceAfterLast_char",
            receiverType: stringType,
            parameters: [
                ("delimiter", charType, false, false),
                ("replacement", stringType, false, false),
                ("missingDelimiterValue", stringType, true, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-TEXT-REPLACE-003: String.replaceBefore(delimiter, replacement, missingDelimiterValue) ---

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "replaceBefore",
            externalLinkName: "kk_string_replaceBefore",
            receiverType: stringType,
            parameters: [
                ("delimiter", stringType, false, false),
                ("replacement", stringType, false, false),
                ("missingDelimiterValue", stringType, true, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "replaceBefore",
            externalLinkName: "kk_string_replaceBefore_char",
            receiverType: stringType,
            parameters: [
                ("delimiter", charType, false, false),
                ("replacement", stringType, false, false),
                ("missingDelimiterValue", stringType, true, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-TEXT-REPLACE-004: String.replaceBeforeLast(delimiter, replacement, missingDelimiterValue) ---

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "replaceBeforeLast",
            externalLinkName: "kk_string_replaceBeforeLast",
            receiverType: stringType,
            parameters: [
                ("delimiter", stringType, false, false),
                ("replacement", stringType, false, false),
                ("missingDelimiterValue", stringType, true, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "replaceBeforeLast",
            externalLinkName: "kk_string_replaceBeforeLast_char",
            receiverType: stringType,
            parameters: [
                ("delimiter", charType, false, false),
                ("replacement", stringType, false, false),
                ("missingDelimiterValue", stringType, true, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-100/102/103: Regex-related String extensions ---

        let regexSymbol = ensureClassSymbol(
            named: "Regex", in: kotlinTextPkg,
            symbols: symbols, interner: interner
        )
        let regexType = types.make(.classType(ClassType(
            classSymbol: regexSymbol, args: [], nullability: .nonNull
        )))

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "matches",
            externalLinkName: "kk_string_matches_regex",
            receiverType: stringType,
            parameters: [
                ("regex", regexType, false, false),
            ],
            returnType: boolType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "contains",
            externalLinkName: "kk_string_contains_regex",
            receiverType: stringType,
            parameters: [
                ("regex", regexType, false, false),
            ],
            returnType: boolType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "replace",
            externalLinkName: "kk_string_replace_regex",
            receiverType: stringType,
            parameters: [
                ("regex", regexType, false, false),
                ("replacement", stringType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "split",
            externalLinkName: "kk_string_split_regex",
            receiverType: stringType,
            parameters: [
                ("regex", regexType, false, false),
            ],
            returnType: listStringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "toRegex",
            externalLinkName: "kk_string_toRegex",
            receiverType: stringType,
            parameters: [],
            returnType: regexType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-140: String.get(Int): Char ---

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "get",
            externalLinkName: "kk_string_get",
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

        // --- STDLIB-141: String.compareTo ---

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
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

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "compareTo",
            externalLinkName: "kk_string_compareToIgnoreCase",
            receiverType: stringType,
            parameters: [
                ("other", stringType, false, false),
                ("ignoreCase", boolType, false, false),
            ],
            returnType: intType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-187: isEmpty / isNotEmpty / isBlank / isNotBlank ---

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "isEmpty",
            externalLinkName: "kk_string_isEmpty",
            receiverType: stringType,
            parameters: [],
            returnType: boolType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "isNotEmpty",
            externalLinkName: "kk_string_isNotEmpty",
            receiverType: stringType,
            parameters: [],
            returnType: boolType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "isBlank",
            externalLinkName: "kk_string_isBlank",
            receiverType: stringType,
            parameters: [],
            returnType: boolType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "isNotBlank",
            externalLinkName: "kk_string_isNotBlank",
            receiverType: stringType,
            parameters: [],
            returnType: boolType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-TEXT-EDGE-004: CharSequence.ifBlank(defaultValue) ---

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "ifBlank",
            externalLinkName: "kk_string_ifBlank",
            receiverType: charSequenceType,
            parameters: [
                ("defaultValue", stringProducerType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-TEXT-EDGE-005: CharSequence.ifEmpty(defaultValue) ---

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "ifEmpty",
            externalLinkName: "kk_string_ifEmpty",
            receiverType: charSequenceType,
            parameters: [
                ("defaultValue", stringProducerType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-190: first / last / single / firstOrNull / lastOrNull ---

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "first",
            externalLinkName: "kk_string_first",
            receiverType: stringType,
            parameters: [],
            returnType: charType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "last",
            externalLinkName: "kk_string_last",
            receiverType: stringType,
            parameters: [],
            returnType: charType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "single",
            externalLinkName: "kk_string_single",
            receiverType: stringType,
            parameters: [],
            returnType: charType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "firstOrNull",
            externalLinkName: "kk_string_firstOrNull",
            receiverType: stringType,
            parameters: [],
            returnType: nullableCharType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "lastOrNull",
            externalLinkName: "kk_string_lastOrNull",
            receiverType: stringType,
            parameters: [],
            returnType: nullableCharType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "singleOrNull",
            externalLinkName: "kk_string_singleOrNull",
            receiverType: stringType,
            parameters: [],
            returnType: nullableCharType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-140: String.getOrNull(Int): Char? ---

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "getOrNull",
            externalLinkName: "kk_string_getOrNull",
            receiverType: stringType,
            parameters: [
                ("index", intType, false, false),
            ],
            returnType: nullableCharType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-191: prependIndent / replaceIndent ---

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "prependIndent",
            externalLinkName: "kk_string_prependIndent_default",
            receiverType: stringType,
            parameters: [],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "prependIndent",
            externalLinkName: "kk_string_prependIndent",
            receiverType: stringType,
            parameters: [
                ("indent", stringType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "replaceIndent",
            externalLinkName: "kk_string_replaceIndent_default",
            receiverType: stringType,
            parameters: [],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "replaceIndent",
            externalLinkName: "kk_string_replaceIndent",
            receiverType: stringType,
            parameters: [
                ("newIndent", stringType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-192: equals(other, ignoreCase) ---

        let nullableStringType = types.make(.primitive(.string, .nullable))

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "equals",
            externalLinkName: "kk_string_equals",
            receiverType: stringType,
            parameters: [
                ("other", nullableStringType, false, false),
            ],
            returnType: boolType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "equals",
            externalLinkName: "kk_string_equalsIgnoreCase",
            receiverType: stringType,
            parameters: [
                ("other", nullableStringType, false, false),
                ("ignoreCase", boolType, false, false),
            ],
            returnType: boolType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-188: replaceFirst / replaceRange ---

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "replaceFirst",
            externalLinkName: "kk_string_replaceFirst",
            receiverType: stringType,
            parameters: [
                ("oldValue", stringType, false, false),
                ("newValue", stringType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "replaceRange",
            externalLinkName: "kk_string_replaceRange",
            receiverType: stringType,
            parameters: [
                ("range", intType, false, false),
                ("replacement", stringType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-TEXT-EDGE-008: removeRange ---

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "removeRange",
            externalLinkName: "kk_string_removeRange",
            receiverType: stringType,
            parameters: [
                ("startIndex", intType, false, false),
                ("endIndex", intType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "removeRange",
            externalLinkName: "kk_string_removeRange_range",
            receiverType: stringType,
            parameters: [
                ("range", intType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-189: String HOF (filter, map, count, any, all, none) ---
        let charToBoolType = types.make(.functionType(FunctionType(
            params: [charType],
            returnType: boolType,
            isSuspend: false,
            nullability: .nonNull
        )))

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "trim",
            externalLinkName: "kk_string_trim_predicate",
            receiverType: stringType,
            parameters: [("predicate", charToBoolType, false, false)],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        let charToCharType = types.make(.functionType(FunctionType(
            params: [charType],
            returnType: charType,
            isSuspend: false,
            nullability: .nonNull
        )))
        let charToAnyType = types.make(.functionType(FunctionType(
            params: [charType],
            returnType: types.anyType,
            isSuspend: false,
            nullability: .nonNull
        )))
        let charToIntType = types.make(.functionType(FunctionType(
            params: [charType],
            returnType: intType,
            isSuspend: false,
            nullability: .nonNull
        )))
        let charToDoubleType = types.make(.functionType(FunctionType(
            params: [charType],
            returnType: doubleType,
            isSuspend: false,
            nullability: .nonNull
        )))
        let charToNullableAnyType = types.make(.functionType(FunctionType(
            params: [charType],
            returnType: types.nullableAnyType,
            isSuspend: false,
            nullability: .nonNull
        )))
        let charCharToCharType = types.make(.functionType(FunctionType(
            params: [charType, charType],
            returnType: charType,
            isSuspend: false,
            nullability: .nonNull
        )))
        let intCharToAnyType = types.make(.functionType(FunctionType(
            params: [intType, charType],
            returnType: types.anyType,
            isSuspend: false,
            nullability: .nonNull
        )))
        let intCharToBoolType = types.make(.functionType(FunctionType(
            params: [intType, charType],
            returnType: boolType,
            isSuspend: false,
            nullability: .nonNull
        )))
        let intCharCharToCharType = types.make(.functionType(FunctionType(
            params: [intType, charType, charType],
            returnType: charType,
            isSuspend: false,
            nullability: .nonNull
        )))
        let listAnyType = SyntheticStringStubRegistration.makeListType(
            symbols: symbols,
            types: types,
            interner: interner,
            elementType: types.anyType
        )
        let sequenceStringType = SyntheticStringStubRegistration.makeSequenceType(
            symbols: symbols,
            types: types,
            interner: interner,
            elementType: stringType
        )
        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "filter",
            externalLinkName: "kk_string_filter",
            receiverType: stringType,
            parameters: [("predicate", charToBoolType, false, false)],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )
        // String.map returns List<R> in Kotlin; use (Char) -> Any transform
        // and Any return type to allow arbitrary mapping.
        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "map",
            externalLinkName: "kk_string_map",
            receiverType: stringType,
            parameters: [("transform", charToAnyType, false, false)],
            returnType: types.anyType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )
        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "count",
            externalLinkName: "kk_string_count",
            receiverType: stringType,
            parameters: [("predicate", charToBoolType, false, false)],
            returnType: intType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )
        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "any",
            externalLinkName: "kk_string_any",
            receiverType: stringType,
            parameters: [("predicate", charToBoolType, false, false)],
            returnType: boolType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )
        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "all",
            externalLinkName: "kk_string_all",
            receiverType: stringType,
            parameters: [("predicate", charToBoolType, false, false)],
            returnType: boolType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )
        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "none",
            externalLinkName: "kk_string_none",
            receiverType: stringType,
            parameters: [("predicate", charToBoolType, false, false)],
            returnType: boolType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )
        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "mapIndexed",
            externalLinkName: "kk_string_mapIndexed",
            receiverType: stringType,
            parameters: [("transform", intCharToAnyType, false, false)],
            returnType: listAnyType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )
        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "mapNotNull",
            externalLinkName: "kk_string_mapNotNull",
            receiverType: stringType,
            parameters: [("transform", charToNullableAnyType, false, false)],
            returnType: listAnyType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-TEXT-HOF-001: CharSequence.firstNotNullOf(transform) ---
        let firstNotNullOfFQName = kotlinTextPkg + [interner.intern("firstNotNullOf")]
        if !symbols.lookupAll(fqName: firstNotNullOfFQName).contains(where: { symID in
            guard let sig = symbols.functionSignature(for: symID) else {
                return false
            }
            return sig.receiverType == charSequenceType && sig.parameterTypes.count == 1
        }) {
            let rName = interner.intern("R")
            let rSymbol = symbols.define(
                kind: .typeParameter,
                name: rName,
                fqName: firstNotNullOfFQName + [rName],
                declSite: nil,
                visibility: .private,
                flags: []
            )
            let rType = types.make(.typeParam(TypeParamType(symbol: rSymbol, nullability: .nonNull)))
            let transformType = types.make(.functionType(FunctionType(
                params: [charType],
                returnType: types.makeNullable(rType),
                isSuspend: false,
                nullability: .nonNull
            )))
            let memberSymbol = symbols.define(
                kind: .function,
                name: interner.intern("firstNotNullOf"),
                fqName: firstNotNullOfFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .inlineFunction]
            )
            if let packageSymbol = symbols.lookup(fqName: kotlinTextPkg) {
                symbols.setParentSymbol(packageSymbol, for: memberSymbol)
            }
            symbols.setExternalLinkName("kk_string_firstNotNullOf", for: memberSymbol)

            let transformParamName = interner.intern("transform")
            let transformParamSymbol = symbols.define(
                kind: .valueParameter,
                name: transformParamName,
                fqName: firstNotNullOfFQName + [transformParamName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(memberSymbol, for: transformParamSymbol)

            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: charSequenceType,
                    parameterTypes: [transformType],
                    returnType: rType,
                    valueParameterSymbols: [transformParamSymbol],
                    valueParameterHasDefaultValues: [false],
                    valueParameterIsVararg: [false],
                    typeParameterSymbols: [rSymbol],
                    classTypeParameterCount: 0
                ),
                for: memberSymbol
            )
        }

        // --- STDLIB-TEXT-HOF-002: CharSequence.firstNotNullOfOrNull(transform) ---
        let firstNotNullOfOrNullFQName = kotlinTextPkg + [interner.intern("firstNotNullOfOrNull")]
        if !symbols.lookupAll(fqName: firstNotNullOfOrNullFQName).contains(where: { symID in
            guard let sig = symbols.functionSignature(for: symID) else {
                return false
            }
            return sig.receiverType == charSequenceType && sig.parameterTypes.count == 1
        }) {
            let rName = interner.intern("R")
            let rSymbol = symbols.define(
                kind: .typeParameter,
                name: rName,
                fqName: firstNotNullOfOrNullFQName + [rName],
                declSite: nil,
                visibility: .private,
                flags: []
            )
            let rType = types.make(.typeParam(TypeParamType(symbol: rSymbol, nullability: .nonNull)))
            let nullableRType = types.makeNullable(rType)
            let transformType = types.make(.functionType(FunctionType(
                params: [charType],
                returnType: nullableRType,
                isSuspend: false,
                nullability: .nonNull
            )))
            let memberSymbol = symbols.define(
                kind: .function,
                name: interner.intern("firstNotNullOfOrNull"),
                fqName: firstNotNullOfOrNullFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .inlineFunction]
            )
            if let packageSymbol = symbols.lookup(fqName: kotlinTextPkg) {
                symbols.setParentSymbol(packageSymbol, for: memberSymbol)
            }
            symbols.setExternalLinkName("kk_string_firstNotNullOfOrNull", for: memberSymbol)

            let transformParamName = interner.intern("transform")
            let transformParamSymbol = symbols.define(
                kind: .valueParameter,
                name: transformParamName,
                fqName: firstNotNullOfOrNullFQName + [transformParamName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(memberSymbol, for: transformParamSymbol)

            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: charSequenceType,
                    parameterTypes: [transformType],
                    returnType: nullableRType,
                    valueParameterSymbols: [transformParamSymbol],
                    valueParameterHasDefaultValues: [false],
                    valueParameterIsVararg: [false],
                    typeParameterSymbols: [rSymbol],
                    classTypeParameterCount: 0
                ),
                for: memberSymbol
            )
        }

        // --- STDLIB-TEXT-HOF-003: CharSequence.reduceRightIndexed(operation) ---
        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "reduceRightIndexed",
            externalLinkName: "kk_string_reduceRightIndexed",
            receiverType: charSequenceType,
            parameters: [("operation", intCharCharToCharType, false, false)],
            returnType: charType,
            flags: [.synthetic, .inlineFunction],
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-TEXT-HOF-004: CharSequence.reduceRightIndexedOrNull(operation) ---
        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "reduceRightIndexedOrNull",
            externalLinkName: "kk_string_reduceRightIndexedOrNull",
            receiverType: charSequenceType,
            parameters: [("operation", intCharCharToCharType, false, false)],
            returnType: nullableCharType,
            flags: [.synthetic, .inlineFunction],
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-TEXT-HOF-005: CharSequence.reduceRightOrNull(operation) ---
        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "reduceRightOrNull",
            externalLinkName: "kk_string_reduceRightOrNull",
            receiverType: charSequenceType,
            parameters: [("operation", charCharToCharType, false, false)],
            returnType: nullableCharType,
            flags: [.synthetic, .inlineFunction],
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-TEXT-HOF-006: CharSequence.sumBy(selector) deprecated surface ---
        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "sumBy",
            externalLinkName: "kk_string_sumBy",
            receiverType: charSequenceType,
            parameters: [("selector", charToIntType, false, false)],
            returnType: intType,
            annotations: [
                MetadataAnnotationRecord(
                    annotationFQName: "kotlin.Deprecated",
                    arguments: [
                        "message = \"Use sumOf instead.\"",
                        "replaceWith = ReplaceWith(\"sumOf(selector)\")",
                    ]
                ),
            ],
            flags: [.synthetic, .inlineFunction],
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-TEXT-HOF-007: CharSequence.sumByDouble(selector) deprecated surface ---
        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "sumByDouble",
            externalLinkName: "kk_string_sumByDouble",
            receiverType: charSequenceType,
            parameters: [("selector", charToDoubleType, false, false)],
            returnType: doubleType,
            annotations: [
                MetadataAnnotationRecord(
                    annotationFQName: "kotlin.Deprecated",
                    arguments: [
                        "message = \"Use sumOf instead.\"",
                        "replaceWith = ReplaceWith(\"sumOf(selector)\")",
                    ]
                ),
            ],
            flags: [.synthetic, .inlineFunction],
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "filterIndexed",
            externalLinkName: "kk_string_filterIndexed",
            receiverType: stringType,
            parameters: [("predicate", intCharToBoolType, false, false)],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )
        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "filterNot",
            externalLinkName: "kk_string_filterNot",
            receiverType: stringType,
            parameters: [("predicate", charToBoolType, false, false)],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )
        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "takeWhile",
            externalLinkName: "kk_string_takeWhile",
            receiverType: stringType,
            parameters: [("predicate", charToBoolType, false, false)],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )
        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "dropWhile",
            externalLinkName: "kk_string_dropWhile",
            receiverType: stringType,
            parameters: [("predicate", charToBoolType, false, false)],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )
        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "find",
            externalLinkName: "kk_string_find",
            receiverType: stringType,
            parameters: [("predicate", charToBoolType, false, false)],
            returnType: nullableCharType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )
        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "findLast",
            externalLinkName: "kk_string_findLast",
            receiverType: stringType,
            parameters: [("predicate", charToBoolType, false, false)],
            returnType: nullableCharType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )
        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "splitToSequence",
            externalLinkName: "kk_string_splitToSequence",
            receiverType: stringType,
            parameters: [("delimiter", stringType, false, false)],
            returnType: sequenceStringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // --- String.indexOfFirst / indexOfLast ---
        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "indexOfFirst",
            externalLinkName: "kk_string_indexOfFirst",
            receiverType: stringType,
            parameters: [("predicate", charToBoolType, false, false)],
            returnType: intType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )
        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "indexOfLast",
            externalLinkName: "kk_string_indexOfLast",
            receiverType: stringType,
            parameters: [("predicate", charToBoolType, false, false)],
            returnType: intType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-315: String.replaceFirstChar ---
        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "replaceFirstChar",
            externalLinkName: "kk_string_replaceFirstChar",
            receiverType: stringType,
            parameters: [("transform", charToCharType, false, false)],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-142: String.toBoolean / toBooleanStrict ---

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "toBoolean",
            externalLinkName: "kk_string_toBoolean",
            receiverType: stringType,
            parameters: [],
            returnType: boolType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "toBooleanStrict",
            externalLinkName: "kk_string_toBooleanStrict",
            receiverType: stringType,
            parameters: [],
            returnType: boolType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "toBooleanStrictOrNull",
            externalLinkName: "kk_string_toBooleanStrictOrNull",
            receiverType: stringType,
            parameters: [],
            returnType: nullableBoolType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "toShort",
            externalLinkName: "kk_string_toShort",
            receiverType: stringType,
            parameters: [],
            returnType: intType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "toShortOrNull",
            externalLinkName: "kk_string_toShortOrNull",
            receiverType: stringType,
            parameters: [],
            returnType: nullableIntType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "toByte",
            externalLinkName: "kk_string_toByte",
            receiverType: stringType,
            parameters: [],
            returnType: intType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "toByteOrNull",
            externalLinkName: "kk_string_toByteOrNull",
            receiverType: stringType,
            parameters: [],
            returnType: nullableIntType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-143: String.lines ---

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "lines",
            externalLinkName: "kk_string_lines",
            receiverType: stringType,
            parameters: [],
            returnType: listStringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-666: String.lineSequence ---

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "lineSequence",
            externalLinkName: "kk_string_lineSequence",
            receiverType: stringType,
            parameters: [],
            returnType: sequenceStringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-144: String.trimStart / trimEnd ---

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "trimStart",
            externalLinkName: "kk_string_trimStart",
            receiverType: stringType,
            parameters: [],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "trimStart",
            externalLinkName: "kk_string_trimStart_predicate",
            receiverType: stringType,
            parameters: [("predicate", charToBoolType, false, false)],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "trimEnd",
            externalLinkName: "kk_string_trimEnd",
            receiverType: stringType,
            parameters: [],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "trimEnd",
            externalLinkName: "kk_string_trimEnd_predicate",
            receiverType: stringType,
            parameters: [("predicate", charToBoolType, false, false)],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-145: String.toByteArray / encodeToByteArray ---

        let listIntType = SyntheticStringStubRegistration.makeListType(
            symbols: symbols,
            types: types,
            interner: interner,
            elementType: intType
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "toByteArray",
            externalLinkName: "kk_string_toByteArray",
            receiverType: stringType,
            parameters: [],
            returnType: listIntType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // STDLIB-581: String.toByteArray(charset: Charset)
        let charsetSymbol = ensureClassSymbol(
            named: "Charset", in: kotlinTextPkg,
            symbols: symbols, interner: interner
        )
        let charsetType = types.make(.classType(ClassType(
            classSymbol: charsetSymbol, args: [], nullability: .nonNull
        )))
        symbols.setPropertyType(charsetType, for: charsetSymbol)

        // Register Charsets singleton object with charset constants
        let charsetsSymbol = ensureSyntheticObjectSymbol(
            named: "Charsets",
            in: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )
        let charsetsType = types.make(.classType(ClassType(
            classSymbol: charsetsSymbol, args: [], nullability: .nonNull
        )))
        symbols.setPropertyType(charsetsType, for: charsetsSymbol)

        for charsetName in [
            "UTF_8", "ISO_8859_1", "US_ASCII",
            "UTF_16", "UTF_16BE", "UTF_16LE",
            "UTF_32", "UTF_32BE", "UTF_32LE",
        ] {
            SyntheticStringStubRegistration.registerSyntheticObjectProperty(
                ownerSymbol: charsetsSymbol,
                ownerType: charsetsType,
                name: charsetName,
                propertyType: charsetType,
                symbols: symbols,
                interner: interner
            )
        }

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "toByteArray",
            externalLinkName: "kk_string_toByteArray_charset",
            receiverType: stringType,
            parameters: [
                ("charset", charsetType, false, false),
            ],
            returnType: listIntType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // STDLIB-573: String.encodeToByteArray()
        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "encodeToByteArray",
            externalLinkName: "kk_string_encodeToByteArray",
            receiverType: stringType,
            parameters: [],
            returnType: listIntType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // STDLIB-573: String.encodeToByteArray(startIndex, endIndex)
        for functionName in ["encodeToByteArray", "toByteArray"] {
            SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
                named: functionName,
                externalLinkName: "kk_string_encodeToByteArray_range",
                receiverType: stringType,
                parameters: [
                    ("startIndex", intType, false, false),
                    ("endIndex", intType, false, false),
                ],
                returnType: listIntType,
                packageFQName: kotlinTextPkg,
                symbols: symbols,
                interner: interner
            )
        }

        // STDLIB-573: String.encodeToByteArray(charset) — charset-aware overload
        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "encodeToByteArray",
            externalLinkName: "kk_string_encodeToByteArray_charset",
            receiverType: stringType,
            parameters: [
                ("charset", charsetType, false, false),
            ],
            returnType: listIntType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        let javaMathPkg = ensurePackage(
            path: ["java", "math"],
            symbols: symbols,
            interner: interner
        )
        let javaMathPkgSymbol = symbols.lookup(fqName: javaMathPkg)
        let bigDecimalSymbol = ensureClassSymbol(
            named: "BigDecimal",
            in: javaMathPkg,
            symbols: symbols,
            interner: interner
        )
        let bigIntegerSymbol = ensureClassSymbol(
            named: "BigInteger",
            in: javaMathPkg,
            symbols: symbols,
            interner: interner
        )
        if let javaMathPkgSymbol {
            symbols.setParentSymbol(javaMathPkgSymbol, for: bigDecimalSymbol)
            symbols.setParentSymbol(javaMathPkgSymbol, for: bigIntegerSymbol)
        }
        let bigDecimalType = types.make(.classType(ClassType(
            classSymbol: bigDecimalSymbol, args: [], nullability: .nonNull
        )))
        symbols.setPropertyType(bigDecimalType, for: bigDecimalSymbol)
        let bigIntegerType = types.make(.classType(ClassType(
            classSymbol: bigIntegerSymbol, args: [], nullability: .nonNull
        )))
        symbols.setPropertyType(bigIntegerType, for: bigIntegerSymbol)

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "toBigDecimal",
            externalLinkName: "kk_string_toBigDecimal",
            receiverType: stringType,
            parameters: [],
            returnType: bigDecimalType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "toBigInteger",
            externalLinkName: "kk_string_toBigInteger",
            receiverType: stringType,
            parameters: [],
            returnType: bigIntegerType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticBigNumberMemberFunction(
            ownerSymbol: bigDecimalSymbol,
            ownerType: bigDecimalType,
            name: "toString",
            returnType: stringType,
            externalLinkName: "kk_bignum_toString",
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticBigNumberMemberFunction(
            ownerSymbol: bigIntegerSymbol,
            ownerType: bigIntegerType,
            name: "toString",
            returnType: stringType,
            externalLinkName: "kk_bignum_toString",
            symbols: symbols,
            interner: interner
        )

        // STDLIB-574: ByteArray.decodeToString()
        let byteArrayType = SyntheticStringStubRegistration.makeNominalType(
            symbols: symbols,
            types: types,
            fqName: [interner.intern("kotlin"), interner.intern("ByteArray")]
        )

        // Register on both List<Int> (internal representation) and ByteArray (user-facing type)
        for receiverType in [listIntType, byteArrayType] {
            SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
                named: "decodeToString",
                externalLinkName: "kk_bytearray_decodeToString",
                receiverType: receiverType,
                parameters: [],
                returnType: stringType,
                packageFQName: kotlinTextPkg,
                symbols: symbols,
                interner: interner
            )
        }

        for charsetPropName in ["UTF_8", "US_ASCII", "ISO_8859_1"] {
            let propName = interner.intern(charsetPropName)
            let propFQName = [interner.intern("kotlin"), interner.intern("text"), interner.intern("Charsets"), propName]
            guard symbols.lookup(fqName: propFQName) == nil else { continue }
            let propSymbol = symbols.define(
                kind: .property,
                name: propName,
                fqName: propFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(charsetsSymbol, for: propSymbol)
            symbols.setPropertyType(charsetType, for: propSymbol)
        }

        // STDLIB-574: ByteArray.decodeToString(charset: Charset) overload
        for receiverType in [listIntType, byteArrayType] {
            SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
                named: "decodeToString",
                externalLinkName: "kk_bytearray_decodeToString_charset",
                receiverType: receiverType,
                parameters: [
                    ("charset", charsetType, false, false),
                ],
                returnType: stringType,
                packageFQName: kotlinTextPkg,
                symbols: symbols,
                interner: interner
            )
        }

        // STDLIB-TEXT-EDGE-006: ByteArray.decodeToString(startIndex, endIndex, throwOnInvalidSequence)
        for receiverType in [listIntType, byteArrayType] {
            SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
                named: "decodeToString",
                externalLinkName: "kk_bytearray_decodeToString_range",
                receiverType: receiverType,
                parameters: [
                    ("startIndex", intType, false, false),
                    ("endIndex", intType, false, false),
                ],
                returnType: stringType,
                packageFQName: kotlinTextPkg,
                symbols: symbols,
                interner: interner
            )

            SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
                named: "decodeToString",
                externalLinkName: "kk_bytearray_decodeToString_range_throw",
                receiverType: receiverType,
                parameters: [
                    ("startIndex", intType, false, false),
                    ("endIndex", intType, false, false),
                    ("throwOnInvalidSequence", types.booleanType, false, false),
                ],
                returnType: stringType,
                packageFQName: kotlinTextPkg,
                symbols: symbols,
                interner: interner
            )
        }

        // STDLIB-STR-125: String(ByteArray, Charset) constructor
        // Allows decoding a byte array with an explicit charset: String(bytes, Charsets.UTF_8)
        // Register on both List<Int> (internal representation) and ByteArray (user-facing type)
        let kotlinPkg: [InternedString] = [interner.intern("kotlin")]
        let stringClassSymbol = ensureClassSymbol(
            named: "String",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        if let kotlinPkgSymbol = symbols.lookup(fqName: kotlinPkg) {
            symbols.setParentSymbol(kotlinPkgSymbol, for: stringClassSymbol)
        }
        symbols.setDirectSupertypes([charSequenceSymbol], for: stringClassSymbol)
        types.setNominalDirectSupertypes([charSequenceSymbol], for: stringClassSymbol)
        for bytesType in [listIntType, byteArrayType] {
            SyntheticStringStubRegistration.registerStringConstructorFromBytes(
                ownerSymbol: stringClassSymbol,
                ownerType: stringType,
                parameters: [("bytes", bytesType), ("charset", charsetType)],
                externalLinkName: "kk_bytearray_decodeToString_charset",
                symbols: symbols,
                interner: interner
            )
            // String(ByteArray) — default UTF-8 decoding
            SyntheticStringStubRegistration.registerStringConstructorFromBytes(
                ownerSymbol: stringClassSymbol,
                ownerType: stringType,
                parameters: [("bytes", bytesType)],
                externalLinkName: "kk_bytearray_decodeToString",
                symbols: symbols,
                interner: interner
            )
        }

        // --- STDLIB-I18N-COMMON-001: String.format companion method ---
        // Kotlin: String.format(format: String, vararg args: Any?) -> String
        // This is a companion (static) method on the String class, not an extension.
        let stringCompanionFQName = SyntheticStringStubRegistration.ensureStringCompanionSymbol(
            ownerSymbol: stringClassSymbol,
            symbols: symbols,
            interner: interner
        )
        SyntheticStringStubRegistration.registerStringCompanionMethod(
            named: "format",
            externalLinkName: "kk_string_format",
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
        SyntheticStringStubRegistration.registerStringCompanionMethod(
            named: "format",
            externalLinkName: "kk_string_format_locale",
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

        // --- STDLIB-316: String.chunked / String.windowed ---

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "chunked",
            externalLinkName: "kk_string_chunked",
            receiverType: stringType,
            parameters: [
                ("size", intType, false, false),
            ],
            returnType: listStringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        for receiverType in [charSequenceType, stringType] {
            SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
                named: "chunkedSequence",
                externalLinkName: "kk_string_chunked_sequence",
                receiverType: receiverType,
                parameters: [
                    ("size", intType, false, false),
                ],
                returnType: sequenceStringType,
                packageFQName: kotlinTextPkg,
                symbols: symbols,
                interner: interner
            )
        }

        do {
            let functionName = interner.intern("chunkedSequence")
            let functionFQName = kotlinTextPkg + [functionName]
            let rName = interner.intern("R")
            let rFQName = functionFQName + [rName]
            let rSymbol: SymbolID = if let existing = symbols.lookup(fqName: rFQName) {
                existing
            } else {
                symbols.define(
                    kind: .typeParameter,
                    name: rName,
                    fqName: rFQName,
                    declSite: nil,
                    visibility: .private,
                    flags: []
                )
            }
            let rType = types.make(.typeParam(TypeParamType(
                symbol: rSymbol,
                nullability: .nonNull
            )))
            let transformType = types.make(.functionType(FunctionType(
                params: [charSequenceType],
                returnType: rType,
                isSuspend: false,
                nullability: .nonNull
            )))
            let sequenceRType = SyntheticStringStubRegistration.makeSequenceType(
                symbols: symbols,
                types: types,
                interner: interner,
                elementType: rType
            )
            for receiverType in [charSequenceType, stringType] {
                guard !symbols.lookupAll(fqName: functionFQName).contains(where: { symbolID in
                    guard let signature = symbols.functionSignature(for: symbolID) else {
                        return false
                    }
                    return signature.receiverType == receiverType
                        && signature.parameterTypes == [intType, transformType]
                }) else {
                    continue
                }
                let functionSymbol = symbols.define(
                    kind: .function,
                    name: functionName,
                    fqName: functionFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic, .inlineFunction]
                )
                if let packageSymbol = symbols.lookup(fqName: kotlinTextPkg) {
                    symbols.setParentSymbol(packageSymbol, for: functionSymbol)
                }
                symbols.setExternalLinkName("kk_string_chunked_sequence_transform", for: functionSymbol)
                let sizeParameter = symbols.define(
                    kind: .valueParameter,
                    name: interner.intern("size"),
                    fqName: functionFQName + [interner.intern("size")],
                    declSite: nil,
                    visibility: .private,
                    flags: [.synthetic]
                )
                let transformParameter = symbols.define(
                    kind: .valueParameter,
                    name: interner.intern("transform"),
                    fqName: functionFQName + [interner.intern("transform")],
                    declSite: nil,
                    visibility: .private,
                    flags: [.synthetic]
                )
                symbols.setParentSymbol(functionSymbol, for: sizeParameter)
                symbols.setParentSymbol(functionSymbol, for: transformParameter)
                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: receiverType,
                        parameterTypes: [intType, transformType],
                        returnType: sequenceRType,
                        isSuspend: false,
                        valueParameterSymbols: [sizeParameter, transformParameter],
                        valueParameterHasDefaultValues: [false, false],
                        valueParameterIsVararg: [false, false],
                        typeParameterSymbols: [rSymbol]
                    ),
                    for: functionSymbol
                )
            }
        }

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "windowed",
            externalLinkName: "kk_string_windowed_default",
            receiverType: stringType,
            parameters: [
                ("size", intType, false, false),
            ],
            returnType: listStringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "windowed",
            externalLinkName: "kk_string_windowed",
            receiverType: stringType,
            parameters: [
                ("size", intType, false, false),
                ("step", intType, false, false),
            ],
            returnType: listStringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "windowed",
            externalLinkName: "kk_string_windowed_partial",
            receiverType: stringType,
            parameters: [
                ("size", intType, false, false),
                ("step", intType, false, false),
                ("partialWindows", boolType, false, false),
            ],
            returnType: listStringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-TEXT-SEQ-003: CharSequence.windowedSequence(size, step, partialWindows) ---

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "windowedSequence",
            externalLinkName: "kk_string_windowedSequence_partial",
            receiverType: charSequenceType,
            parameters: [
                ("size", intType, false, false),
                ("step", intType, false, false),
                ("partialWindows", boolType, false, false),
            ],
            returnType: sequenceStringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-TEXT-SEQ-004: CharSequence.windowedSequence(size, step, partialWindows, transform) ---

        let windowedSequenceTransformFQName = kotlinTextPkg + [interner.intern("windowedSequence")]
        let windowedSequenceRName = interner.intern("R")
        let windowedSequenceRFQName = windowedSequenceTransformFQName + [windowedSequenceRName]
        let windowedSequenceRSymbol: SymbolID = if let existing = symbols.lookup(fqName: windowedSequenceRFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: windowedSequenceRName,
                fqName: windowedSequenceRFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        let windowedSequenceRType = types.make(.typeParam(TypeParamType(
            symbol: windowedSequenceRSymbol,
            nullability: .nonNull
        )))
        let windowedSequenceTransformType = types.make(.functionType(FunctionType(
            params: [charSequenceType],
            returnType: windowedSequenceRType,
            isSuspend: false,
            nullability: .nonNull
        )))
        let windowedSequenceTransformReturnType = SyntheticStringStubRegistration.makeSequenceType(
            symbols: symbols,
            types: types,
            interner: interner,
            elementType: windowedSequenceRType
        )
        let hasWindowedSequenceTransform = symbols.lookupAll(fqName: windowedSequenceTransformFQName).contains { symID in
            guard let sig = symbols.functionSignature(for: symID) else {
                return false
            }
            return sig.receiverType == charSequenceType && sig.parameterTypes.count == 4
        }
        if !hasWindowedSequenceTransform {
            let memberSymbol = symbols.define(
                kind: .function,
                name: interner.intern("windowedSequence"),
                fqName: windowedSequenceTransformFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .inlineFunction]
            )
            if let packageSymbol = symbols.lookup(fqName: kotlinTextPkg) {
                symbols.setParentSymbol(packageSymbol, for: memberSymbol)
            }
            symbols.setExternalLinkName("kk_string_windowedSequence_transform", for: memberSymbol)

            let sizeParamName = interner.intern("size")
            let sizeParamSymbol = symbols.define(
                kind: .valueParameter,
                name: sizeParamName,
                fqName: windowedSequenceTransformFQName + [sizeParamName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(memberSymbol, for: sizeParamSymbol)

            let stepParamName = interner.intern("step")
            let stepParamSymbol = symbols.define(
                kind: .valueParameter,
                name: stepParamName,
                fqName: windowedSequenceTransformFQName + [stepParamName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(memberSymbol, for: stepParamSymbol)

            let partialWindowsParamName = interner.intern("partialWindows")
            let partialWindowsParamSymbol = symbols.define(
                kind: .valueParameter,
                name: partialWindowsParamName,
                fqName: windowedSequenceTransformFQName + [partialWindowsParamName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(memberSymbol, for: partialWindowsParamSymbol)

            let transformParamName = interner.intern("transform")
            let transformParamSymbol = symbols.define(
                kind: .valueParameter,
                name: transformParamName,
                fqName: windowedSequenceTransformFQName + [transformParamName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(memberSymbol, for: transformParamSymbol)

            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: charSequenceType,
                    parameterTypes: [intType, intType, boolType, windowedSequenceTransformType],
                    returnType: windowedSequenceTransformReturnType,
                    valueParameterSymbols: [
                        sizeParamSymbol,
                        stepParamSymbol,
                        partialWindowsParamSymbol,
                        transformParamSymbol,
                    ],
                    valueParameterHasDefaultValues: [false, false, false, false],
                    valueParameterIsVararg: [false, false, false, false],
                    typeParameterSymbols: [windowedSequenceRSymbol],
                    classTypeParameterCount: 0
                ),
                for: memberSymbol
            )
        }

        // --- STDLIB-318: String.commonPrefixWith / commonSuffixWith ---

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "commonPrefixWith",
            externalLinkName: "kk_string_commonPrefixWith",
            receiverType: stringType,
            parameters: [
                ("other", stringType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "commonSuffixWith",
            externalLinkName: "kk_string_commonSuffixWith",
            receiverType: stringType,
            parameters: [
                ("other", stringType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-575/576: commonPrefixWith / commonSuffixWith (ignoreCase overloads) ---

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "commonPrefixWith",
            externalLinkName: "kk_string_commonPrefixWith_ignoreCase",
            receiverType: stringType,
            parameters: [
                ("other", stringType, false, false),
                ("ignoreCase", boolType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "commonSuffixWith",
            externalLinkName: "kk_string_commonSuffixWith_ignoreCase",
            receiverType: stringType,
            parameters: [
                ("other", stringType, false, false),
                ("ignoreCase", boolType, false, false),
            ],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-316: String/CharSequence.zipWithNext ---

        let pairFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("Pair"),
        ]
        let pairCharCharType: TypeID
        if let pairSymbol = symbols.lookup(fqName: pairFQName) {
            pairCharCharType = types.make(.classType(ClassType(
                classSymbol: pairSymbol,
                args: [.out(charType), .out(charType)],
                nullability: .nonNull
            )))
        } else {
            pairCharCharType = types.anyType
        }
        let listPairCharCharType = SyntheticStringStubRegistration.makeListType(
            symbols: symbols,
            types: types,
            interner: interner,
            elementType: pairCharCharType
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "zipWithNext",
            externalLinkName: "kk_string_zipWithNext",
            receiverType: stringType,
            parameters: [],
            returnType: listPairCharCharType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "zipWithNext",
            externalLinkName: "kk_string_zipWithNext",
            receiverType: charSequenceType,
            parameters: [],
            returnType: listPairCharCharType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // String/CharSequence.zipWithNext(transform: (Char, Char) -> R)
        let zipWithNextTransformFQName = kotlinTextPkg + [interner.intern("zipWithNext")]
        func registerZipWithNextTransform(receiverType: TypeID) {
            let existingZipWithNextTransform = symbols.lookupAll(fqName: zipWithNextTransformFQName).first { symID in
                guard let sig = symbols.functionSignature(for: symID) else {
                    return false
                }
                return sig.receiverType == receiverType && sig.parameterTypes.count == 1
            }
            if let existingZipWithNextTransform {
                symbols.setExternalLinkName("kk_string_zipWithNextTransform", for: existingZipWithNextTransform)
                return
            }

            let rName = interner.intern("R")
            let rSymbol = symbols.define(
                kind: .typeParameter,
                name: rName,
                fqName: zipWithNextTransformFQName + [rName],
                declSite: nil,
                visibility: .private,
                flags: []
            )
            let rType = types.make(.typeParam(TypeParamType(symbol: rSymbol, nullability: .nonNull)))
            let transformFnType = types.make(.functionType(FunctionType(
                params: [charType, charType],
                returnType: rType,
                isSuspend: false,
                nullability: .nonNull
            )))
            let transformResultType = SyntheticStringStubRegistration.makeListType(
                symbols: symbols,
                types: types,
                interner: interner,
                elementType: rType
            )
            let transformMemberSymbol = symbols.define(
                kind: .function,
                name: interner.intern("zipWithNext"),
                fqName: zipWithNextTransformFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .inlineFunction]
            )
            if let packageSymbol = symbols.lookup(fqName: kotlinTextPkg) {
                symbols.setParentSymbol(packageSymbol, for: transformMemberSymbol)
            }
            symbols.setExternalLinkName("kk_string_zipWithNextTransform", for: transformMemberSymbol)
            let transformParamName = interner.intern("transform")
            let transformParamSymbol = symbols.define(
                kind: .valueParameter,
                name: transformParamName,
                fqName: zipWithNextTransformFQName + [transformParamName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(transformMemberSymbol, for: transformParamSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: [transformFnType],
                    returnType: transformResultType,
                    valueParameterSymbols: [transformParamSymbol],
                    valueParameterHasDefaultValues: [false],
                    valueParameterIsVararg: [false],
                    typeParameterSymbols: [rSymbol],
                    classTypeParameterCount: 0
                ),
                for: transformMemberSymbol
            )
        }
        registerZipWithNextTransform(receiverType: stringType)
        registerZipWithNextTransform(receiverType: charSequenceType)

        // --- String.partition ---
        let pairStringStringType: TypeID
        if let pairSymbol = symbols.lookup(fqName: pairFQName) {
            pairStringStringType = types.make(.classType(ClassType(
                classSymbol: pairSymbol,
                args: [.out(stringType), .out(stringType)],
                nullability: .nonNull
            )))
        } else {
            pairStringStringType = types.anyType
        }
        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "partition",
            externalLinkName: "kk_string_partition",
            receiverType: stringType,
            parameters: [("predicate", charToBoolType, false, false)],
            returnType: pairStringStringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-317: String.asSequence / asIterable ---

        let sequenceCharType = SyntheticStringStubRegistration.makeSequenceType(
            symbols: symbols,
            types: types,
            interner: interner,
            elementType: charType
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "asSequence",
            externalLinkName: "kk_string_asSequence",
            receiverType: stringType,
            parameters: [],
            returnType: sequenceCharType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "asIterable",
            externalLinkName: "kk_string_asIterable",
            receiverType: stringType,
            parameters: [],
            returnType: iterableCharType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-534: String?.orEmpty() ---

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "orEmpty",
            externalLinkName: "kk_string_orEmpty",
            receiverType: nullableStringType,
            parameters: [],
            returnType: stringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-TEXT-EDGE-009: CharSequence?.contentEquals ---

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "contentEquals",
            externalLinkName: "kk_string_contentEquals",
            receiverType: nullableStringType,
            parameters: [
                ("other", nullableStringType, false, false),
            ],
            returnType: boolType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        SyntheticStringStubRegistration.registerSyntheticStringExtensionFunction(
            named: "contentEquals",
            externalLinkName: "kk_string_contentEquals_ignoreCase",
            receiverType: nullableStringType,
            parameters: [
                ("other", nullableStringType, false, false),
                ("ignoreCase", boolType, false, false),
            ],
            returnType: boolType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )
    }

}
