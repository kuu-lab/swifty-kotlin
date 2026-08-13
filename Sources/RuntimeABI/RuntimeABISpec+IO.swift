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
            name: "__kk_readline_raw",
            parameters: [],
            returnType: .intptr,
            section: "IO",
            isThrowing: false,
        ),
    ]
}
