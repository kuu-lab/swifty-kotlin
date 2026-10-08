import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

// MARK: - Mutex (kotlinx.coroutines.sync.Mutex)

/// Runtime backing for `kotlinx.coroutines.sync.Mutex`.
///
/// A non-reentrant mutual exclusion lock with FIFO waiter ordering.
/// `lock()` blocks or suspends depending on the caller path, `tryLock()`
/// returns immediately, and `unlock()` transfers ownership to the oldest
/// queued waiter.
final class RuntimeMutexHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var isHeld = false
    /// Owner token recorded by `lock(owner)`/`tryLock` (`0` = anonymous lock).
    /// `null` reaching the ABI as `runtimeNullSentinelInt` is normalized to 0.
    private var owner: Int = 0
    private enum Waiter {
        case blocking(DispatchSemaphore, owner: Int)
        case coroutine(Int, owner: Int)
    }
    private var waiters = RuntimeFIFOQueue<Waiter>()

    var isLocked: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isHeld
    }

    /// Check the recorded owner by identity without changing the mutex state.
    func holdsLock(owner: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return owner != 0 && isHeld && self.owner == owner
    }

    /// Try to acquire the lock without suspending.
    /// Returns `true` if the lock was acquired, `false` otherwise.
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

    /// Acquire the mutex, blocking the calling thread until it is available.
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

    /// `lock(owner)` overload (KUU-1356). On acquisition the owner token is
    /// recorded so `unlock(owner)` can validate it. When the mutex is already
    /// held by the same `owner`, this writes an `IllegalStateException` into
    /// `outThrown` and returns 0, matching kotlinx.coroutines `lock(owner)`
    /// which fails fast instead of deadlocking on same-owner re-acquisition.
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
        waiters.enqueue(.coroutine(continuation, owner: owner))
        lock.unlock()
        return Int(bitPattern: kk_coroutine_suspended())
    }

    /// Release the lock.  If there are pending waiters, the first one is
    /// resumed on a GCD queue.
    ///
    /// Returns `0` on success. Unlocking a mutex that is not held returns an
    /// `IllegalStateException` handle, matching kotlinx.coroutines `Mutex.unlock`.
    @discardableResult
    func unlock() -> Int {
        unlock(expectedOwner: 0)
    }

    /// `unlock(owner)` overload (KUU-1356). When `expectedOwner != 0` the
    /// recorded owner must match (upstream compares by identity); on mismatch
    /// the lock stays held and an `IllegalStateException` handle is returned.
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
                if runtimeSyncContinuationIsCancelled(continuation) {
                    continue
                }
                waiterOwner = owner
                // Keep the mutex held — ownership transfers to the resumed waiter.
                self.owner = waiterOwner
                lock.unlock()
                runtimeSyncResume(continuation)
                return 0
            }
        }
        isHeld = false
        owner = 0
        lock.unlock()
        return 0
    }
}

// MARK: - Semaphore (kotlinx.coroutines.sync.Semaphore)

/// Runtime backing for `kotlinx.coroutines.sync.Semaphore`.
///
/// A counting semaphore with `permits` initial permits.  `acquire()` suspends
/// when no permits are available; `tryAcquire()` returns immediately.
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

    /// Try to acquire a permit without suspending.
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

    /// Release a permit.  If waiters are pending, the first one is resumed
    /// (or unblocked) and the permit transfers directly to it.
    ///
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

// MARK: - C ABI entry points

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

// KUU-1356: owner-token overloads of Mutex.lock/unlock
// (`suspend fun lock(owner: Any?)` / `fun unlock(owner: Any?)` upstream).
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

// MARK: - Lock.withLock { } (kotlin.concurrent.Lock.withLock)

/// Runtime backing for `kotlin.concurrent.Lock.withLock { }`.
///
/// Acquires the mutex in a blocking way using `lockBlocking()`, executes the action,
/// and releases the mutex. `Lock.withLock` is Kotlin source (KSP-677,
/// Stdlib/kotlin/concurrent/Lock.kt) delegating to this demoted bridge, so the
/// action arrives split into a function pointer / closure environment pair with an
/// `outThrown` out-parameter, matching the general closure-taking bridge ABI.
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
