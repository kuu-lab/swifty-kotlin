// swiftlint:disable file_length

/// `RuntimeABISpec.ioFunctions` extracted from `RuntimeABISpec.swift`.
public extension RuntimeABISpec {
    static let ioFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_io_default_buffer_size",
            parameters: [],
            returnType: .intptr,
            section: "IO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_readline",
            parameters: [],
            returnType: .intptr,
            section: "IO",
            isThrowing: false,
        ),
        RuntimeABIFunctionSpec(
            name: "kk_readln",
            parameters: [
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "IO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_readln_from_syscall",
            parameters: [
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "IO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_readlnOrNull",
            parameters: [],
            returnType: .intptr,
            section: "IO",
            isThrowing: false,
        ),
    ]
}
