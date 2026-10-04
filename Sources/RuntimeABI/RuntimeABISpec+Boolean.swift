// swiftlint:disable file_length

/// `RuntimeABISpec.booleanFunctions` extracted from `RuntimeABISpec.swift`.
public extension RuntimeABISpec {
    static let booleanFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_op_not",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Boolean",
            isThrowing: false
        ),
    ]
}
