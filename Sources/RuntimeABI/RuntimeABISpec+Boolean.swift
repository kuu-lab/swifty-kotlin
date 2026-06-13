
/// `RuntimeABISpec.booleanFunctions` extracted from `RuntimeABISpec.swift`.
public extension RuntimeABISpec {

    /// Boolean logical operators
    static let booleanFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_op_not",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Boolean"
        ),
    ]

    /// Char operations
}
