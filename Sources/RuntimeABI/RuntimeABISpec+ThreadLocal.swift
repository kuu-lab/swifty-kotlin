private let abi = RuntimeABISectionBuilder("ThreadLocal")

public extension RuntimeABISpec {
    static let threadLocalNewBridgeSpec = abi.nt("__kk_thread_local_new")

    static let threadLocalHasValueBridgeSpec = abi.nt("__kk_thread_local_has_value", "receiver")

    static let threadLocalValueBridgeSpec = abi.nt("__kk_thread_local_value", "receiver")

    static let threadLocalStoreBridgeSpec = abi.nt("__kk_thread_local_store", "receiver value")

    static let threadLocalFunctions: [RuntimeABIFunctionSpec] = [
        threadLocalNewBridgeSpec,
        threadLocalHasValueBridgeSpec,
        threadLocalValueBridgeSpec,
        threadLocalStoreBridgeSpec,
        abi.nt("__kk_thread_local_remove", "receiver"),
        abi.nt("__kk_thread_non_daemon_start"),
        abi.nt("__kk_thread_non_daemon_finish"),
        abi.nt("__kk_thread_wait_non_daemon"),
        abi.nt("__kk_thread_report_uncaught", "exception"),
    ]
}
