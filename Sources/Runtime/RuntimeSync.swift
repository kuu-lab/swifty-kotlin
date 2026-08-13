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
    private enum Waiter {
        case blocking(DispatchSemaphore)
        case coroutine(Int)
    }
    private var waiters: [Waiter] = []

    var isLocked: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isHeld
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
        lock.lock()
        if !isHeld && waiters.isEmpty {
            isHeld = true
            lock.unlock()
            return 0
        }
        if continuation == 0 {
            let sema = DispatchSemaphore(value: 0)
            waiters.append(.blocking(sema))
            lock.unlock()
            sema.wait()
            return 0
        }
        waiters.append(.coroutine(continuation))
        lock.unlock()
        return Int(bitPattern: kk_coroutine_suspended())
    }

    /// Release the lock.  If there are pending waiters, the first one is
    /// resumed on a GCD queue.
    func unlock() {
        lock.lock()
        guard isHeld else {
            lock.unlock()
            fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: Mutex.unlock() called on an unlocked mutex")
        }
        while !waiters.isEmpty {
            let waiter = waiters.removeFirst()
            switch waiter {
            case let .blocking(sema):
                // Keep isHeld = true — ownership transfers to the blocking waiter.
                lock.unlock()
                sema.signal()
                return
            case let .coroutine(continuation):
                if runtimeSyncContinuationIsCancelled(continuation) {
                    continue
                }
                // Keep the mutex held — ownership transfers to the resumed waiter.
                lock.unlock()
                runtimeSyncResume(continuation)
                return
            }
        }
        isHeld = false
        lock.unlock()
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
    private var waiters: [Waiter] = []

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
            waiters.append(.blocking(sema))
            lock.unlock()
            sema.wait()
            return 0
        }
        waiters.append(.coroutine(continuation))
        lock.unlock()
        return Int(bitPattern: kk_coroutine_suspended())
    }

    /// Release a permit.  If waiters are pending, the first one is resumed
    /// (or unblocked) and the permit transfers directly to it.
    func release() {
        lock.lock()
        while !waiters.isEmpty {
            let waiter = waiters.removeFirst()
            switch waiter {
            case let .blocking(sema):
                // Permit transfers directly to the blocking waiter.
                lock.unlock()
                sema.signal()
                return
            case let .coroutine(continuation):
                if runtimeSyncContinuationIsCancelled(continuation) {
                    continue
                }
                // Permit transfers directly to the resumed waiter.
                lock.unlock()
                runtimeSyncResume(continuation)
                return
            }
        }
        guard permits < maxPermits else {
            lock.unlock()
            fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: Semaphore.release() exceeded acquired permits")
        }
        permits += 1
        lock.unlock()
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
public func kk_mutex_unlock(_ handle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_mutex_unlock received invalid mutex handle")
    }
    let mutex = Unmanaged<RuntimeMutexHandle>.fromOpaque(ptr).takeUnretainedValue()
    mutex.unlock()
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
public func kk_semaphore_release(_ handle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_semaphore_release received invalid semaphore handle")
    }
    let semaphore = Unmanaged<RuntimeSemaphoreHandle>.fromOpaque(ptr).takeUnretainedValue()
    semaphore.release()
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
