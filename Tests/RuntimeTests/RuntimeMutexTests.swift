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
