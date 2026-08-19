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

private let runtimeLockStorage = NSLock()
private nonisolated(unsafe) var runtimeLocks: [Int: NSRecursiveLock] = [:]

// Lazy synchronization entries are retained only while a caller owns or is
// waiting for the corresponding lock. This avoids keeping one lock per Lazy
// instance alive for the lifetime of the process.
private struct RuntimeLazyLockEntry {
    let lock: NSRecursiveLock
    var users: Int
}

private nonisolated(unsafe) var runtimeLazyLocks: [Int: RuntimeLazyLockEntry] = [:]

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

private func runtimeAcquireLazyLock(for key: Int) {
    runtimeLockStorage.lock()
    let lock: NSRecursiveLock
    if var entry = runtimeLazyLocks[key] {
        entry.users += 1
        lock = entry.lock
        runtimeLazyLocks[key] = entry
    } else {
        let newEntry = RuntimeLazyLockEntry(lock: NSRecursiveLock(), users: 1)
        lock = newEntry.lock
        runtimeLazyLocks[key] = newEntry
    }
    runtimeLockStorage.unlock()
    lock.lock()
}

private func runtimeReleaseLazyLock(for key: Int) {
    runtimeLockStorage.lock()
    guard let entry = runtimeLazyLocks[key] else {
        runtimeLockStorage.unlock()
        return
    }
    runtimeLockStorage.unlock()

    entry.lock.unlock()

    runtimeLockStorage.lock()
    guard var current = runtimeLazyLocks[key], current.lock === entry.lock else {
        runtimeLockStorage.unlock()
        return
    }
    current.users -= 1
    if current.users == 0 {
        runtimeLazyLocks.removeValue(forKey: key)
    } else {
        runtimeLazyLocks[key] = current
    }
    runtimeLockStorage.unlock()
}

// KSP-781: synchronization used by the bundled Lazy implementation.
@_cdecl("__kk_lazy_sync_lock")
public func __kk_lazy_sync_lock(_ handle: Int) -> Int {
    runtimeAcquireLazyLock(for: handle)
    return 0
}

@_cdecl("__kk_lazy_sync_unlock")
public func __kk_lazy_sync_unlock(_ handle: Int) -> Int {
    runtimeReleaseLazyLock(for: handle)
    return 0
}
