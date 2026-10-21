import Foundation
@testable import Runtime
import Testing

/// KUU-2688: `runTest`'s `timeout` argument drives a real-time watchdog
/// (`RuntimeTestRunTimeout`) that cancels the test scope and reports an
/// `UncompletedCoroutinesError`; the bundled `RuntimeTestScheduler` pumps
/// virtual-time work while the run is in flight so the body's own `delay`
/// resolves like upstream's TestDispatcher.
@Suite(.serialized, .runtimeIsolation(.gcOnly))
struct RuntimeTestRunTimeoutTests {
    private static let millisUnit = 2
    private static let microsUnit = 1

    private func makeScope() -> RuntimeCoroutineScope? {
        runtimeCoroutineScope(from: kk_coroutine_scope_new_with_context(0))
    }

    private func waitFor(_ condition: @escaping () -> Bool, millis: Int = 2_000) -> Bool {
        var remaining = millis / 5
        while remaining > 0 {
            if condition() { return true }
            usleep(5_000)
            remaining -= 1
        }
        return condition()
    }

    // MARK: - Budget decoding

    @Test
    func timeoutBudgetDecodesFiniteDuration() {
        let (millis, text) = runtimeRunTestTimeoutBudget(
            kk_duration_toDuration_long(50, Self.millisUnit)
        )
        #expect(millis == 50)
        #expect(text == "50ms")
    }

    @Test
    func timeoutBudgetClampsSubMillisecondToOne() {
        // Upstream's `Duration.toDelayMillis()` gives a positive duration at
        // least 1 ms.
        let (millis, _) = runtimeRunTestTimeoutBudget(
            kk_duration_toDuration_long(1, Self.microsUnit)
        )
        #expect(millis == 1)
    }

    @Test
    func timeoutBudgetDisarmsNonPositiveAndInfinite() {
        #expect(runtimeRunTestTimeoutBudget(kk_duration_zero()).millis == nil)
        #expect(runtimeRunTestTimeoutBudget(
            kk_duration_toDuration_long(-5, Self.millisUnit)
        ).millis == nil)
        #expect(runtimeRunTestTimeoutBudget(kk_duration_infinite()).millis == nil)
    }

    // MARK: - Watchdog lifecycle

    @Test
    func watchdogFireCancelsScopeAndChildren() throws {
        let scope = try #require(makeScope())
        _ = scope.installJob()
        let child = RuntimeJobHandle()
        // `launch` mints its job under this debug name; a bare handle
        // defaults to "JobImpl" in the debug rendering.
        child.debugName = "StandaloneCoroutine"
        child.markStarted()
        scope.registerChild(runtimeRegisterObject(child))

        let watchdog = RuntimeTestRunTimeout()
        watchdog.arm(millis: 20, scope: scope)
        defer { watchdog.disarm() }

        #expect(waitFor { watchdog.fired })
        #expect(scope.isCancelled)
        #expect(scope.cancellationMessage == "The test timed out")
        #expect(child.cancellationSnapshot())
        #expect(!watchdog.bodyFinishedAtFire)
        // The snapshot is taken before the cancel, so the child is listed
        // the way upstream's UncompletedCoroutinesError enumerates jobs.
        #expect(watchdog.activeChildrenAtFire.count == 1)
        #expect(watchdog.activeChildrenAtFire[0].contains("StandaloneCoroutine"))
    }

    @Test
    func disarmedWatchdogNeverFires() throws {
        let scope = try #require(makeScope())
        let watchdog = RuntimeTestRunTimeout()
        watchdog.arm(millis: 10, scope: scope)
        watchdog.disarm()
        usleep(60_000)
        #expect(!watchdog.fired)
        #expect(!scope.isCancelled)
    }

    // MARK: - Error shape

    @Test
    func timeoutErrorIsAssertionErrorFamilyWithSuppressed() {
        let body = runtimeAllocateIllegalStateException(message: "boom")
        let watchdog = RuntimeTestRunTimeout()
        let errorRaw = runtimeRunTestTimeoutError(
            watchdog: watchdog, timeoutText: "50ms", suppressed: [body]
        )
        let box = tryCast(
            UnsafeMutableRawPointer(bitPattern: errorRaw)!,
            to: RuntimeThrowableBox.self
        )
        #expect(box?.exceptionFQName == "kotlinx.coroutines.test.UncompletedCoroutinesError")
        #expect(box?.exceptionHierarchyFQNames.contains("kotlin.AssertionError") == true)
        #expect(box?.exceptionHierarchyFQNames.contains("kotlin.Throwable") == true)
        #expect(box?.suppressed == [body])
        #expect(box?.renderedMessage == "UncompletedCoroutinesError: "
            + "After waiting for 50ms, the test body did not run to completion")
    }

    @Test
    func timeoutErrorMessageListsActiveChildrenWhenBodyFinished() throws {
        let scope = try #require(makeScope())
        _ = scope.installJob()
        let child = RuntimeJobHandle()
        child.debugName = "StandaloneCoroutine"
        child.markStarted()
        scope.registerChild(runtimeRegisterObject(child))

        let watchdog = RuntimeTestRunTimeout()
        watchdog.markBodyFinished()
        watchdog.arm(millis: 20, scope: scope)
        defer { watchdog.disarm() }
        #expect(waitFor { watchdog.fired })

        let errorRaw = runtimeRunTestTimeoutError(
            watchdog: watchdog, timeoutText: "50ms", suppressed: []
        )
        let box = tryCast(
            UnsafeMutableRawPointer(bitPattern: errorRaw)!,
            to: RuntimeThrowableBox.self
        )
        #expect(box?.message?.hasPrefix("After waiting for 50ms, "
            + "there were active child jobs: [\"StandaloneCoroutine{Active}@") == true)
        #expect(box?.message?.contains("backgroundScope") == true)
    }

    // MARK: - Scheduler auto-pump

    @Test
    func autoPumpAdvancesVirtualDelayWhileLoopDrains() {
        let scheduler = RuntimeTestScheduler()
        let loop = RuntimeEventLoop()
        scheduler.bind(eventLoop: loop)
        scheduler.setAutoPump(true)
        defer { scheduler.setAutoPump(false) }

        final class Flag: @unchecked Sendable { var ran = false }
        let flag = Flag()
        scheduler.schedule(after: 1_000) { flag.ran = true }
        _ = loop.run(until: { flag.ran }, deadline: Date().addingTimeInterval(2))

        #expect(flag.ran)
        #expect(scheduler.currentTimeMillis == 1_000)
    }

    @Test
    func disarmedAutoPumpLeavesTasksPending() {
        let scheduler = RuntimeTestScheduler()
        let loop = RuntimeEventLoop()
        scheduler.bind(eventLoop: loop)
        scheduler.setAutoPump(false)

        final class Flag: @unchecked Sendable { var ran = false }
        let flag = Flag()
        scheduler.schedule(after: 1_000) { flag.ran = true }
        _ = loop.run(until: { flag.ran }, deadline: Date().addingTimeInterval(0.05))
        #expect(!flag.ran)
        #expect(scheduler.currentTimeMillis == 0)

        scheduler.advanceUntilIdle()
        #expect(flag.ran)
        #expect(scheduler.currentTimeMillis == 1_000)
    }
}
