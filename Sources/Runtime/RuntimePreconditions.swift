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
    let nsLock = runtimeGetOrCreateLock(for: lock)
    nsLock.lock()
    defer { nsLock.unlock() }

    var thrown = 0
    let result = runtimeInvokeClosureThunk(fnPtr: fnPtr, closureRaw: closureRaw, outThrown: &thrown)
    if thrown != 0 {
        outThrown?.pointee = thrown
        return 0
    }
    return result
}

@_cdecl("kk_reentrant_read_write_lock_read")
public func kk_reentrant_read_write_lock_read(
    _ lock: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let nsLock = runtimeGetOrCreateLock(for: lock)
    nsLock.lock()
    defer { nsLock.unlock() }

    var thrown = 0
    let result = runtimeInvokeClosureThunk(fnPtr: fnPtr, closureRaw: closureRaw, outThrown: &thrown)
    if thrown != 0 {
        outThrown?.pointee = thrown
        return 0
    }
    return result
}

private let runtimeLockStorage = NSLock()
private nonisolated(unsafe) var runtimeLocks: [Int: NSRecursiveLock] = [:]

private func runtimeGetOrCreateLock(for key: Int) -> NSRecursiveLock {
    runtimeLockStorage.lock()
    defer { runtimeLockStorage.unlock() }
    if let existing = runtimeLocks[key] {
        return existing
    }
    let newLock = NSRecursiveLock()
    runtimeLocks[key] = newLock
    return newLock
}
