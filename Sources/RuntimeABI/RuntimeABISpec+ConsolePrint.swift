// swiftlint:disable file_length

/// `RuntimeABISpec.consolePrintFunctions` extracted from `RuntimeABISpec.swift`.
public extension RuntimeABISpec {
    static let consolePrintFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "__kk_print_raw",
            parameters: [
                RuntimeABIParameter(name: "obj", type: .intptr),
            ],
            returnType: .void,
            section: "Print",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_println_bool",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .void,
            section: "Print"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_println_ulong",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .void,
            section: "Print",
            isThrowing: false
        ),
    ]
}
