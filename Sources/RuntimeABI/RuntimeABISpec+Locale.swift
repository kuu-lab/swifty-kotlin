/// Locale-parameterized string operations not already covered by `stringFunctions`.
///
/// `kk_locale_new_flat`/`kk_locale_new_language_country_flat`/`kk_locale_language`/
/// `kk_locale_country`/`kk_locale_variant`/`kk_locale_displayLanguage`/`kk_locale_getDefault`/
/// `kk_locale_setDefault`/`kk_locale_getAvailableLocales`/`kk_locale_hashCode`/
/// `kk_locale_equals`/`__kk_string_format_locale_flat` are already registered in
/// `RuntimeABISpec+String.swift` (`stringFunctions`); they are intentionally omitted here
/// to avoid duplicate `allFunctions` entries. The legacy (non-flat) public
/// `kk_string_format_locale` no longer exists; `String.format` is a private stdlib
/// bridge reachable only through the `__kk_` names.
public extension RuntimeABISpec {
    static let localeFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "__kk_lowercase_locale",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "localeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_uppercase_locale",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "localeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_string_compareTo_locale",
            parameters: [
                RuntimeABIParameter(name: "lhsRaw", type: .intptr),
                RuntimeABIParameter(name: "rhsRaw", type: .intptr),
                RuntimeABIParameter(name: "localeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
    ]
}
