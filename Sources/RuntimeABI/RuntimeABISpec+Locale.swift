/// Locale functions and locale-parameterized string operations.
public extension RuntimeABISpec {
    static let localeFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_locale_new",
            parameters: [
                RuntimeABIParameter(name: "identifierRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_locale_new_language_country",
            parameters: [
                RuntimeABIParameter(name: "languageRaw", type: .intptr),
                RuntimeABIParameter(name: "countryRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_locale_language",
            parameters: [
                RuntimeABIParameter(name: "localeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_locale_country",
            parameters: [
                RuntimeABIParameter(name: "localeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_locale_variant",
            parameters: [
                RuntimeABIParameter(name: "localeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_locale_displayLanguage",
            parameters: [
                RuntimeABIParameter(name: "localeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_locale_getDefault",
            parameters: [
                RuntimeABIParameter(name: "companionRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_locale_setDefault",
            parameters: [
                RuntimeABIParameter(name: "companionRaw", type: .intptr),
                RuntimeABIParameter(name: "localeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_locale_getAvailableLocales",
            parameters: [
                RuntimeABIParameter(name: "companionRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_locale_hashCode",
            parameters: [
                RuntimeABIParameter(name: "localeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_locale_equals",
            parameters: [
                RuntimeABIParameter(name: "localeRaw", type: .intptr),
                RuntimeABIParameter(name: "otherRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_lowercase_locale",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "localeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_uppercase_locale",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "localeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_compareTo_locale",
            parameters: [
                RuntimeABIParameter(name: "lhsRaw", type: .intptr),
                RuntimeABIParameter(name: "rhsRaw", type: .intptr),
                RuntimeABIParameter(name: "localeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_format_locale",
            parameters: [
                RuntimeABIParameter(name: "localeRaw", type: .intptr),
                RuntimeABIParameter(name: "formatRaw", type: .intptr),
                RuntimeABIParameter(name: "argsArrayRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
    ]
}
