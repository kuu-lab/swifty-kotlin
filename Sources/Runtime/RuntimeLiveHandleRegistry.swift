import Foundation

/// Liveness registry for the coroutine runtime handles that outlive their owner's
/// last reference: continuations, scopes, jobs and async tasks.
///
/// These handles travel through generated code as raw pointer-sized integers and
/// are routinely resolved again *after* the runtime has released them
/// (`kk_coroutine_state_exit` releases a continuation, `waitForChildren`
/// releases child job/task handles). Casting such a stale pointer reads freed
/// memory, and once the allocator recycles the address the cast succeeds against
/// an unrelated live object of the same type — one coroutine then mutates
/// another's state (e.g. a producer's launcher arguments), which surfaces far
/// away as an "invalid handle" panic.
///
/// `objectPointers` cannot answer "is this handle still alive?" for these types:
/// `kk_coroutine_state_exit` unregisters a continuation while the suspend-entry
/// loop still holds a reference to it, so membership there means "not yet
/// exited", not "not yet freed". This registry records an address in `init` and
/// drops it in `deinit`, so it is populated exactly while the object is alive.
enum RuntimeLiveHandles {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var addresses: Set<UInt> = []

    /// Record `object`'s address as live. Call from the designated initializer.
    static func register(_ object: AnyObject) {
        let key = address(of: object)
        lock.lock()
        addresses.insert(key)
        lock.unlock()
    }

    /// Drop `object`'s address. Call from `deinit`, before the memory is reused.
    static func unregister(_ object: AnyObject) {
        let key = address(of: object)
        lock.lock()
        addresses.remove(key)
        lock.unlock()
    }

    static func isLive(_ pointer: UnsafeMutableRawPointer) -> Bool {
        let key = UInt(bitPattern: pointer)
        lock.lock()
        defer { lock.unlock() }
        return addresses.contains(key)
    }

    private static func address(of object: AnyObject) -> UInt {
        UInt(bitPattern: Unmanaged.passUnretained(object).toOpaque())
    }
}

/// Resolve a raw handle to a live coroutine runtime object of the given type.
/// Returns nil when the handle is zero, refers to an object that has already
/// been deallocated, or refers to a live object of a different type.
func resolveLiveRuntimeHandle<T: AnyObject>(_ rawValue: Int, as _: T.Type) -> T? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: rawValue),
          RuntimeLiveHandles.isLive(ptr)
    else {
        return nil
    }
    return tryCast(ptr, to: T.self)
}
