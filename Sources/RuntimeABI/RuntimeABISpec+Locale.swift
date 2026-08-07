/// Locale-parameterized string operations not already covered by `stringFunctions`.
///
/// `kk_locale_new_flat`/`kk_locale_new_language_country_flat`/`kk_string_format_locale_flat`
/// are already registered in `RuntimeABISpec+String.swift` (`stringFunctions`); they are
/// intentionally omitted here to avoid duplicate `allFunctions` entries.
/// The legacy (non-flat) `kk_string_format_locale`
/// is no longer referenced by Sema and is intentionally not registered.
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
    ]
}
