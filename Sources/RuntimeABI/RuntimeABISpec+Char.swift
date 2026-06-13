
/// `RuntimeABISpec.charFunctions` extracted from `RuntimeABISpec.swift`.
public extension RuntimeABISpec {

    /// Char operations
    static let charFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_char_minus",
            parameters: [
                RuntimeABIParameter(name: "lhsRaw", type: .intptr),
                RuntimeABIParameter(name: "rhsRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Char"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_char_plus",
            parameters: [
                RuntimeABIParameter(name: "charValue", type: .intptr),
                RuntimeABIParameter(name: "stringRaw", type: .intptr),
            ],
            returnType: .opaquePointer,
            section: "Char"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_char_get",
            parameters: [
                RuntimeABIParameter(name: "charValue", type: .intptr),
                RuntimeABIParameter(name: "index", type: .intptr),
            ],
            returnType: .intptr,
            section: "Char"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_char_rangeTo",
            parameters: [
                RuntimeABIParameter(name: "startValue", type: .intptr),
                RuntimeABIParameter(name: "endValue", type: .intptr),
            ],
            returnType: .intptr,
            section: "Char"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_char_compareTo",
            parameters: [
                RuntimeABIParameter(name: "lhsRaw", type: .intptr),
                RuntimeABIParameter(name: "rhsRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Char"
        ),
    ]

    /// Regex (STDLIB-100/101/102/103)
}
