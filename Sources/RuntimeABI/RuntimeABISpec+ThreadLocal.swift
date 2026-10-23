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
    ]
}
