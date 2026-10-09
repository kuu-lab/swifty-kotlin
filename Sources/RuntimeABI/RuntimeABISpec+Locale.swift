/// Locale-parameterized string operations not already covered by `stringFunctions`.
///
/// `__kk_locale_new_flat`, `__kk_locale_new_language_country_flat`, and the private
/// `__kk_string_format_locale_flat` bridge are registered in
/// `RuntimeABISpec+String.swift` (`stringFunctions`); they are intentionally omitted
/// here to avoid duplicate `allFunctions` entries.
public extension RuntimeABISpec {
    static let localeFunctions: [RuntimeABIFunctionSpec] = [
        // Memory representation: read fields from the runtime-owned Locale box.
        RuntimeABIFunctionSpec(
            name: "__kk_locale_toString_flat",
            parameters: [
                RuntimeABIParameter(name: "localeRaw", type: .intptr),
                RuntimeABIParameter(name: "outLength", type: .nullableIntptrPointer),
                RuntimeABIParameter(name: "outByteCount", type: .nullableIntptrPointer),
                RuntimeABIParameter(name: "outHash", type: .nullableIntptrPointer),
            ],
            returnType: .nullableUInt8Pointer,
            section: "String",
            isThrowing: false
        ),
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
