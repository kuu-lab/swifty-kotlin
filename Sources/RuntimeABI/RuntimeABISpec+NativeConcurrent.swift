private let abi = RuntimeABISectionBuilder("NativeConcurrent")

public extension RuntimeABISpec {
    static let nativeConcurrentFunctions: [RuntimeABIFunctionSpec] = [
        abi.nt("__kk_native_concurrent_active_workers"),
        abi.nt("__kk_native_concurrent_attach_object_graph", "stableRaw"),
        abi.nt("__kk_native_concurrent_consume_future", "futureHandle"),
        abi.nt("__kk_native_concurrent_current_worker"),
        abi.nt("__kk_native_concurrent_detach_object_graph", "modeRaw valueRaw"),
        abi.nt("__kk_native_concurrent_execute_impl", "workerHandle modeRaw jobArgumentRaw jobPointerHandle"),
        abi.nt("__kk_native_concurrent_start_worker", "errorReportingRaw nameRaw"),
        abi.nt("__kk_native_concurrent_terminate_worker", "workerHandle"),
        abi.nt("__kk_native_concurrent_wait_for_multiple_futures", "futuresHandle timeoutMillis"),
        abi.nt("__kk_native_concurrent_wait_worker_termination", "workerHandle"),
        abi.nt("__kk_native_concurrent_worker_from_cpointer", "pointerHandle"),
    ]
}
