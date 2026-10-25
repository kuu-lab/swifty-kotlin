private let abi = RuntimeABISectionBuilder("String")

/// `__kk_locale_new_flat`, `__kk_locale_new_language_country_flat`, and the private
/// `__kk_string_format_locale_flat` bridge are registered in
/// `RuntimeABISpec+String.swift` (`stringFunctions`); they are intentionally omitted
/// here to avoid duplicate `allFunctions` entries.
public extension RuntimeABISpec {
    static let localeFunctions: [RuntimeABIFunctionSpec] = [
        abi.nt("__kk_locale_get_default"),
        abi.nt("__kk_locale_set_default", "localeRaw", ret: .void),
        abi.nt("__kk_locale_for_language_tag", "tagRaw"),
        abi.nt("__kk_locale_get_language", "localeRaw"),
        abi.nt("__kk_locale_get_country", "localeRaw"),
        abi.nt("__kk_locale_get_variant", "localeRaw"),
        abi.nt("__kk_locale_get_display_name", "localeRaw displayLocaleRaw"),
        abi.nt("__kk_locale_get_display_language", "localeRaw displayLocaleRaw"),
        abi.nt("__kk_locale_get_display_country", "localeRaw displayLocaleRaw"),
        abi.nt("__kk_locale_to_language_tag", "localeRaw"),
        abi.nt("__kk_locale_toString_flat", "localeRaw outLength:nullableIntptrPointer outByteCount:nullableIntptrPointer outHash:nullableIntptrPointer", ret: .nullableUInt8Pointer),
        abi.nt("__kk_lowercase_locale", "strRaw localeRaw"),
        abi.nt("__kk_uppercase_locale", "strRaw localeRaw"),
        abi.nt("__kk_string_compareTo_locale", "lhsRaw rhsRaw localeRaw"),
    ]
}
