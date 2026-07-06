// swiftlint:disable file_length

/// `RuntimeABISpec.consolePrintFunctions` extracted from `RuntimeABISpec.swift`.
public extension RuntimeABISpec {
    static let consolePrintFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_print_any",
            parameters: [
                RuntimeABIParameter(name: "obj", type: .nullableOpaquePointer),
            ],
            returnType: .void,
            section: "Print",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_println_any",
            parameters: [
                RuntimeABIParameter(name: "obj", type: .nullableOpaquePointer),
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
        RuntimeABIFunctionSpec(
            name: "kk_print_noarg",
            parameters: [],
            returnType: .void,
            section: "Print",
            isThrowing: false,
        ),
        RuntimeABIFunctionSpec(
            name: "kk_println_newline",
            parameters: [],
            returnType: .void,
            section: "Print",
            isThrowing: false,
        ),
    ]
}
