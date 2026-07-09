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

final class RuntimeSemaphoreTests: IsolatedRuntimeXCTestCase {
    // swiftlint:disable:next static_over_final_class
    override class var requiredLockSet: RuntimeLockSet { .gcOnly }
    override func resetIsolatedRuntimeTestState() {
        runtimeSemaphoreWithPermitObservedAvailableInside = -1
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

    func testSemaphoreWithPermitLimitsConcurrentWaiters() {
        let handle = kk_semaphore_create(1)
        XCTAssertNotEqual(handle, 0)
        XCTAssertEqual(kk_semaphore_acquire(handle, 0), 0)

        let waiterDone = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            _ = kk_semaphore_acquire(handle, 0)
            _ = kk_semaphore_release(handle)
            waiterDone.signal()
        }

        Thread.sleep(forTimeInterval: 0.05)
        XCTAssertEqual(kk_semaphore_tryAcquire(handle), 0, "the single permit must still be held by the main thread")

        XCTAssertEqual(kk_semaphore_release(handle), 0)
        XCTAssertEqual(waiterDone.wait(timeout: .now() + .seconds(2)), .success)
        XCTAssertEqual(kk_semaphore_availablePermits(handle), 1)
    }
}
