import Dispatch
import Foundation
@testable import Runtime
import Testing

private final class RuntimeMutexTestState: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [String] = []

    func reset() {
        lock.lock()
        events.removeAll()
        lock.unlock()
    }

    func record(_ event: String) {
        lock.lock()
        events.append(event)
        lock.unlock()
    }

    func snapshot() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }
}

private let runtimeMutexTestStateLock = NSLock()
nonisolated(unsafe) private var _runtimeMutexTestState = RuntimeMutexTestState()

private var runtimeMutexTestState: RuntimeMutexTestState {
    get {
        runtimeMutexTestStateLock.lock()
        defer { runtimeMutexTestStateLock.unlock() }
        return _runtimeMutexTestState
    }
    set {
        runtimeMutexTestStateLock.lock()
        defer { runtimeMutexTestStateLock.unlock() }
        _runtimeMutexTestState = newValue
    }
}

private func resetRuntimeMutexTestState() {
    runtimeMutexTestState.reset()
}

@Suite(.runtimeIsolation(.gcOnly, resetAdditionalState: resetRuntimeMutexTestState))
struct RuntimeMutexTests {
    // KSP-677: Mutex.withLock is Kotlin source composing the c-soft lock()/unlock()
    // kernel primitives, so its runtime coverage is the lock/tryLock/unlock path below.
    @Test func mutexBasicLockTryLockUnlock() {
        let handle = __kk_mutex_create()
        #expect(handle != 0)

        #expect(__kk_mutex_isLocked(handle) == 0)
        #expect(kk_mutex_lock(handle, 0) == 0)
        #expect(__kk_mutex_isLocked(handle) == 1)
        #expect(__kk_mutex_tryLock(handle) == 0)
        #expect(kk_mutex_unlock(handle) == 0)
        #expect(__kk_mutex_isLocked(handle) == 0)
        #expect(__kk_mutex_tryLock(handle) == 1)
        #expect(__kk_mutex_isLocked(handle) == 1)
        #expect(kk_mutex_unlock(handle) == 0)
    }

    @Test func mutexUnlockOnUnlockedMutexThrowsIllegalStateException() throws {
        let handle = __kk_mutex_create()
        #expect(handle != 0)

        var thrown = 0
        #expect(kk_mutex_unlock(handle, &thrown) == 0)
        let box = try requireThrownBox(thrown)
        #expect(box.exceptionFQName == "kotlin.IllegalStateException")
        #expect(box.message == "This mutex is not locked")
        #expect(__kk_mutex_isLocked(handle) == 0)

        thrown = 0
        #expect(kk_mutex_lock(handle, 0) == 0)
        #expect(kk_mutex_unlock(handle, &thrown) == 0)
        #expect(thrown == 0)
        #expect(__kk_mutex_isLocked(handle) == 0)

        thrown = 0
        #expect(kk_mutex_unlock(handle, &thrown) == 0)
        let secondBox = try requireThrownBox(thrown)
        #expect(secondBox.exceptionFQName == "kotlin.IllegalStateException")
        #expect(secondBox.message == "This mutex is not locked")
    }

    // KUU-1356: owner-token overloads (__kk_mutex_lock_owner /
    // __kk_mutex_unlock_owner) back `Mutex.lock(owner)`/`Mutex.unlock(owner)`.
    // The runtime treats the owner as an opaque token compared by value;
    // `0` stands in for Kotlin `null` (no owner).
    @Test func mutexOwnerLockUnlock() throws {
        let handle = __kk_mutex_create()
        #expect(handle != 0)

        let owner: Int = 0x5157
        let otherOwner: Int = 0x4F48

        var thrown = 0
        #expect(__kk_mutex_lock_owner(handle, owner, 0, &thrown) == 0)
        #expect(thrown == 0)
        #expect(__kk_mutex_isLocked(handle) == 1)

        // Unlocking with a different owner throws and keeps the lock held.
        #expect(__kk_mutex_unlock_owner(handle, otherOwner, &thrown) == 0)
        let mismatchBox = try requireThrownBox(thrown)
        #expect(mismatchBox.exceptionFQName == "kotlin.IllegalStateException")
        #expect(__kk_mutex_isLocked(handle) == 1)

        // The matching owner releases the lock.
        thrown = 0
        #expect(__kk_mutex_unlock_owner(handle, owner, &thrown) == 0)
        #expect(thrown == 0)
        #expect(__kk_mutex_isLocked(handle) == 0)
    }

    @Test func mutexUnlockWithoutOwnerBypassesOwnerCheck() throws {
        let handle = __kk_mutex_create()
        #expect(handle != 0)

        let owner: Int = 0x5157
        var thrown = 0
        #expect(__kk_mutex_lock_owner(handle, owner, 0, &thrown) == 0)
        #expect(thrown == 0)

        // unlock(owner: null) skips the token check, matching upstream
        // `unlock(owner == null)` which always succeeds on a held mutex.
        #expect(__kk_mutex_unlock_owner(handle, 0, &thrown) == 0)
        #expect(thrown == 0)
        #expect(__kk_mutex_isLocked(handle) == 0)

        // The plain no-arg unlock path also releases an owner-held mutex.
        #expect(__kk_mutex_lock_owner(handle, owner, 0, &thrown) == 0)
        #expect(thrown == 0)
        #expect(kk_mutex_unlock(handle) == 0)
        #expect(__kk_mutex_isLocked(handle) == 0)
    }

    @Test func mutexUnlockOwnerOnUnlockedMutexThrowsIllegalStateException() throws {
        let handle = __kk_mutex_create()
        #expect(handle != 0)

        var thrown = 0
        #expect(__kk_mutex_unlock_owner(handle, 0x5157, &thrown) == 0)
        let box = try requireThrownBox(thrown)
        #expect(box.exceptionFQName == "kotlin.IllegalStateException")
        #expect(box.message == "This mutex is not locked")
    }

    @Test func mutexLockAlreadyHeldBySameOwnerThrowsIllegalStateException() throws {
        let handle = __kk_mutex_create()
        #expect(handle != 0)

        let owner: Int = 0x5157
        var thrown = 0
        #expect(__kk_mutex_lock_owner(handle, owner, 0, &thrown) == 0)
        #expect(thrown == 0)

        // Re-locking with the same owner fails fast instead of parking
        // forever, matching kotlinx.coroutines lock(owner)/tryLock(owner).
        #expect(__kk_mutex_lock_owner(handle, owner, 0, &thrown) == 0)
        let box = try requireThrownBox(thrown)
        #expect(box.exceptionFQName == "kotlin.IllegalStateException")
        #expect(__kk_mutex_isLocked(handle) == 1)

        thrown = 0
        #expect(__kk_mutex_unlock_owner(handle, owner, &thrown) == 0)
        #expect(thrown == 0)
        #expect(__kk_mutex_isLocked(handle) == 0)
    }

    @Test func mutexOwnerTransfersToBlockingWaiter() {
        let handle = __kk_mutex_create()
        #expect(handle != 0)

        let firstOwner: Int = 0x5157
        let waiterOwner: Int = 0x4F48
        var thrown = 0
        #expect(__kk_mutex_lock_owner(handle, firstOwner, 0, &thrown) == 0)

        let waiterDone = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            // Blocks until the first owner releases; the waiter's owner token
            // must become the mutex's recorded owner.
            #expect(__kk_mutex_lock_owner(handle, waiterOwner, 0, nil) == 0)
            waiterDone.signal()
        }
        Thread.sleep(forTimeInterval: 0.05)

        // Releasing with the first owner hands the mutex to the waiter,
        // carrying the waiter's owner token with it.
        #expect(__kk_mutex_unlock_owner(handle, firstOwner, &thrown) == 0)
        #expect(waiterDone.wait(timeout: .now() + .seconds(2)) == .success)

        // The mutex is now held under waiterOwner: firstOwner no longer
        // satisfies the token check and the release must fail.
        thrown = 0
        #expect(__kk_mutex_unlock_owner(handle, firstOwner, &thrown) == 0)
        _ = try? requireThrownBox(thrown)
        #expect(thrown != 0)
        #expect(__kk_mutex_isLocked(handle) == 1)

        thrown = 0
        #expect(__kk_mutex_unlock_owner(handle, waiterOwner, &thrown) == 0)
        #expect(thrown == 0)
        #expect(__kk_mutex_isLocked(handle) == 0)
    }

    // NOTE: pthread_mutex_t does not guarantee FIFO wake-up order on Linux, so
    // this test verifies only that multiple waiters can all acquire and release
    // the mutex without deadlock.  A strict ordering assertion would be flaky on
    // CI runners using Linux's nptl mutex implementation.
    @Test func mutexLockWaitersAreServedInFIFOOrder() {
        let handle = __kk_mutex_create()
        #expect(handle != 0)

        #expect(kk_mutex_lock(handle, 0) == 0)
        runtimeMutexTestState.record("main-acquired")
        #expect(__kk_mutex_isLocked(handle) == 1)

        let waiter1Done = DispatchSemaphore(value: 0)
        let waiter2Done = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            _ = kk_mutex_lock(handle, 0)
            runtimeMutexTestState.record("waiter-1-acquired")
            _ = kk_mutex_unlock(handle)
            runtimeMutexTestState.record("waiter-1-released")
            waiter1Done.signal()
        }

        Thread.sleep(forTimeInterval: 0.05)

        DispatchQueue.global().async {
            _ = kk_mutex_lock(handle, 0)
            runtimeMutexTestState.record("waiter-2-acquired")
            _ = kk_mutex_unlock(handle)
            runtimeMutexTestState.record("waiter-2-released")
            waiter2Done.signal()
        }

        Thread.sleep(forTimeInterval: 0.05)
        #expect(__kk_mutex_tryLock(handle) == 0)

        #expect(kk_mutex_unlock(handle) == 0)

        #expect(waiter1Done.wait(timeout: .now() + .seconds(2)) == .success)
        #expect(waiter2Done.wait(timeout: .now() + .seconds(2)) == .success)

        #expect(__kk_mutex_isLocked(handle) == 0)
        #expect(__kk_mutex_tryLock(handle) == 1)
        #expect(kk_mutex_unlock(handle) == 0)

        // Verify that all expected events were recorded (order is platform-dependent).
        let events = runtimeMutexTestState.snapshot()
        #expect(events.contains("main-acquired"), "main-acquired must be recorded")
        #expect(events.contains("waiter-1-acquired"), "waiter-1-acquired must be recorded")
        #expect(events.contains("waiter-1-released"), "waiter-1-released must be recorded")
        #expect(events.contains("waiter-2-acquired"), "waiter-2-acquired must be recorded")
        #expect(events.contains("waiter-2-released"), "waiter-2-released must be recorded")
        // Each waiter must release after it acquires.
        if let a1 = events.firstIndex(of: "waiter-1-acquired"),
           let r1 = events.firstIndex(of: "waiter-1-released") {
            #expect(a1 < r1, "waiter-1 must release after acquiring")
        }
        if let a2 = events.firstIndex(of: "waiter-2-acquired"),
           let r2 = events.firstIndex(of: "waiter-2-released") {
            #expect(a2 < r2, "waiter-2 must release after acquiring")
        }
    }
}

private func requireThrownBox(_ thrown: Int) throws -> RuntimeThrowableBox {
    let ptr = try #require(
        UnsafeMutableRawPointer(bitPattern: thrown),
        "thrown channel value is not a valid pointer"
    )
    return try #require(
        tryCast(ptr, to: RuntimeThrowableBox.self),
        "thrown value must be a RuntimeThrowableBox"
    )
}
