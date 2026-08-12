import Dispatch
import Foundation
@testable import Runtime
import Testing

private typealias RuntimeTestSuspendEntry = @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int

private let runtimeKxMiniDelayFunctionID = 9101
private let runtimeKxMiniLaunchFunctionID = 9102
private let runtimeKxMiniAsyncFunctionID = 9103
private let runtimeKxMiniCancelFunctionID = 9104
private let runtimeWithContextFunctionID = 9105
private let runtimeWithContextSlowFunctionID = 9106
private let runtimeOuterWithContextFunctionID = 9107
private let runtimeCoroutineTestState = RuntimeCoroutineTestState()

/// CORO-004: thread-safe probe to observe whether a completion/join resumer fired
/// and with what value, without sharing mutable state unsafely across threads.
private final class ResumerProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var firedFlag = false
    private var resultValue = 0
    private var thrownValue = 0
    func record(result: Int, thrown: Int) {
        lock.lock()
        firedFlag = true
        resultValue = result
        thrownValue = thrown
        lock.unlock()
    }
    var fired: Bool { lock.lock(); defer { lock.unlock() }; return firedFlag }
    var result: Int { lock.lock(); defer { lock.unlock() }; return resultValue }
    var thrown: Int { lock.lock(); defer { lock.unlock() }; return thrownValue }
}

private func makeRuntimeString(_ value: String) -> Int {
    let box = RuntimeStringBox(value)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

private func runtimeStringValue(_ raw: Int) -> String {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw),
          let box = tryCast(ptr, to: RuntimeStringBox.self) else {
        return ""
    }
    return box.value
}

@_cdecl("runtime_test_suspend_with_delay")
func runtime_test_suspend_with_delay(_ continuation: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    let label = kk_coroutine_state_enter(continuation, runtimeKxMiniDelayFunctionID)
    if label == 0 {
        _ = kk_coroutine_state_set_label(continuation, 1)
        return kk_kxmini_delay(1, continuation)
    }
    outThrown?.pointee = 0
    return kk_coroutine_state_exit(continuation, 42)
}

@_cdecl("runtime_test_suspend_launch")
func runtime_test_suspend_launch(_ continuation: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    runtimeCoroutineTestState.recordLaunchEvent()
    return kk_coroutine_state_exit(continuation, 7)
}

@_cdecl("runtime_test_suspend_async")
func runtime_test_suspend_async(_ continuation: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    return kk_coroutine_state_exit(continuation, 73)
}

/// Direct suspend-call test entry that completes without reaching a suspend point.
@_cdecl("runtime_test_direct_suspend_immediate")
func runtime_test_direct_suspend_immediate(_ continuation: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    return kk_coroutine_state_exit(continuation, 123)
}

@_cdecl("runtime_test_suspend_with_arg")
func runtime_test_suspend_with_arg(_ continuation: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    let arg = kk_coroutine_launcher_arg_get(continuation, 0)
    outThrown?.pointee = 0
    return kk_coroutine_state_exit(continuation, Int(arg) + 10)
}

@_cdecl("runtime_test_suspend_cancel_loop")
func runtime_test_suspend_cancel_loop(_ continuation: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    let label = kk_coroutine_state_enter(continuation, runtimeKxMiniCancelFunctionID)
    if label == 0 {
        runtimeCoroutineTestState.recordCancelLoopIteration()
        _ = kk_coroutine_state_set_label(continuation, 1)
        let cancelled = kk_coroutine_check_cancellation(continuation, outThrown)
        if cancelled != 0 {
            return 0
        }
        return kk_kxmini_delay(5, continuation)
    }
    // Resumed after delay — check cancellation again
    let cancelled = kk_coroutine_check_cancellation(continuation, outThrown)
    if cancelled != 0 {
        return 0
    }
    // Loop: increment iteration counter, set label to 1 and delay again
    runtimeCoroutineTestState.recordCancelLoopIteration()
    _ = kk_coroutine_state_set_label(continuation, 1)
    return kk_kxmini_delay(5, continuation)
}

/// withContext test entry: returns a value immediately (no suspension).
@_cdecl("runtime_test_with_context_simple")
func runtime_test_with_context_simple(_ continuation: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    return kk_coroutine_state_exit(continuation, 99)
}

/// withContext test entry: suspends via delay, then returns.
/// This verifies that the full suspend-resume loop runs on the target queue.
@_cdecl("runtime_test_with_context_delay")
func runtime_test_with_context_delay(_ continuation: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    let label = kk_coroutine_state_enter(continuation, runtimeWithContextFunctionID)
    if label == 0 {
        _ = kk_coroutine_state_set_label(continuation, 1)
        return kk_kxmini_delay(1, continuation)
    }
    outThrown?.pointee = 0
    return kk_coroutine_state_exit(continuation, 55)
}

/// withContext test entry: uses a longer delay so the caller-resumer path can be observed.
@_cdecl("runtime_test_with_context_slow_delay")
func runtime_test_with_context_slow_delay(_ continuation: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    let label = kk_coroutine_state_enter(continuation, runtimeWithContextSlowFunctionID)
    if label == 0 {
        _ = kk_coroutine_state_set_label(continuation, 1)
        return kk_kxmini_delay(75, continuation)
    }
    outThrown?.pointee = 0
    return kk_coroutine_state_exit(continuation, 56)
}

/// Outer withContext test entry: proves kk_with_context suspends and later resumes the caller.
@_cdecl("runtime_test_outer_with_context_delay")
func runtime_test_outer_with_context_delay(_ continuation: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    let label = kk_coroutine_state_enter(continuation, runtimeOuterWithContextFunctionID)
    if label == 0 {
        _ = kk_coroutine_state_set_label(continuation, 1)
        let blockContinuation = kk_coroutine_continuation_new(runtimeWithContextSlowFunctionID)
        let entryRaw = unsafeBitCast(
            runtime_test_with_context_slow_delay as RuntimeTestSuspendEntry,
            to: Int.self
        )
        let result = kk_with_context(kk_dispatcher_default(), entryRaw, blockContinuation)
        if result == Int(bitPattern: kk_coroutine_suspended()) {
            return result
        }
        _ = kk_coroutine_state_set_completion(continuation, result)
    }
    let completedValue = kk_coroutine_state_get_completion(continuation)
    outThrown?.pointee = 0
    return kk_coroutine_state_exit(continuation, completedValue)
}

private func resetRuntimeCoroutineStateTestState() {
    runtimeCoroutineTestState.reset()
}

// Serialized: these cases block libdispatch worker threads while waiting on
// coroutine resumers, so running them concurrently starves the global pool.
@Suite(.serialized, .runtimeIsolation(.gcOnly, resetAdditionalState: resetRuntimeCoroutineStateTestState))
struct RuntimeCoroutineStateTests {
    @Test func testContinuationStoresAndLoadsSpillSlotsAndCompletion() {
        let continuation = kk_coroutine_continuation_new(42)
        defer { _ = kk_coroutine_state_exit(continuation, 0) }

        #expect(kk_coroutine_state_enter(continuation, 42) == 0)

        #expect(kk_coroutine_state_set_spill(continuation, 0, 111) == 111)
        #expect(kk_coroutine_state_set_spill(continuation, 2, 333) == 333)
        #expect(kk_coroutine_state_get_spill(continuation, 0) == 111)
        #expect(kk_coroutine_state_get_spill(continuation, 1) == 0)
        #expect(kk_coroutine_state_get_spill(continuation, 2) == 333)

        #expect(kk_coroutine_state_set_completion(continuation, 777) == 777)
        #expect(kk_coroutine_state_get_completion(continuation) == 777)
    }

    @Test func testStateEnterResetsCompletionAndSpillsWhenFunctionChanges() {
        let continuation = kk_coroutine_continuation_new(7)
        defer { _ = kk_coroutine_state_exit(continuation, 0) }

        _ = kk_coroutine_state_set_label(continuation, 5)
        _ = kk_coroutine_state_set_spill(continuation, 0, 91)
        _ = kk_coroutine_state_set_completion(continuation, 123)

        #expect(kk_coroutine_state_enter(continuation, 7) == 5)
        #expect(kk_coroutine_state_enter(continuation, 8) == 0)
        #expect(kk_coroutine_state_get_spill(continuation, 0) == 0)
        #expect(kk_coroutine_state_get_completion(continuation) == 0)
    }

    @Test func testKxMiniRunBlockingResumesDelayedSuspendEntry() {
        let entryRaw = unsafeBitCast(
            runtime_test_suspend_with_delay as RuntimeTestSuspendEntry,
            to: Int.self
        )
        let result = kk_kxmini_run_blocking(entryRaw, runtimeKxMiniDelayFunctionID, nil)
        #expect(result == 42)
    }

    @Test func testKxMiniLaunchRunsSuspendEntryAsynchronously() {
        let launchBaseline = runtimeCoroutineTestState.launchEventCountSnapshot()
        let entryRaw = unsafeBitCast(
            runtime_test_suspend_launch as RuntimeTestSuspendEntry,
            to: Int.self
        )
        // launch now returns a job handle (non-zero) for structured concurrency
        let jobHandle = kk_kxmini_launch(entryRaw, runtimeKxMiniLaunchFunctionID)
        #expect(jobHandle != 0)
        #expect(runtimeCoroutineTestState.waitForLaunchEvent(after: launchBaseline, timeout: 1.0),
            "Expected launched coroutine to record a launch event."
        )
        #expect(kk_job_join(jobHandle, 0) == 7)
    }

    @Test func testKxMiniAsyncReturnsAwaitableHandle() {
        let entryRaw = unsafeBitCast(
            runtime_test_suspend_async as RuntimeTestSuspendEntry,
            to: Int.self
        )
        let handle = kk_kxmini_async(entryRaw, runtimeKxMiniAsyncFunctionID)
        #expect(handle != 0)
        #expect(kk_kxmini_async_await(handle, 0) == 73)
    }

    @Test func testAwaitPropagatesExceptionFromAlreadyCompletedTask() {
        let task = RuntimeAsyncTask()
        let taskPtr = UnsafeMutableRawPointer(Unmanaged.passRetained(task).toOpaque())
        defer { Unmanaged<RuntimeAsyncTask>.fromOpaque(taskPtr).release() }
        let handle = Int(bitPattern: taskPtr)

        let throwable = runtimeAllocateThrowable(message: "child-fail")
        task.completeExceptionally(with: throwable)

        let callerContinuation = kk_coroutine_continuation_new(9110)
        defer { _ = kk_coroutine_state_exit(callerContinuation, 0) }

        let awaited = kk_kxmini_async_await(handle, callerContinuation)

        #expect(awaited == Int(bitPattern: kk_coroutine_suspended()),
            "Awaiting an already-failed task must hand control back to the resume label."
        )
        #expect(kk_coroutine_state_get_thrown_exception(callerContinuation) == throwable,
            "The child failure must be published on the caller state instead of being swallowed."
        )
    }

    @Test func testAwaitReturnsResultDirectlyForAlreadyCompletedTask() {
        let task = RuntimeAsyncTask()
        let taskPtr = UnsafeMutableRawPointer(Unmanaged.passRetained(task).toOpaque())
        defer { Unmanaged<RuntimeAsyncTask>.fromOpaque(taskPtr).release() }
        let handle = Int(bitPattern: taskPtr)
        task.complete(with: 55)

        let callerContinuation = kk_coroutine_continuation_new(9111)
        defer { _ = kk_coroutine_state_exit(callerContinuation, 0) }

        #expect(kk_kxmini_async_await(handle, callerContinuation) == 55)
        #expect(kk_coroutine_state_get_thrown_exception(callerContinuation) == 0)
    }

    @Test func testDirectSuspendCallReturnsImmediateChildResult() {
        let callerContinuation = kk_coroutine_continuation_new(9108)
        defer { _ = kk_coroutine_state_exit(callerContinuation, 0) }
        let childContinuation = kk_coroutine_continuation_new(9109)
        let entryRaw = unsafeBitCast(
            runtime_test_direct_suspend_immediate as RuntimeTestSuspendEntry,
            to: Int.self
        )

        let result = kk_coroutine_call_direct_suspend(
            entryRaw,
            childContinuation,
            callerContinuation
        )

        #expect(result == 123)
        #expect(result != Int(bitPattern: kk_coroutine_suspended()))
        #expect(kk_coroutine_state_get_completion(callerContinuation) == 123)
    }

    @Test func testLauncherArgSetAndGetRoundTrips() {
        let continuation = kk_coroutine_continuation_new(5000)
        defer { _ = kk_coroutine_state_exit(continuation, 0) }

        #expect(kk_coroutine_launcher_arg_set(continuation, 0, 42) == 42)
        #expect(kk_coroutine_launcher_arg_set(continuation, 1, 99) == 99)
        #expect(kk_coroutine_launcher_arg_get(continuation, 0) == 42)
        #expect(kk_coroutine_launcher_arg_get(continuation, 1) == 99)
        #expect(kk_coroutine_launcher_arg_get(continuation, 2) == 0)
    }

    @Test func testLauncherArgsSurviveStateEnterReset() {
        let continuation = kk_coroutine_continuation_new(5001)
        defer { _ = kk_coroutine_state_exit(continuation, 0) }

        _ = kk_coroutine_launcher_arg_set(continuation, 0, 77)
        #expect(kk_coroutine_state_enter(continuation, 5001) == 0)
        _ = kk_coroutine_state_enter(continuation, 9999)
        #expect(kk_coroutine_launcher_arg_get(continuation, 0) == 77)
    }

    @Test func testRunBlockingWithContPassesArgsThroughLauncherArgs() {
        let functionID = 5002
        let continuation = kk_coroutine_continuation_new(functionID)
        _ = kk_coroutine_launcher_arg_set(continuation, 0, 32)

        let entryRaw = unsafeBitCast(
            runtime_test_suspend_with_arg as RuntimeTestSuspendEntry,
            to: Int.self
        )
        let result = kk_kxmini_run_blocking_with_cont(entryRaw, continuation, nil)
        #expect(result == 42)
    }

    @Test func testLaunchWithContRunsAsynchronously() {
        let launchBaseline = runtimeCoroutineTestState.launchEventCountSnapshot()
        let functionID = 5003
        let continuation = kk_coroutine_continuation_new(functionID)
        _ = kk_coroutine_launcher_arg_set(continuation, 0, 0)

        let entryRaw = unsafeBitCast(
            runtime_test_suspend_launch as RuntimeTestSuspendEntry,
            to: Int.self
        )
        // launch_with_cont now returns a job handle (non-zero) for structured concurrency
        let jobHandle = kk_kxmini_launch_with_cont(entryRaw, continuation)
        #expect(jobHandle != 0)
        #expect(runtimeCoroutineTestState.waitForLaunchEvent(after: launchBaseline, timeout: 1.0),
            "Expected launched continuation to record a launch event."
        )
        #expect(kk_job_join(jobHandle, 0) == 7)
    }

    @Test func testCoroutineScopeLaunchWithContForwardsCaptureArgs() {
        // BUG-049: a capturing suspend lambda launched via CoroutineScope.launch must
        // thread its captured outer variables through the launcher continuation.
        let scopeHandle = kk_coroutine_scope_new()
        #expect(scopeHandle != 0)

        let functionID = 5008
        let continuation = kk_coroutine_continuation_new(functionID)
        _ = kk_coroutine_launcher_arg_set(continuation, 0, 63)

        let entryRaw = unsafeBitCast(
            runtime_test_suspend_with_arg as RuntimeTestSuspendEntry,
            to: Int.self
        )
        let jobHandle = kk_coroutine_scope_launch_with_cont(scopeHandle, entryRaw, continuation)
        #expect(jobHandle != 0)
        // runtime_test_suspend_with_arg returns launcherArg(0) + 10 == 73.
        #expect(kk_job_join(jobHandle, 0) == 73)
        #expect(kk_coroutine_scope_wait(scopeHandle) == runtimeNullSentinelInt)
    }

    @Test func testAsyncWithContReturnsAwaitableResult() {
        let functionID = 5004
        let continuation = kk_coroutine_continuation_new(functionID)
        _ = kk_coroutine_launcher_arg_set(continuation, 0, 63)

        let entryRaw = unsafeBitCast(
            runtime_test_suspend_with_arg as RuntimeTestSuspendEntry,
            to: Int.self
        )
        let handle = kk_kxmini_async_with_cont(entryRaw, continuation)
        #expect(handle != 0)
        #expect(kk_kxmini_async_await(handle, 0) == 73)
    }

    @Test func testRunBlockingWithContInvalidEntryDoesNotCrash() {
        let continuation = kk_coroutine_continuation_new(5005)
        _ = kk_coroutine_launcher_arg_set(continuation, 0, 123)
        _ = kk_kxmini_run_blocking_with_cont(0, continuation, nil)
    }

    @Test func testLaunchWithContInvalidEntryDoesNotCrash() {
        let continuation = kk_coroutine_continuation_new(5006)
        _ = kk_coroutine_launcher_arg_set(continuation, 0, 0)
        _ = kk_kxmini_launch_with_cont(0, continuation)
    }

    @Test func testAsyncWithContInvalidEntryDoesNotCrash() {
        let continuation = kk_coroutine_continuation_new(5007)
        _ = kk_coroutine_launcher_arg_set(continuation, 0, 1)
        _ = kk_kxmini_async_with_cont(0, continuation)
    }

    // MARK: - Structured Concurrency (P5-89)

    @Test func testCoroutineScopeNewAndWaitLifecycle() {
        let scopeHandle = kk_coroutine_scope_new()
        #expect(scopeHandle != 0)
        // Scope with no children should complete immediately; wait returns the
        // nullable-Throwable null sentinel (not raw 0) when there is no failure.
        #expect(kk_coroutine_scope_wait(scopeHandle) == runtimeNullSentinelInt)
    }

    @Test func testCoroutineScopeWaitsForLaunchedChild() {
        let scopeHandle = kk_coroutine_scope_new()
        let launchBaseline = runtimeCoroutineTestState.launchEventCountSnapshot()

        // Launch a child that delays and completes with value 7
        let entryRaw = unsafeBitCast(
            runtime_test_suspend_launch as RuntimeTestSuspendEntry,
            to: Int.self
        )
        let jobHandle = kk_kxmini_launch(entryRaw, runtimeKxMiniLaunchFunctionID)
        #expect(jobHandle != 0)

        // Wait for the launched signal to confirm the child ran
        #expect(runtimeCoroutineTestState.waitForLaunchEvent(after: launchBaseline, timeout: 2.0),
            "Expected scope child to record a launch event."
        )

        // scope_wait should return after all children complete
        #expect(kk_coroutine_scope_wait(scopeHandle) == runtimeNullSentinelInt)
    }

    @Test func testJobJoinWaitsForCompletion() {
        let entryRaw = unsafeBitCast(
            runtime_test_suspend_async as RuntimeTestSuspendEntry,
            to: Int.self
        )
        // Launch outside a scope to get a job handle directly
        let jobHandle = kk_kxmini_launch(entryRaw, runtimeKxMiniAsyncFunctionID)
        #expect(jobHandle != 0)
        let result = kk_job_join(jobHandle, 0)
        #expect(result == 73)
    }

    @Test func testCoroutineScopeCancelPropagatesToChildren() {
        let scopeHandle = kk_coroutine_scope_new()

        // Launch a child that delays (will be cancelled before completing normally)
        let entryRaw = unsafeBitCast(
            runtime_test_suspend_with_delay as RuntimeTestSuspendEntry,
            to: Int.self
        )
        _ = kk_kxmini_launch(entryRaw, runtimeKxMiniDelayFunctionID)

        // Measure how long cancel + wait take to complete.
        // The child uses kk_kxmini_delay(1, ...), so a correct cancellation
        // should cause wait to complete significantly earlier than 1 second.
        let start = DispatchTime.now()

        // Cancel the scope — should propagate to children
        #expect(kk_coroutine_scope_cancel(scopeHandle) == 0)

        // Wait should complete (children are cancelled so they exit early)
        #expect(kk_coroutine_scope_wait(scopeHandle) == runtimeNullSentinelInt)

        let end = DispatchTime.now()
        let elapsedSeconds = Double(end.uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000

        // Ensure we didn't just wait for the full 1-second delay, which would
        // indicate that the child was not actually cancelled.
        #expect(elapsedSeconds < 0.9)
    }

    @Test func testCoroutineScopeRegisterChildManualRegistration() {
        let scopeHandle = kk_coroutine_scope_new()

        // Create an async task and manually register it
        let entryRaw = unsafeBitCast(
            runtime_test_suspend_async as RuntimeTestSuspendEntry,
            to: Int.self
        )
        // Temporarily pop the scope to prevent auto-registration
        let savedScope = RuntimeCoroutineScope.current
        RuntimeCoroutineScope.current = nil
        defer { RuntimeCoroutineScope.current = savedScope }

        let asyncHandle = kk_kxmini_async(entryRaw, runtimeKxMiniAsyncFunctionID)

        // Restore scope before manual registration
        RuntimeCoroutineScope.current = savedScope
        _ = kk_coroutine_scope_register_child(scopeHandle, asyncHandle)

        // Await the async result BEFORE scope_wait, since scope_wait releases the handle.
        // This matches real usage: user code awaits within the scope block, then scope cleans up.
        let result = kk_kxmini_async_await(asyncHandle, 0)
        #expect(result == 73)

        // Wait for children — scope releases remaining retains for the child
        #expect(kk_coroutine_scope_wait(scopeHandle) == runtimeNullSentinelInt)
    }

    @Test func testJobJoinWithinScopeAndScopeWaitsForChild() {
        let scopeHandle = kk_coroutine_scope_new()
        #expect(scopeHandle != 0)

        let entryRaw = unsafeBitCast(
            runtime_test_suspend_async as RuntimeTestSuspendEntry,
            to: Int.self
        )

        // Launch within an active scope so the job is registered with it
        let jobHandle = kk_kxmini_launch(entryRaw, runtimeKxMiniAsyncFunctionID)
        #expect(jobHandle != 0)

        // Explicitly join the job and verify it completed successfully
        let result = kk_job_join(jobHandle, 0)
        #expect(result == 73)

        // Scope wait should also complete successfully after the child has finished
        #expect(kk_coroutine_scope_wait(scopeHandle) == runtimeNullSentinelInt)
    }

    @Test func testNestedCoroutineScopesRestoreParent() {
        let outerScope = kk_coroutine_scope_new()
        #expect(outerScope != 0)

        let innerScope = kk_coroutine_scope_new()
        #expect(innerScope != 0)

        // Inner scope wait should pop inner and restore outer as current
        #expect(kk_coroutine_scope_wait(innerScope) == runtimeNullSentinelInt)

        // Outer scope wait should pop outer
        #expect(kk_coroutine_scope_wait(outerScope) == runtimeNullSentinelInt)
    }

    // MARK: - CORO-002: Cancellation Tests

    @Test func testCheckCancellationReturnsZeroWhenNotCancelled() {
        let continuation = kk_coroutine_continuation_new(42)
        defer { _ = kk_coroutine_state_exit(continuation, 0) }
        var outThrown = 0
        let result = kk_coroutine_check_cancellation(continuation, &outThrown)
        #expect(result == 0, "Should return 0 when not cancelled")
        #expect(outThrown == 0, "outThrown should be 0 when not cancelled")
    }

    @Test func testCheckCancellationReturnsCancellationExceptionWhenCancelled() {
        let continuation = kk_coroutine_continuation_new(42)
        defer { _ = kk_coroutine_state_exit(continuation, 0) }
        // Link a job handle so kk_coroutine_cancel and kk_coroutine_check_cancellation work
        let job = RuntimeJobHandle()
        if let state = runtimeContinuationState(from: continuation) {
            state.jobHandle = job
            job.continuationState = state
        }
        kk_coroutine_cancel(continuation)
        var outThrown = 0
        let result = kk_coroutine_check_cancellation(continuation, &outThrown)
        #expect(result == 1, "Should return 1 when cancelled")
        #expect(outThrown != 0, "outThrown should be set to CancellationException")
        #expect(kk_is_cancellation_exception(outThrown) == 1, "Should be a CancellationException")
    }

    @Test func testCancelCurrentCoroutinePreservesMessageAndCause() {
        let continuation = kk_coroutine_continuation_new(42)
        defer { _ = kk_coroutine_state_exit(continuation, 0) }

        let job = RuntimeJobHandle()
        if let state = runtimeContinuationState(from: continuation) {
            state.jobHandle = job
            job.continuationState = state
        }

        let taskKey = RuntimeCoroutineScopeTaskKey.installFreshKey()
        defer { RuntimeCoroutineScopeTaskKey.removeKey() }
        if let state = runtimeContinuationState(from: continuation) {
            RuntimeContinuationState.installCurrent(state, forTask: taskKey)
        }
        defer { RuntimeContinuationState.removeCurrent(forTask: taskKey) }

        let messageRaw = makeRuntimeString("custom stop")
        let causeRaw = __kk_throwable_new(UnsafeMutableRawPointer(bitPattern: makeRuntimeString("root cause")))

        _ = kk_coroutine_cancel_current(messageRaw, Int(bitPattern: causeRaw))
        #expect(job.cancellationSnapshot(), "Current job should be cancelled")

        var outThrown = 0
        let thrownRaw = kk_coroutine_check_cancellation(continuation, &outThrown)
        #expect(thrownRaw == 1, "Cancellation check should report cancellation")
        #expect(outThrown != 0, "Cancellation should materialize a throwable")
        #expect(runtimeStringValue(__kk_throwable_message(outThrown)) == "custom stop")
        #expect(runtimeStringValue(__kk_throwable_message(__kk_throwable_cause(outThrown))) == "root cause")
    }

    @Test func testIsCancellationExceptionReturnsFalseForRegularThrowable() {
        let throwablePtr = __kk_throwable_new(nil)
        let throwableInt = Int(bitPattern: throwablePtr)
        let result = kk_is_cancellation_exception(throwableInt)
        #expect(result == 0, "Regular throwable should not be CancellationException")
    }

    @Test func testJobCancelStopsLaunchedCoroutine() {
        let entryRaw = unsafeBitCast(
            runtime_test_suspend_cancel_loop as RuntimeTestSuspendEntry,
            to: Int.self
        )
        let jobHandle = kk_kxmini_launch(entryRaw, runtimeKxMiniCancelFunctionID)
        #expect(jobHandle != 0, "Launch should return a job handle")

        // Wait until the coroutine has started (bounded polling)
        #expect(runtimeCoroutineTestState.waitForCancelLoopIterations(atLeast: 1, timeout: 2.0),
            "Coroutine should have started"
        )
        #expect(runtimeCoroutineTestState.cancelLoopIterationsSnapshot() > 0,
            "Coroutine should have started"
        )

        // Cancel the job
        _ = kk_job_cancel(jobHandle)

        // Join the job — should complete promptly after cancellation
        let startTime = DispatchTime.now()
        _ = kk_job_join(jobHandle, 0)
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000_000
        #expect(elapsed < 2.0, "Coroutine should stop promptly after cancel")
    }

    @Test func testContextCancelStopsLaunchedCoroutine() {
        let entryRaw = unsafeBitCast(
            runtime_test_suspend_cancel_loop as RuntimeTestSuspendEntry,
            to: Int.self
        )
        let jobHandle = kk_kxmini_launch(entryRaw, runtimeKxMiniCancelFunctionID)
        #expect(jobHandle != 0, "Launch should return a job handle")

        let contextHandle = kk_context_plus(jobHandle, kk_dispatcher_default())
        defer { kk_context_release(contextHandle) }

        #expect(runtimeCoroutineTestState.waitForCancelLoopIterations(atLeast: 1, timeout: 2.0),
            "Coroutine should have started"
        )

        _ = kk_context_cancel(contextHandle, 0)
        #expect(kk_job_is_cancelled(jobHandle) == 1)

        let startTime = DispatchTime.now()
        _ = kk_job_join(jobHandle, 0)
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000_000
        #expect(elapsed < 2.0, "Coroutine should stop promptly after context cancel")
    }

    @Test func testLaunchReturnsJobHandle() {
        let launchBaseline = runtimeCoroutineTestState.launchEventCountSnapshot()
        let entryRaw = unsafeBitCast(
            runtime_test_suspend_launch as RuntimeTestSuspendEntry,
            to: Int.self
        )
        let jobHandle = kk_kxmini_launch(entryRaw, runtimeKxMiniLaunchFunctionID)
        #expect(jobHandle != 0, "Launch should return a non-zero job handle")
        #expect(runtimeCoroutineTestState.waitForLaunchEvent(after: launchBaseline, timeout: 1.0),
            "Expected launched coroutine to record a launch event."
        )
        #expect(kk_job_join(jobHandle, 0) == 7)
    }

    @Test func testJobStateMachineTransitionsAndAwaitCompletion() {
        let job = RuntimeJobHandle()
        #expect(!job.isActiveSnapshot())
        #expect(!job.completedSnapshot())
        #expect(!job.cancellationSnapshot())

        job.markStarted()
        #expect(job.isActiveSnapshot())

        #expect(job.complete(with: 41))
        #expect(job.completedSnapshot())
        #expect(!job.cancellationSnapshot())
        #expect(job.awaitCompletion() == 41)
        #expect(job.join() == 41)
    }

    @Test func testJobCompleteExceptionallyStoresFailureCause() {
        let job = RuntimeJobHandle()
        job.markStarted()
        let throwable = runtimeAllocateThrowable(message: "boom")

        #expect(job.completeExceptionally(with: throwable))
        #expect(job.completedSnapshot())
        #expect(job.isFailedSnapshot())
        #expect(!job.cancellationSnapshot())
        #expect(job.join() == throwable)
    }

    @Test func testJobCancelPropagatesToRegisteredChildren() {
        let parent = RuntimeJobHandle()
        let child = RuntimeJobHandle()
        parent.markStarted()
        child.markStarted()

        let childHandle = Int(bitPattern: Unmanaged.passUnretained(child).toOpaque())
        parent.registerChild(childHandle)

        #expect(parent.cancel())
        #expect(parent.cancellationSnapshot())
        #expect(child.cancellationSnapshot())
        #expect(parent.complete(with: 0))
        #expect(child.complete(with: 0))
        #expect(parent.completedSnapshot())
        #expect(child.completedSnapshot())
    }

    @Test func testJobCancelWithCausePreservesCauseValue() {
        let job = RuntimeJobHandle()
        job.markStarted()
        let cause = runtimeAllocateThrowable(message: "cancel cause")

        #expect(job.cancel(cause: cause))
        #expect(job.cancellationSnapshot())
        #expect(job.complete(with: 0))
        #expect(job.join() == cause)
    }

    // MARK: - STDLIB-250: withContext async context switching

    @Test func testWithContextDefaultDispatcherReturnsBlockResult() {
        let continuation = kk_coroutine_continuation_new(runtimeWithContextFunctionID)
        let entryRaw = unsafeBitCast(
            runtime_test_with_context_simple as RuntimeTestSuspendEntry,
            to: Int.self
        )
        let dispatcher = kk_dispatcher_default()
        let result = kk_with_context(dispatcher, entryRaw, continuation)
        #expect(result == 99, "withContext should return the block's result")
    }

    @Test func testWithContextIODispatcherReturnsBlockResult() {
        let continuation = kk_coroutine_continuation_new(runtimeWithContextFunctionID)
        let entryRaw = unsafeBitCast(
            runtime_test_with_context_simple as RuntimeTestSuspendEntry,
            to: Int.self
        )
        let dispatcher = kk_dispatcher_io()
        let result = kk_with_context(dispatcher, entryRaw, continuation)
        #expect(result == 99, "withContext(IO) should return the block's result")
    }

    @Test func testWithContextHandlesSuspensionInsideBlock() {
        let continuation = kk_coroutine_continuation_new(runtimeWithContextFunctionID)
        let entryRaw = unsafeBitCast(
            runtime_test_with_context_delay as RuntimeTestSuspendEntry,
            to: Int.self
        )
        let dispatcher = kk_dispatcher_default()
        let result = kk_with_context(dispatcher, entryRaw, continuation)
        #expect(result == 55, "withContext should handle suspension inside the block")
    }

    @Test func testWithContextUnknownDispatcherFallsBackToDefault() {
        let continuation = kk_coroutine_continuation_new(runtimeWithContextFunctionID)
        let entryRaw = unsafeBitCast(
            runtime_test_with_context_simple as RuntimeTestSuspendEntry,
            to: Int.self
        )
        // Unknown dispatcher tag — should fall back to Default
        let result = kk_with_context(0xDEAD, entryRaw, continuation)
        #expect(result == 99, "Unknown dispatcher should fall back to Default and still work")
    }

    @Test func testWithContextInvalidEntryPointReturnsZero() {
        let continuation = kk_coroutine_continuation_new(runtimeWithContextFunctionID)
        // kk_with_context now cleans up the continuation internally on
        // invalid entry, so no manual defer cleanup is needed.
        let dispatcher = kk_dispatcher_default()
        let result = kk_with_context(dispatcher, 0, continuation)
        #expect(result == 0, "Invalid entry point should return 0")
    }

    @Test func testWithContextIODispatcherRunsOffMainThread() {
        let continuation = kk_coroutine_continuation_new(runtimeWithContextFunctionID)
        let entryRaw = unsafeBitCast(
            runtime_test_with_context_simple as RuntimeTestSuspendEntry,
            to: Int.self
        )
        // Run on IO dispatcher — the call should complete successfully
        // even when issued from the main thread (no deadlock).
        let dispatcher = kk_dispatcher_io()
        let result = kk_with_context(dispatcher, entryRaw, continuation)
        #expect(result == 99, "IO dispatcher should execute without deadlock")
    }

    @Test func testWithContextMainDispatcherFromMainThread() {
        // Dispatchers.Main should execute inline when already on the main
        // thread, avoiding the deadlock that would occur with async+semaphore.
        let continuation = kk_coroutine_continuation_new(runtimeWithContextFunctionID)
        let entryRaw = unsafeBitCast(
            runtime_test_with_context_simple as RuntimeTestSuspendEntry,
            to: Int.self
        )
        let dispatcher = kk_dispatcher_main()
        let result = kk_with_context(dispatcher, entryRaw, continuation)
        #expect(result == 99, "Main dispatcher should execute inline on main thread")
    }

    @Test func testWithContextMainDispatcherFromBackgroundThread() {
        // When called from a background thread, kk_with_context dispatches
        // async to DispatchQueue.main and waits on a semaphore. The test body
        // runs off the main thread, so the main queue stays free to service
        // the enqueued block.
        let finished = DispatchSemaphore(value: 0)
        // Perform the assertion inside the async block so there is no shared
        // mutable state across threads — only the semaphore is used to
        // synchronize completion with the test thread.
        DispatchQueue.global().async {
            let continuation = kk_coroutine_continuation_new(runtimeWithContextFunctionID)
            let entryRaw = unsafeBitCast(
                runtime_test_with_context_simple as RuntimeTestSuspendEntry,
                to: Int.self
            )
            let dispatcher = kk_dispatcher_main()
            let result = kk_with_context(dispatcher, entryRaw, continuation)
            #expect(result == 99, "Main dispatcher from background thread should return block result")
            finished.signal()
        }
        #expect(finished.wait(timeout: .now() + 5.0) == .success)
    }

    @Test func testWithContextWithDelayOnIODispatcher() {
        let continuation = kk_coroutine_continuation_new(runtimeWithContextFunctionID)
        let entryRaw = unsafeBitCast(
            runtime_test_with_context_delay as RuntimeTestSuspendEntry,
            to: Int.self
        )
        let dispatcher = kk_dispatcher_io()
        let result = kk_with_context(dispatcher, entryRaw, continuation)
        #expect(result == 55, "withContext(IO) should handle suspension correctly")
    }

    @Test func testWithContextCoroutineCallerUsesContinuationCompletionPath() {
        let continuation = kk_coroutine_continuation_new(runtimeOuterWithContextFunctionID)
        let entryRaw = unsafeBitCast(
            runtime_test_outer_with_context_delay as RuntimeTestSuspendEntry,
            to: Int.self
        )
        let completed = DispatchSemaphore(value: 0)
        let probe = ResumerProbe()

        let immediate = runSuspendEntryLoopWithContinuation(
            entryPointRaw: entryRaw,
            continuation: continuation,
            onCompletion: { result, thrown in
                probe.record(result: result, thrown: thrown)
                completed.signal()
            }
        )

        #expect(immediate == 0)
        #expect(!probe.fired, "withContext should suspend the caller instead of blocking until the block completes")
        #expect(completed.wait(timeout: .now() + 2.0) == .success)
        #expect(probe.result == 56)
        #expect(probe.thrown == 0)
    }

    // MARK: - CORO-004: suspend-aware await / join resumers

    @Test func testAsyncTaskCompletionResumerFiresWithResultOnComplete() {
        let task = RuntimeAsyncTask()
        let probe = ResumerProbe()
        task.addCompletionResumer { result, thrown in
            probe.record(result: result, thrown: thrown)
        }
        #expect(!probe.fired, "resumer must not fire before completion")
        task.complete(with: 42)
        #expect(probe.fired, "resumer should fire when the task completes")
        #expect(probe.result == 42)
        #expect(probe.thrown == 0)
    }

    @Test func testAsyncTaskCompletionResumerFiresWithExceptionOnCompleteExceptionally() {
        let task = RuntimeAsyncTask()
        let probe = ResumerProbe()
        task.addCompletionResumer { result, thrown in
            probe.record(result: result, thrown: thrown)
        }
        task.completeExceptionally(with: 0xBEEF)
        #expect(probe.fired)
        #expect(probe.thrown == 0xBEEF, "the thrown exception pointer should be propagated")
    }

    @Test func testAsyncTaskCompletionResumerFiresImmediatelyWhenAlreadyComplete() {
        let task = RuntimeAsyncTask()
        task.complete(with: 7)
        let probe = ResumerProbe()
        task.addCompletionResumer { result, thrown in
            probe.record(result: result, thrown: thrown)
        }
        #expect(probe.fired, "resumer must fire immediately for an already-completed task")
        #expect(probe.result == 7)
    }

    @Test func testJobHandleJoinResumerFiresOnComplete() {
        let job = RuntimeJobHandle()
        job.markStarted()
        let probe = ResumerProbe()
        job.addJoinResumer { value in
            probe.record(result: value, thrown: 0)
        }
        #expect(!probe.fired, "join resumer must not fire before completion")
        _ = job.complete(with: 11)
        #expect(probe.fired, "join resumer should fire when the job completes")
        #expect(probe.result == 11)
    }

    // MARK: - CORO-004: RuntimeCoroutineSyncGate (sequence/iterator builder migration)

    @Test func testCoroutineSyncGateContinuationResumeDoesNotBlockWaiterThread() {
        let gate = RuntimeCoroutineSyncGate()
        let resumed = DispatchSemaphore(value: 0)
        let waiterFinished = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            let suspended = gate.wait(resumeContinuation: {
                resumed.signal()
            })
            #expect(suspended, "continuation install should suspend without blocking")
            waiterFinished.signal()
        }

        Thread.sleep(forTimeInterval: 0.05)
        gate.signal()
        #expect(resumed.wait(timeout: .now() + 2.0) == .success)
        #expect(waiterFinished.wait(timeout: .now() + 2.0) == .success)
    }

    @Test func testCoroutineSyncGateSemaphoreFallbackWakesBlockedWaiter() {
        let gate = RuntimeCoroutineSyncGate()
        let done = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            gate.wait()
            done.signal()
        }

        Thread.sleep(forTimeInterval: 0.05)
        gate.signal()
        #expect(done.wait(timeout: .now() + 2.0) == .success)
    }

    @Test func testSequenceCoroutineNextElementAsyncResumesCallerWithoutBlockingWaiter() {
        let thunk: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, builderRaw, _ in
            Thread.sleep(forTimeInterval: 0.05)
            _ = __kk_sequence_builder_yield(builderRaw, 41)
            return 0
        }
        let coroutine = RuntimeSequenceCoroutine(fnPtr: unsafeBitCast(thunk, to: Int.self), closureRaw: 0)
        let callerState = RuntimeContinuationState(functionID: 9202)
        let resumed = DispatchSemaphore(value: 0)
        let probe = ResumerProbe()
        callerState.installResumeContinuation {
            probe.record(result: Int(callerState.completion), thrown: callerState.thrownException)
            resumed.signal()
        }

        let next = coroutine.nextElementAsync(callerState: callerState)

        #expect(next == nil, "nextElementAsync should return suspended instead of blocking for the producer")
        #expect(!probe.fired)
        #expect(resumed.wait(timeout: .now() + 2.0) == .success)
        #expect(probe.result == 41)
        #expect(probe.thrown == 0)
        switch coroutine.nextElement() {
        case .done:
            break
        case .value(let value):
            Issue.record("expected coroutine to drain after the async element, got \(value)")
        }
    }

    @Test func testIteratorBuilderHasNextAsyncResumesCallerWithoutBlockingWaiter() {
        let thunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { builderRaw, _ in
            Thread.sleep(forTimeInterval: 0.05)
            _ = __kk_iterator_builder_yield(builderRaw, 17)
            return 0
        }
        let builder = RuntimeIteratorBuilderBox(fnPtr: unsafeBitCast(thunk, to: Int.self))
        let builderHandle = registerRuntimeObject(builder)
        builder.bindRegisteredHandle(builderHandle)
        let callerState = RuntimeContinuationState(functionID: 9203)
        let resumed = DispatchSemaphore(value: 0)
        let probe = ResumerProbe()
        callerState.installResumeContinuation {
            probe.record(result: Int(callerState.completion), thrown: callerState.thrownException)
            resumed.signal()
        }

        let hasNext = builder.probeHasNextAsync(callerState: callerState)

        #expect(hasNext == Int(bitPattern: kk_coroutine_suspended()))
        #expect(!probe.fired)
        #expect(resumed.wait(timeout: .now() + 2.0) == .success)
        #expect(probe.result == 1)
        #expect(probe.thrown == 0)
        #expect(builder.consumeNext() == 17)
        #expect(!builder.probeHasNext())
    }

    @Test func testAsyncTaskAwaitResultReturnsCompletedWhenAlreadyDone() {
        let task = RuntimeAsyncTask()
        task.complete(with: 19)
        let state = RuntimeContinuationState(functionID: 9201)
        switch task.awaitResult(callerState: state) {
        case .completed(let result, let thrown):
            #expect(result == 19)
            #expect(thrown == 0)
        case .suspended:
            Issue.record("already-completed task must not suspend")
        }
    }

    @Test func testAsyncTaskAwaitResultSuspendsAndResumesCallerState() {
        let task = RuntimeAsyncTask()
        let state = RuntimeContinuationState(functionID: 9202)
        let registered = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            switch task.awaitResult(callerState: state) {
            case .suspended:
                registered.signal()
            case .completed:
                Issue.record("incomplete task with callerState must suspend")
            }
        }
        #expect(registered.wait(timeout: .now() + 2.0) == .success)
        task.complete(with: 31)
        #expect(state.completion == 31, "completion resumer should resume callerState")
    }

    @Test func testAsyncTaskBlockingAwaitResultStillWaits() {
        let task = RuntimeAsyncTask()
        let completed = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            #expect(task.awaitResult() == 44)
            completed.signal()
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
            task.complete(with: 44)
        }
        #expect(completed.wait(timeout: .now() + 2.0) == .success)
    }
}
