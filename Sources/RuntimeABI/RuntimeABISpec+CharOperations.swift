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
    ]
}
