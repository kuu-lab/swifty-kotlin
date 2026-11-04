private let abi = RuntimeABISectionBuilder("IO")

public extension RuntimeABISpec {
    static let ioFunctions: [RuntimeABIFunctionSpec] = [
        abi.nt("__kk_readline_raw"),
        // KUU-4162: `System.in.close()` marks stdin closed; `kotlin.io.readLine`
        // queries this so it can throw IOException like the JVM.
        abi.nt("__kk_console_stdin_closed"),
    ]
}
