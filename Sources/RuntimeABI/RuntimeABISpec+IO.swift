private let abi = RuntimeABISectionBuilder("IO")

public extension RuntimeABISpec {
    static let ioFunctions: [RuntimeABIFunctionSpec] = [
        abi.nt("__kk_readline_raw"),
        abi.nt("__kk_console_stdin_closed"),
    ]
}
