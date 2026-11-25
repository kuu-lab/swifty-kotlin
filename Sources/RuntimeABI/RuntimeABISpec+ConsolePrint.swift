private let abi = RuntimeABISectionBuilder("Print")

public extension RuntimeABISpec {
    static let bridgePrintRawSpec: RuntimeABIFunctionSpec = abi.nt("__kk_print_raw", "messageRaw", ret: .void)
    static let bridgePrintlnRawSpec: RuntimeABIFunctionSpec = abi.nt("__kk_println_raw", "messageRaw", ret: .void)
    static let bridgeConsoleStdoutCloseSpec: RuntimeABIFunctionSpec = abi.nt("__kk_console_stdout_close", ret: .void)
    static let bridgeConsoleStderrCloseSpec: RuntimeABIFunctionSpec = abi.nt("__kk_console_stderr_close", ret: .void)

    static let consolePrintFunctions: [RuntimeABIFunctionSpec] = [
        bridgePrintRawSpec,
        bridgePrintlnRawSpec,
        bridgeConsoleStdoutCloseSpec,
        bridgeConsoleStderrCloseSpec,
    ]
}
