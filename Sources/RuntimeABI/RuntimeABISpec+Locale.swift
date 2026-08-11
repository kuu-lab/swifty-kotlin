/// Locale-parameterized string operations not already covered by `stringFunctions`.
///
/// `kk_locale_new_flat`, `kk_locale_new_language_country_flat`, and the private
/// `__kk_string_format_locale` bridges are registered in
/// `RuntimeABISpec+String.swift` (`stringFunctions`); they are intentionally omitted
/// here to avoid duplicate `allFunctions` entries. Locale member APIs removed by
/// CLEANUP-STUB-112 are intentionally absent.
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
