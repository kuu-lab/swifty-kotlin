// swiftlint:disable file_length

/// `RuntimeABISpec.consolePrintFunctions` extracted from `RuntimeABISpec.swift`.
public extension RuntimeABISpec {
    static let consolePrintFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "__kk_print_raw",
            parameters: [
                RuntimeABIParameter(name: "messageRaw", type: .intptr),
            ],
            returnType: .void,
            section: "Print",
            isThrowing: false
        ),
    ]
}
