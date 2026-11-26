import Foundation

@_cdecl("__kk_synchronized")
public func __kk_synchronized(_ lock: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    return runtimeThrowingBridge(outThrown) {
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
}

private let runtimeLockStorage = NSLock()
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


@_cdecl("__kk_lazy_sync_lock")
public func __kk_lazy_sync_lock(_ handle: Int) -> Int {
    _ = runtimeAcquireLock(for: handle)
    return 0
}

@_cdecl("__kk_lazy_sync_unlock")
public func __kk_lazy_sync_unlock(_ handle: Int) -> Int {
    runtimeLockStorage.lock()
    let lock = runtimeLocks[handle]?.lock
    runtimeLockStorage.unlock()
    if let lock {
        runtimeReleaseLock(for: handle, lock: lock)
    }
    return 0
}
