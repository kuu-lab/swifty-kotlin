import Dispatch
import Foundation
@testable import Runtime
import Testing

private let runtimeSemaphoreWithPermitObservedAvailableInsideLock = NSLock()
nonisolated(unsafe) private var _runtimeSemaphoreWithPermitObservedAvailableInside = -1

private var runtimeSemaphoreWithPermitObservedAvailableInside: Int {
    get {
        runtimeSemaphoreWithPermitObservedAvailableInsideLock.lock()
        defer { runtimeSemaphoreWithPermitObservedAvailableInsideLock.unlock() }
        return _runtimeSemaphoreWithPermitObservedAvailableInside
    }
    set {
        runtimeSemaphoreWithPermitObservedAvailableInsideLock.lock()
        defer { runtimeSemaphoreWithPermitObservedAvailableInsideLock.unlock() }
        _runtimeSemaphoreWithPermitObservedAvailableInside = newValue
    }
}

@_cdecl("runtime_semaphore_with_permit_action")
private func runtime_semaphore_with_permit_action(_ envRaw: Int) -> Int {
    runtimeSemaphoreWithPermitObservedAvailableInside = kk_semaphore_availablePermits(envRaw)
    return 99
}

private let runtimeSemaphoreWithPermitContentionResultLock = NSLock()
nonisolated(unsafe) private var _runtimeSemaphoreWithPermitContentionResult = -1

private var runtimeSemaphoreWithPermitContentionResult: Int {
    get {
        runtimeSemaphoreWithPermitContentionResultLock.lock()
        defer { runtimeSemaphoreWithPermitContentionResultLock.unlock() }
        return _runtimeSemaphoreWithPermitContentionResult
    }
    set {
        runtimeSemaphoreWithPermitContentionResultLock.lock()
        defer { runtimeSemaphoreWithPermitContentionResultLock.unlock() }
        _runtimeSemaphoreWithPermitContentionResult = newValue
    }
}

private func resetRuntimeSemaphoreTestState() {
    runtimeSemaphoreWithPermitObservedAvailableInside = -1
    runtimeSemaphoreWithPermitContentionResult = -1
}

@Suite(.runtimeIsolation(.gcOnly, resetAdditionalState: resetRuntimeSemaphoreTestState))
struct RuntimeSemaphoreTests {
    @Test func semaphoreCreateAcquireTryAcquireAndRelease() {
        let handle = kk_semaphore_create(2)
        #expect(handle != 0)

        #expect(kk_semaphore_availablePermits(handle) == 2)
        #expect(kk_semaphore_acquire(handle, 0) == 0)
        #expect(kk_semaphore_availablePermits(handle) == 1)
        #expect(kk_semaphore_tryAcquire(handle) == 1)
        #expect(kk_semaphore_availablePermits(handle) == 0)
        #expect(kk_semaphore_tryAcquire(handle) == 0)
        #expect(kk_semaphore_release(handle) == 0)
        #expect(kk_semaphore_availablePermits(handle) == 1)
        #expect(kk_semaphore_release(handle) == 0)
        #expect(kk_semaphore_availablePermits(handle) == 2)
    }

    @Test func semaphoreWithPermitAcquiresRunsActionAndReleases() {
        let handle = kk_semaphore_create(1)
        #expect(handle != 0)

        let actionFn = unsafeBitCast(
            runtime_semaphore_with_permit_action as @convention(c) (Int) -> Int,
            to: Int.self
        )
        let withPermitResult = kk_semaphore_withPermit(handle, actionFn, handle, 0)
        #expect(withPermitResult == 99)
        // The permit is held (available == 0) while the action runs.
        #expect(runtimeSemaphoreWithPermitObservedAvailableInside == 0)
        // The permit must be returned once withPermit completes.
        #expect(kk_semaphore_availablePermits(handle) == 1)
        #expect(kk_semaphore_tryAcquire(handle) == 1)
        #expect(kk_semaphore_release(handle) == 0)
    }

    @Test func semaphoreAcquireBlocksUntilPermitAvailable() {
        let handle = kk_semaphore_create(1)
        #expect(handle != 0)
        #expect(kk_semaphore_acquire(handle, 0) == 0)

        let waiterAcquired = DispatchSemaphore(value: 0)
        let waiterDone = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            #expect(
                kk_semaphore_acquire(handle, 0) == 0,
                "a blocking acquire must return 0 once unblocked"
            )
            waiterAcquired.signal()
            _ = kk_semaphore_release(handle)
            waiterDone.signal()
        }

        // The waiter must genuinely block while the only permit is held by the
        // main thread — a non-blocking (buggy) acquire would signal immediately.
        #expect(
            waiterAcquired.wait(timeout: .now() + 0.2) == .timedOut,
            "waiter must not acquire while the permit is held"
        )

        #expect(kk_semaphore_release(handle) == 0)
        #expect(
            waiterAcquired.wait(timeout: .now() + 2) == .success,
            "waiter must acquire once the permit is released"
        )
        #expect(waiterDone.wait(timeout: .now() + 2) == .success)
        #expect(kk_semaphore_availablePermits(handle) == 1)
    }

    @Test func semaphoreWithPermitBlocksThenRunsActionUnderContention() {
        let handle = kk_semaphore_create(1)
        #expect(handle != 0)
        #expect(kk_semaphore_acquire(handle, 0) == 0, "main thread takes the only permit")

        let actionFn = unsafeBitCast(
            runtime_semaphore_with_permit_action as @convention(c) (Int) -> Int,
            to: Int.self
        )

        let waiterStarted = DispatchSemaphore(value: 0)
        let waiterDone = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            waiterStarted.signal()
            runtimeSemaphoreWithPermitContentionResult = kk_semaphore_withPermit(handle, actionFn, handle, 0)
            waiterDone.signal()
        }
        #expect(waiterStarted.wait(timeout: .now() + 2) == .success)

        // With only one permit held by the main thread, the contended withPermit
        // call must block rather than silently skip the action and return early.
        #expect(
            waiterDone.wait(timeout: .now() + 0.2) == .timedOut,
            "withPermit must block while contended"
        )

        #expect(kk_semaphore_release(handle) == 0)
        #expect(waiterDone.wait(timeout: .now() + 2) == .success)

        // The action must have actually run once unblocked, and the permit it
        // held must be returned afterward (no leak).
        #expect(
            runtimeSemaphoreWithPermitContentionResult == 99,
            "the contended call must still run the action and return its result"
        )
        #expect(
            runtimeSemaphoreWithPermitObservedAvailableInside == 0,
            "the action must observe the permit as held while it runs"
        )
        #expect(
            kk_semaphore_availablePermits(handle) == 1,
            "the permit must not leak after the contended withPermit completes"
        )
    }
}
