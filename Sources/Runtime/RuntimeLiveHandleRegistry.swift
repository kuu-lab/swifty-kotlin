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
/// exited", not "not yet freed". This registry records an entry in `init` and
/// drops it in `deinit`, so it is populated exactly while the object is alive.
///
/// Each entry holds the object *weakly*. Resolution looks the address up and
/// loads that weak reference while holding the same lock that serializes
/// register/unregister: a weak load acquires a strong reference atomically
/// with respect to deallocation, so it yields either the live object or nil —
/// never a pointer into freed memory. That closes the TOCTOU window a
/// membership-check-then-unretained-cast leaves open, where another thread
/// could drop the last retain (and recycle the address) between the check and
/// the cast. The resolved strong reference keeps the object alive until the
/// caller's operation completes, and a stale handle can only ever resolve to a
/// currently-registered, correctly-typed live object.
enum RuntimeLiveHandles {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var entries: [UInt: WeakEntry] = [:]

    /// Weak box tying a registered address to its object. Loading `object`
    /// takes a strong reference atomically with respect to deallocation.
    private final class WeakEntry {
        weak var object: AnyObject?

        init(_ object: AnyObject) {
            self.object = object
        }
    }

    /// Record `object`'s address as live. Call from the designated initializer.
    static func register(_ object: AnyObject) {
        let key = address(of: object)
        lock.lock()
        entries[key] = WeakEntry(object)
        lock.unlock()
    }

    /// Drop `object`'s address. Call from `deinit`, before the memory is reused.
    /// The entry is removed unconditionally: until `deinit` finishes the memory
    /// cannot be recycled, so no other object's entry can live at this address.
    static func unregister(_ object: AnyObject) {
        let key = address(of: object)
        lock.lock()
        entries.removeValue(forKey: key)
        lock.unlock()
    }

    /// Resolve `pointer` to its registered object while holding the registry
    /// lock, returning a strong reference that keeps the object alive for the
    /// rest of the caller's operation. Returns nil when the address is not
    /// registered or the object has already begun deinitializing (weak loads
    /// on a deallocating object return nil).
    static func resolve(_ pointer: UnsafeMutableRawPointer) -> AnyObject? {
        let key = UInt(bitPattern: pointer)
        lock.lock()
        defer { lock.unlock() }
        return entries[key]?.object
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
          let object = RuntimeLiveHandles.resolve(ptr)
    else {
        return nil
    }
    return object as? T
}
