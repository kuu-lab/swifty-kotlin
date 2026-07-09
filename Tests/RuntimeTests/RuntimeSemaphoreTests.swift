import Dispatch
@testable import Runtime
import XCTest

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

final class RuntimeSemaphoreTests: IsolatedRuntimeXCTestCase {
    // swiftlint:disable:next static_over_final_class
    override class var requiredLockSet: RuntimeLockSet { .gcOnly }
    override func resetIsolatedRuntimeTestState() {
        runtimeSemaphoreWithPermitObservedAvailableInside = -1
        runtimeSemaphoreWithPermitContentionResult = -1
    }

    func testSemaphoreCreateAcquireTryAcquireAndRelease() {
        let handle = kk_semaphore_create(2)
        XCTAssertNotEqual(handle, 0)

        XCTAssertEqual(kk_semaphore_availablePermits(handle), 2)
        XCTAssertEqual(kk_semaphore_acquire(handle, 0), 0)
        XCTAssertEqual(kk_semaphore_availablePermits(handle), 1)
        XCTAssertEqual(kk_semaphore_tryAcquire(handle), 1)
        XCTAssertEqual(kk_semaphore_availablePermits(handle), 0)
        XCTAssertEqual(kk_semaphore_tryAcquire(handle), 0)
        XCTAssertEqual(kk_semaphore_release(handle), 0)
        XCTAssertEqual(kk_semaphore_availablePermits(handle), 1)
        XCTAssertEqual(kk_semaphore_release(handle), 0)
        XCTAssertEqual(kk_semaphore_availablePermits(handle), 2)
    }

    func testSemaphoreWithPermitAcquiresRunsActionAndReleases() {
        let handle = kk_semaphore_create(1)
        XCTAssertNotEqual(handle, 0)

        let actionFn = unsafeBitCast(
            runtime_semaphore_with_permit_action as @convention(c) (Int) -> Int,
            to: Int.self
        )
        let withPermitResult = kk_semaphore_withPermit(handle, actionFn, handle, 0)
        XCTAssertEqual(withPermitResult, 99)
        // The permit is held (available == 0) while the action runs.
        XCTAssertEqual(runtimeSemaphoreWithPermitObservedAvailableInside, 0)
        // The permit must be returned once withPermit completes.
        XCTAssertEqual(kk_semaphore_availablePermits(handle), 1)
        XCTAssertEqual(kk_semaphore_tryAcquire(handle), 1)
        XCTAssertEqual(kk_semaphore_release(handle), 0)
    }

    func testSemaphoreAcquireBlocksUntilPermitAvailable() {
        let handle = kk_semaphore_create(1)
        XCTAssertNotEqual(handle, 0)
        XCTAssertEqual(kk_semaphore_acquire(handle, 0), 0)

        let waiterAcquired = DispatchSemaphore(value: 0)
        let waiterDone = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            XCTAssertEqual(kk_semaphore_acquire(handle, 0), 0, "a blocking acquire must return 0 once unblocked")
            waiterAcquired.signal()
            _ = kk_semaphore_release(handle)
            waiterDone.signal()
        }

        // The waiter must genuinely block while the only permit is held by the
        // main thread — a non-blocking (buggy) acquire would signal immediately.
        XCTAssertEqual(waiterAcquired.wait(timeout: .now() + 0.2), .timedOut, "waiter must not acquire while the permit is held")

        XCTAssertEqual(kk_semaphore_release(handle), 0)
        XCTAssertEqual(waiterAcquired.wait(timeout: .now() + 2), .success, "waiter must acquire once the permit is released")
        XCTAssertEqual(waiterDone.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(kk_semaphore_availablePermits(handle), 1)
    }

    func testSemaphoreWithPermitBlocksThenRunsActionUnderContention() {
        let handle = kk_semaphore_create(1)
        XCTAssertNotEqual(handle, 0)
        XCTAssertEqual(kk_semaphore_acquire(handle, 0), 0, "main thread takes the only permit")

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
        XCTAssertEqual(waiterStarted.wait(timeout: .now() + 2), .success)

        // With only one permit held by the main thread, the contended withPermit
        // call must block rather than silently skip the action and return early.
        XCTAssertEqual(waiterDone.wait(timeout: .now() + 0.2), .timedOut, "withPermit must block while contended")

        XCTAssertEqual(kk_semaphore_release(handle), 0)
        XCTAssertEqual(waiterDone.wait(timeout: .now() + 2), .success)

        // The action must have actually run once unblocked, and the permit it
        // held must be returned afterward (no leak).
        XCTAssertEqual(runtimeSemaphoreWithPermitContentionResult, 99, "the contended call must still run the action and return its result")
        XCTAssertEqual(runtimeSemaphoreWithPermitObservedAvailableInside, 0, "the action must observe the permit as held while it runs")
        XCTAssertEqual(kk_semaphore_availablePermits(handle), 1, "the permit must not leak after the contended withPermit completes")
    }
}
