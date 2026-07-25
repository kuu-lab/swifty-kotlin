// swiftlint:disable file_length

/// `RuntimeABISpec.charFunctions` extracted from `RuntimeABISpec.swift`.
public extension RuntimeABISpec {
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
            section: "Char",
            isThrowing: false
        ),
        // KSP-661: Char 判定系の Kotlin 化に伴い残す Unicode テーブル参照ブリッジ。
        RuntimeABIFunctionSpec(
            name: "__kk_char_unicode_category",
            parameters: [
                RuntimeABIParameter(name: "code", type: .intptr),
            ],
            returnType: .intptr,
            section: "Char"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_char_is_uppercase",
            parameters: [
                RuntimeABIParameter(name: "code", type: .intptr),
            ],
            returnType: .intptr,
            section: "Char"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_char_is_lowercase",
            parameters: [
                RuntimeABIParameter(name: "code", type: .intptr),
            ],
            returnType: .intptr,
            section: "Char"
        ),
    ]
}
