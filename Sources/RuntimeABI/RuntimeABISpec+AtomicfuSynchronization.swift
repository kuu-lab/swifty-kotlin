// Private real thread/lock/parking kernels. Public API is bundled Kotlin source.
private let abi = RuntimeABISectionBuilder("AtomicfuSynchronization")

public extension RuntimeABISpec {
    static let atomicfuSynchronizationFunctions: [RuntimeABIFunctionSpec] = [
        abi.nt("__kk_atomicfu_lock_new", "ownerErrorKind"),
        abi.th("__kk_atomicfu_lock_lock", "kernel outThrown"),
        abi.th("__kk_atomicfu_lock_try_lock", "kernel timeoutNanos outThrown", raw: true),
        abi.th("__kk_atomicfu_lock_unlock", "kernel outThrown"),
        abi.nt("__kk_atomicfu_parker_new"),
        abi.th("__kk_atomicfu_parker_wait", "kernel timeoutNanos outThrown"),
        abi.th("__kk_atomicfu_parker_unpark", "kernel outThrown"),
        abi.th("__kk_atomicfu_current_parking_handle", "fnPtr closureRaw outThrown"),
    ]
}
