// swiftlint:disable file_length

/// `RuntimeABISpec.consolePrintFunctions` extracted from `RuntimeABISpec.swift`.
public extension RuntimeABISpec {
    static let bridgePrintRawSpec: RuntimeABIFunctionSpec = RuntimeABIFunctionSpec(
        name: "__kk_print_raw",
        parameters: [
            RuntimeABIParameter(name: "messageRaw", type: .intptr),
        ],
        returnType: .void,
        section: "Print",
        isThrowing: false
    )

    static let bridgePrintlnRawSpec: RuntimeABIFunctionSpec = RuntimeABIFunctionSpec(
        name: "__kk_println_raw",
        parameters: [
            RuntimeABIParameter(name: "messageRaw", type: .intptr),
        ],
        returnType: .void,
        section: "Print",
        isThrowing: false
    )

    static let consolePrintFunctions: [RuntimeABIFunctionSpec] = [
        bridgePrintRawSpec,
        bridgePrintlnRawSpec,
    ]
}
