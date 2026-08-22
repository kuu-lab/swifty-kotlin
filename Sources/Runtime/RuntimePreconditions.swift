import Foundation

// MARK: - synchronized (STDLIB-325 / KSP-618)

/// Runtime support for kotlin.synchronized(lock, block).
/// Uses NSRecursiveLock-based per-object locking. The lock argument is used as a key
/// to obtain a reentrant lock, and the block lambda is executed under that lock.
/// The public `synchronized` layer is Kotlin source (Stdlib/kotlin/Synchronized.kt)
/// delegating to this demoted bridge.
@_cdecl("__kk_synchronized")
public func __kk_synchronized(_ lock: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let nsLock = runtimeAcquireLock(for: lock)
    defer { runtimeReleaseLock(for: lock, lock: nsLock) }

    var thrown = 0
    let result = runtimeInvokeClosureThunk(fnPtr: fnPtr, closureRaw: closureRaw, outThrown: &thrown)
    if thrown != 0 {
        outThrown?.pointee = thrown
        return 0
    }
    return result
}

private let runtimeLockStorage = NSLock()
// Lock entries are retained only while a caller owns or is waiting for the
// corresponding lock. Both `synchronized(lock)` and `lazy(lock)` use this
// table so they honor Kotlin's shared-monitor semantics without leaking one
// lock per object for the lifetime of the process.
private struct RuntimeLockEntry {
    let lock: NSRecursiveLock
    var users: Int
}

private nonisolated(unsafe) var runtimeLocks: [Int: RuntimeLockEntry] = [:]

func runtimeAcquireLock(for key: Int) -> NSRecursiveLock {
    runtimeLockStorage.lock()
    let lock: NSRecursiveLock
    if var entry = runtimeLocks[key] {
        entry.users += 1
        lock = entry.lock
        runtimeLocks[key] = entry
    } else {
        let newEntry = RuntimeLockEntry(lock: NSRecursiveLock(), users: 1)
        lock = newEntry.lock
        runtimeLocks[key] = newEntry
    }
    runtimeLockStorage.unlock()
    lock.lock()
    return lock
}

func runtimeReleaseLock(for key: Int, lock: NSRecursiveLock) {
    lock.unlock()
    runtimeLockStorage.lock()
    guard var entry = runtimeLocks[key], entry.lock === lock else {
        runtimeLockStorage.unlock()
        return
    }
    entry.users -= 1
    if entry.users == 0 {
        runtimeLocks.removeValue(forKey: key)
    } else {
        runtimeLocks[key] = entry
    }
    runtimeLockStorage.unlock()
}

func runtimeWithLock<T>(for key: Int, _ body: () -> T) -> T {
    let lock = runtimeAcquireLock(for: key)
    defer { runtimeReleaseLock(for: key, lock: lock) }
    return body()
}

// KSP-781: synchronization used by the bundled Lazy implementation.
@_cdecl("__kk_lazy_sync_lock")
public func __kk_lazy_sync_lock(_ handle: Int) -> Int {
    _ = runtimeAcquireLock(for: handle)
    return 0
}

@_cdecl("__kk_lazy_sync_unlock")
public func __kk_lazy_sync_unlock(_ handle: Int) -> Int {
    // The bridge ABI carries only the key. The shared lock table guarantees
    // that the current key resolves to the same lock while it is held.
    runtimeLockStorage.lock()
    let lock = runtimeLocks[handle]?.lock
    runtimeLockStorage.unlock()
    if let lock {
        runtimeReleaseLock(for: handle, lock: lock)
    }
    return 0
}
