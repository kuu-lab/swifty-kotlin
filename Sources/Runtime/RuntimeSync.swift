import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// A non-reentrant mutual exclusion lock with FIFO waiter ordering.
final class RuntimeMutexHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var isHeld = false
    /// Owner token recorded by `lock(owner)`/`tryLock` (`0` = anonymous lock).
    /// `null` reaching the ABI as `runtimeNullSentinelInt` is normalized to 0.
    private var owner: Int = 0
    private enum Waiter {
        case blocking(DispatchSemaphore, owner: Int)
        case coroutine(RuntimeCancellableContinuation, owner: Int)
    }
    private var waiters = RuntimeFIFOQueue<Waiter>()

    var isLocked: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isHeld
    }

    func holdsLock(owner: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return owner != 0 && isHeld && self.owner == owner
    }

    func tryLock() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if isHeld || !waiters.isEmpty {
            return false
        }
        isHeld = true
        owner = 0
        return true
    }

    /// `tryLock` outcome: acquired, busy (held or waiters queued), or held
    /// by `owner` itself — upstream throws IllegalStateException on the
    /// same-owner path instead of reporting a plain miss.
    enum TryLockOutcome {
        case acquired
        case busy
        case alreadyLockedByOwner
    }

    /// Owner-aware `tryLock`: records `owner` on success so `unlock(owner)`
    /// and `holdsLock(owner)` see the acquirer, exactly like `lock(owner)`.
    func tryLock(owner: Int) -> TryLockOutcome {
        lock.lock()
        defer { lock.unlock() }
        if isHeld {
            if owner != 0 && self.owner == owner {
                return .alreadyLockedByOwner
            }
            return .busy
        }
        if !waiters.isEmpty {
            return .busy
        }
        isHeld = true
        self.owner = owner
        return .acquired
    }

    /// Used by `__kk_lock_withLock` which runs on a regular (non-coroutine) thread.
    func lockBlocking() {
        _ = lockSync(continuation: 0)
    }

    /// Acquire the lock synchronously (non-suspend path).
    /// If the lock is free, acquires immediately and returns 0.
    /// If the lock is held and `continuation != 0`, enqueues the coroutine
    /// waiter and returns the coroutine suspended sentinel.
    /// If the lock is held and `continuation == 0`, the caller is treated as a
    /// blocking waiter and sleeps until ownership transfers.
    func lockSync(continuation: Int) -> Int {
        lockSync(continuation: continuation, owner: 0, outThrown: nil)
    }

    /// On acquisition the owner token is recorded so `unlock(owner)` can
    /// validate it. When the mutex is already held by the same `owner`, this
    /// writes an `IllegalStateException` into `outThrown` and returns 0,
    /// matching kotlinx.coroutines `lock(owner)` which fails fast instead of
    /// deadlocking on same-owner re-acquisition.
    func lockSync(continuation: Int, owner: Int, outThrown: UnsafeMutablePointer<Int>?) -> Int {
        lock.lock()
        if !isHeld && waiters.isEmpty {
            isHeld = true
            self.owner = owner
            lock.unlock()
            return 0
        }
        if isHeld, owner != 0, self.owner == owner {
            lock.unlock()
            if let outThrown {
                outThrown.pointee = runtimeAllocateIllegalStateException(
                    message: "This mutex is already locked by the specified owner"
                )
            }
            return 0
        }
        if continuation == 0 {
            let sema = DispatchSemaphore(value: 0)
            waiters.enqueue(.blocking(sema, owner: owner))
            lock.unlock()
            // A blocking (non-suspend-context) acquisition may be running on a
            // runBlocking event loop, where the holder that will release is
            // itself a coroutine queued on that loop; keep draining rather than
            // park the only thread that can run it.
            runtimeWaitDrainingEventLoop(sema)
            return 0
        }
        // Install delivery before parent cancellation can wake the caller.
        // A cancelled delivery returns any ownership transferred by unlock().
        let waiter = RuntimeCancellableContinuation(delegate: continuation)
        let result = waiter.getResult(nil)
        waiters.enqueue(.coroutine(waiter, owner: owner))
        waiter.initParent()
        lock.unlock()
        return result
    }

    /// Returns `0` on success. Unlocking a mutex that is not held returns an
    /// `IllegalStateException` handle, matching kotlinx.coroutines `Mutex.unlock`.
    @discardableResult
    func unlock() -> Int {
        unlock(expectedOwner: 0)
    }

    /// When `expectedOwner != 0` the recorded owner must match (upstream
    /// compares by identity); on mismatch the lock stays held and an
    /// `IllegalStateException` handle is returned.
    @discardableResult
    func unlock(expectedOwner: Int) -> Int {
        lock.lock()
        guard isHeld else {
            lock.unlock()
            return runtimeAllocateIllegalStateException(message: "This mutex is not locked")
        }
        if expectedOwner != 0, owner != expectedOwner {
            lock.unlock()
            return runtimeAllocateIllegalStateException(
                message: "This mutex is locked by a different owner"
            )
        }
        while let waiter = waiters.dequeue() {
            let waiterOwner: Int
            switch waiter {
            case let .blocking(sema, owner):
                waiterOwner = owner
                // Keep isHeld = true — ownership transfers to the blocking waiter.
                self.owner = waiterOwner
                lock.unlock()
                sema.signal()
                return 0
            case let .coroutine(continuation, owner):
                if continuation.stateValue == 2 {
                    continue
                }
                waiterOwner = owner
                // Keep the mutex held — ownership transfers to the resumed waiter.
                self.owner = waiterOwner
                lock.unlock()
                continuation.resume(value: 0) { [self] in
                    _ = unlock(expectedOwner: owner)
                }
                return 0
            }
        }
        isHeld = false
        owner = 0
        lock.unlock()
        return 0
    }
}

/// `release()` returns a permit and resumes one waiter (FIFO order).
final class RuntimeSemaphoreHandle: @unchecked Sendable {
    private let lock = NSLock()
    private let maxPermits: Int
    private var permits: Int
    private enum Waiter {
        case blocking(DispatchSemaphore)
        case coroutine(Int)
    }
    private var waiters = RuntimeFIFOQueue<Waiter>()

    init(permits: Int) {
        precondition(permits >= 0, "Semaphore permits must be non-negative")
        self.maxPermits = permits
        self.permits = permits
    }

    var availablePermits: Int {
        lock.lock()
        defer { lock.unlock() }
        return permits
    }

    func tryAcquire() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if permits > 0 {
            permits -= 1
            return true
        }
        return false
    }

    /// Acquire a permit synchronously (non-suspend path).
    /// If a permit is free, acquires immediately and returns 0.
    /// If none are available and `continuation != 0`, enqueues the coroutine
    /// waiter and returns the coroutine suspended sentinel.
    /// If none are available and `continuation == 0`, the caller is treated as
    /// a blocking waiter and sleeps until a permit transfers to it.
    func acquireSync(continuation: Int) -> Int {
        lock.lock()
        if permits > 0 {
            permits -= 1
            lock.unlock()
            return 0
        }
        if continuation == 0 {
            let sema = DispatchSemaphore(value: 0)
            waiters.enqueue(.blocking(sema))
            lock.unlock()
            // A blocking (non-suspend-context) acquisition may be running on a
            // runBlocking event loop, where the holder that will release is
            // itself a coroutine queued on that loop; keep draining rather than
            // park the only thread that can run it.
            runtimeWaitDrainingEventLoop(sema)
            return 0
        }
        waiters.enqueue(.coroutine(continuation))
        lock.unlock()
        return Int(bitPattern: kk_coroutine_suspended())
    }

    /// Returns `0` on success. Releasing more permits than `maxPermits`
    /// returns an `IllegalStateException` handle, matching kotlinx.coroutines
    /// `Semaphore.release`.
    @discardableResult
    func release() -> Int {
        lock.lock()
        while let waiter = waiters.dequeue() {
            switch waiter {
            case let .blocking(sema):
                // Permit transfers directly to the blocking waiter.
                lock.unlock()
                sema.signal()
                return 0
            case let .coroutine(continuation):
                if runtimeSyncContinuationIsCancelled(continuation) {
                    continue
                }
                // Permit transfers directly to the resumed waiter.
                lock.unlock()
                runtimeSyncResume(continuation)
                return 0
            }
        }
        guard permits < maxPermits else {
            lock.unlock()
            return runtimeAllocateIllegalStateException(
                message: "The number of released permits cannot be greater than \(maxPermits)"
            )
        }
        permits += 1
        lock.unlock()
        return 0
    }
}

private func runtimeSyncResume(_ continuation: Int) {
    guard continuation != 0,
          let state = runtimeContinuationState(from: continuation)
    else {
        return
    }
    state.signalResume()
}

private func runtimeSyncContinuationIsCancelled(_ continuation: Int) -> Bool {
    guard continuation != 0,
          let state = runtimeContinuationState(from: continuation),
          let job = state.jobHandle
    else {
        return false
    }
    return job.cancellationSnapshot()
}

@_cdecl("__kk_mutex_create")
public func __kk_mutex_create() -> Int {
    let mutex = RuntimeMutexHandle()
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(mutex).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

@_cdecl("kk_mutex_lock")
public func kk_mutex_lock(_ handle: Int, _ continuation: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_mutex_lock received invalid mutex handle")
    }
    let mutex = Unmanaged<RuntimeMutexHandle>.fromOpaque(ptr).takeUnretainedValue()
    return mutex.lockSync(continuation: continuation)
}

@_cdecl("kk_mutex_unlock")
public func kk_mutex_unlock(_ handle: Int, _ outThrown: UnsafeMutablePointer<Int>? = nil) -> Int {
    outThrown?.pointee = 0
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_mutex_unlock received invalid mutex handle")
    }
    let mutex = Unmanaged<RuntimeMutexHandle>.fromOpaque(ptr).takeUnretainedValue()
    let thrown = mutex.unlock()
    if thrown != 0 {
        runtimeSetThrown(outThrown, thrown)
    }
    return 0
}

/// Normalizes an `Any?` owner token crossing the ABI: Kotlin `null` may
/// arrive as 0 or the `runtimeNullSentinelInt` placeholder; both mean
/// "no owner" and disable the identity check, matching kotlinx.coroutines.
private func runtimeMutexNormalizeOwner(_ owner: Int) -> Int {
    owner == runtimeNullSentinelInt ? 0 : owner
}

// The lock bridge mirrors kk_mutex_lock's blocking/continuation ABI plus a
// trailing outThrown slot; a mutex already held by the same owner reports an
// IllegalStateException instead of deadlocking.
@_cdecl("__kk_mutex_lock_owner")
public func __kk_mutex_lock_owner(
    _ handle: Int,
    _ owner: Int,
    _ continuation: Int,
    _ outThrown: UnsafeMutablePointer<Int>? = nil
) -> Int {
    outThrown?.pointee = 0
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_mutex_lock_owner received invalid mutex handle")
    }
    let mutex = Unmanaged<RuntimeMutexHandle>.fromOpaque(ptr).takeUnretainedValue()
    return mutex.lockSync(
        continuation: continuation,
        owner: runtimeMutexNormalizeOwner(owner),
        outThrown: outThrown
    )
}

@_cdecl("__kk_mutex_unlock_owner")
public func __kk_mutex_unlock_owner(
    _ handle: Int,
    _ owner: Int,
    _ outThrown: UnsafeMutablePointer<Int>? = nil
) -> Int {
    outThrown?.pointee = 0
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_mutex_unlock_owner received invalid mutex handle")
    }
    let mutex = Unmanaged<RuntimeMutexHandle>.fromOpaque(ptr).takeUnretainedValue()
    let thrown = mutex.unlock(expectedOwner: runtimeMutexNormalizeOwner(owner))
    if thrown != 0 {
        runtimeSetThrown(outThrown, thrown)
    }
    return 0
}

@_cdecl("__kk_mutex_tryLock")
public func __kk_mutex_tryLock(_ handle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_mutex_tryLock received invalid mutex handle")
    }
    let mutex = Unmanaged<RuntimeMutexHandle>.fromOpaque(ptr).takeUnretainedValue()
    return mutex.tryLock() ? 1 : 0
}

/// `Mutex.tryLock(owner)` bridge: records `owner` on acquisition so
/// `unlock(owner)`/`holdsLock(owner)` apply; a mutex already held by the
/// same owner reports IllegalStateException like `lock(owner)` does.
@_cdecl("__kk_mutex_tryLock_owner")
public func __kk_mutex_tryLock_owner(
    _ handle: Int,
    _ owner: Int,
    _ outThrown: UnsafeMutablePointer<Int>? = nil
) -> Int {
    outThrown?.pointee = 0
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_mutex_tryLock_owner received invalid mutex handle")
    }
    let mutex = Unmanaged<RuntimeMutexHandle>.fromOpaque(ptr).takeUnretainedValue()
    switch mutex.tryLock(owner: runtimeMutexNormalizeOwner(owner)) {
    case .acquired:
        return 1
    case .busy:
        return 0
    case .alreadyLockedByOwner:
        outThrown?.pointee = runtimeAllocateIllegalStateException(
            message: "This mutex is already locked by the specified owner"
        )
        return 0
    }
}

/// `select { mutex.onLock(owner) }` poll. The acquisition is committed
/// through the clause's atomic selection: the mutex is taken only while
/// this clause owns (or wins) the select, so a losing clause never holds
/// the lock. Returns 1 when the clause owns the lock, 0 while the mutex is
/// still held elsewhere or the select decided for another clause, and 2
/// for the same-owner IllegalStateException upstream `tryLock(owner)`
/// reports. Lock order: `runtimeSelectClaimLock` → mutex lock.
@_cdecl("__kk_select_poll_lock")
public func __kk_select_poll_lock(_ handle: Int, _ clauseRaw: Int, _ owner: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle),
          let mutex = tryCast(ptr, to: RuntimeMutexHandle.self),
          let clause = resolveRuntimeHandle(clauseRaw, as: RuntimeSelectClause.self),
          let select = clause.select else {
        return 0
    }
    runtimeSelectClaimLock.lock()
    defer { runtimeSelectClaimLock.unlock() }
    if clause.delivered {
        return clause.deliveredStatus == kChannelResultSuccess ? 1 : 0
    }
    if select.isDecidedUnlocked {
        return 0
    }
    switch mutex.tryLock(owner: runtimeMutexNormalizeOwner(owner)) {
    case .acquired:
        _ = select.trySelectUnlocked(clause)
        clause.delivered = true
        clause.deliveredStatus = kChannelResultSuccess
        return 1
    case .busy:
        return 0
    case .alreadyLockedByOwner:
        return 2
    }
}

@_cdecl("__kk_mutex_isLocked")
public func __kk_mutex_isLocked(_ handle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_mutex_isLocked received invalid mutex handle")
    }
    let mutex = Unmanaged<RuntimeMutexHandle>.fromOpaque(ptr).takeUnretainedValue()
    return mutex.isLocked ? 1 : 0
}

// KUU-1659: Mutex.holdsLock(owner) observes the current owner token by
// identity, under the same lock as isHeld, without changing either value.
@_cdecl("__kk_mutex_holdsLock")
public func __kk_mutex_holdsLock(_ handle: Int, _ owner: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_mutex_holdsLock received invalid mutex handle")
    }
    let mutex = Unmanaged<RuntimeMutexHandle>.fromOpaque(ptr).takeUnretainedValue()
    return mutex.holdsLock(owner: runtimeMutexNormalizeOwner(owner)) ? 1 : 0
}

@_cdecl("__kk_semaphore_create")
public func __kk_semaphore_create(_ permits: Int) -> Int {
    let semaphore = RuntimeSemaphoreHandle(permits: permits)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(semaphore).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

@_cdecl("kk_semaphore_acquire")
public func kk_semaphore_acquire(_ handle: Int, _ continuation: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_semaphore_acquire received invalid semaphore handle")
    }
    let semaphore = Unmanaged<RuntimeSemaphoreHandle>.fromOpaque(ptr).takeUnretainedValue()
    return semaphore.acquireSync(continuation: continuation)
}

@_cdecl("kk_semaphore_release")
public func kk_semaphore_release(_ handle: Int, _ outThrown: UnsafeMutablePointer<Int>? = nil) -> Int {
    outThrown?.pointee = 0
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_semaphore_release received invalid semaphore handle")
    }
    let semaphore = Unmanaged<RuntimeSemaphoreHandle>.fromOpaque(ptr).takeUnretainedValue()
    let thrown = semaphore.release()
    if thrown != 0 {
        runtimeSetThrown(outThrown, thrown)
    }
    return 0
}

@_cdecl("__kk_semaphore_tryAcquire")
public func __kk_semaphore_tryAcquire(_ handle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_semaphore_tryAcquire received invalid semaphore handle")
    }
    let semaphore = Unmanaged<RuntimeSemaphoreHandle>.fromOpaque(ptr).takeUnretainedValue()
    return semaphore.tryAcquire() ? 1 : 0
}

@_cdecl("__kk_semaphore_availablePermits")
public func __kk_semaphore_availablePermits(_ handle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_semaphore_availablePermits received invalid semaphore handle")
    }
    let semaphore = Unmanaged<RuntimeSemaphoreHandle>.fromOpaque(ptr).takeUnretainedValue()
    return semaphore.availablePermits
}

// KSP-677: kk_mutex_withLock and kk_semaphore_withPermit are removed. The
// public helpers Mutex.withLock / Semaphore.withPermit are Kotlin source
// (Stdlib/kotlinx/coroutines/sync/Sync.kt) composing the c-soft kernel
// primitives lock()/unlock() and acquire()/release().

/// `Lock.withLock` is Kotlin source (KSP-677, Stdlib/kotlin/concurrent/Lock.kt)
/// delegating to this demoted bridge, so the action arrives split into a
/// function pointer / closure environment pair with an `outThrown`
/// out-parameter, matching the general closure-taking bridge ABI.
@_cdecl("__kk_lock_withLock")
public func kk_lock_bridge_withLock(
    _ handle: Int,
    _ actionFnPtr: Int,
    _ actionClosureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_lock_withLock received invalid mutex handle")
    }
    let mutex = Unmanaged<RuntimeMutexHandle>.fromOpaque(ptr).takeUnretainedValue()

    mutex.lockBlocking()
    defer { mutex.unlock() }

    var thrown = 0
    let result = runtimeInvokeClosureThunk(fnPtr: actionFnPtr, closureRaw: actionClosureRaw, outThrown: &thrown)
    if thrown != 0 {
        return handleCollectionLambdaThrow(thrown, outThrown)
    }
    return result
}
