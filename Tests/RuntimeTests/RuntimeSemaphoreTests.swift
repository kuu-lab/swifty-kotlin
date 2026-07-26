import Dispatch
import Foundation
@testable import Runtime
import Testing

private func resetRuntimeSemaphoreTestState() {}

@Suite(.runtimeIsolation(.gcOnly, resetAdditionalState: resetRuntimeSemaphoreTestState))
struct RuntimeSemaphoreTests {
    @Test func semaphoreCreateAcquireTryAcquireAndRelease() {
        let handle = __kk_semaphore_create(2)
        #expect(handle != 0)

        #expect(__kk_semaphore_availablePermits(handle) == 2)
        #expect(kk_semaphore_acquire(handle, 0) == 0)
        #expect(__kk_semaphore_availablePermits(handle) == 1)
        #expect(__kk_semaphore_tryAcquire(handle) == 1)
        #expect(__kk_semaphore_availablePermits(handle) == 0)
        #expect(__kk_semaphore_tryAcquire(handle) == 0)
        #expect(kk_semaphore_release(handle) == 0)
        #expect(__kk_semaphore_availablePermits(handle) == 1)
        #expect(kk_semaphore_release(handle) == 0)
        #expect(__kk_semaphore_availablePermits(handle) == 2)
    }

    // KSP-677: Semaphore.withPermit is Kotlin source composing the c-soft
    // acquire()/release() kernel primitives, so its runtime coverage is the
    // acquire/tryAcquire/release paths in this suite.
    @Test func semaphoreAcquireBlocksUntilPermitAvailable() {
        let handle = __kk_semaphore_create(1)
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
        #expect(__kk_semaphore_availablePermits(handle) == 1)
    }
}
