import Dispatch
import Foundation
@testable import Runtime
import XCTest

// MARK: - C-callable helpers for advanced coroutine tests

private let advancedCoroTestState = AdvancedCoroutineTestState()

/// File-level storage for the throwable raw value used in advcoro_fail_with_exc.
private nonisolated(unsafe) var advCoroFailExcRaw: Int = 0

/// Non-capturing C stub that writes `advCoroFailExcRaw` to outThrown.
@_cdecl("advcoro_fail_with_exc")
func advcoro_fail_with_exc(_ _: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = advCoroFailExcRaw
    return 0
}

/// Non-capturing C stub that returns 512 (success value for resumeWith test).
@_cdecl("advcoro_return_512")
func advcoro_return_512(_ _: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    return 512
}

/// A simple suspend function that adds `arg[0]` to a fixed constant and returns.
@_cdecl("advcoro_add_constant")
func advcoro_add_constant(_ continuation: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    let arg = kk_coroutine_launcher_arg_get(continuation, 0)
    outThrown?.pointee = 0
    return kk_coroutine_state_exit(continuation, Int(arg) + 100)
}

/// A suspend function that delays once, then returns 55.
private let advCoroDelayFunctionID = 8801
@_cdecl("advcoro_delay_then_return")
func advcoro_delay_then_return(_ continuation: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    let label = kk_coroutine_state_enter(continuation, advCoroDelayFunctionID)
    if label == 0 {
        _ = kk_coroutine_state_set_label(continuation, 1)
        return kk_kxmini_delay(1, continuation)
    }
    outThrown?.pointee = 0
    return kk_coroutine_state_exit(continuation, 55)
}

/// A suspend function that delays, sets a spill slot with a "live value", then reads it back.
private let advCoroSpillFunctionID = 8802
@_cdecl("advcoro_spill_across_suspension")
func advcoro_spill_across_suspension(_ continuation: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    let label = kk_coroutine_state_enter(continuation, advCoroSpillFunctionID)
    if label == 0 {
        // Save a "live value" in spill slot 0 before suspending.
        _ = kk_coroutine_state_set_spill(continuation, 0, 777)
        _ = kk_coroutine_state_set_label(continuation, 1)
        return kk_kxmini_delay(1, continuation)
    }
    // After resume: reload the live value.
    let live = kk_coroutine_state_get_spill(continuation, 0)
    outThrown?.pointee = 0
    return kk_coroutine_state_exit(continuation, live + 1)
}

/// A suspend function that immediately resumes with exception.
@_cdecl("advcoro_throw_immediately")
func advcoro_throw_immediately(_ _: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    let exc = runtimeAllocateThrowable(message: "advcoro-exception")
    outThrown?.pointee = exc
    return 0
}

/// A suspend function that returns a fixed value (used for multi-launch tests).
@_cdecl("advcoro_return_fixed")
func advcoro_return_fixed(_ continuation: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    return kk_coroutine_state_exit(continuation, 42)
}

/// Nested suspend: delays twice (two suspension labels), saving values across both points.
private let advCoroNestedFunctionID = 8803
@_cdecl("advcoro_nested_two_delays")
func advcoro_nested_two_delays(_ continuation: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    let label = kk_coroutine_state_enter(continuation, advCoroNestedFunctionID)
    switch label {
    case 0:
        // First suspension: save partial result in spill slot 0.
        _ = kk_coroutine_state_set_spill(continuation, 0, 10)
        _ = kk_coroutine_state_set_label(continuation, 1)
        return kk_kxmini_delay(1, continuation)
    case 1:
        // Between first and second suspension: accumulate partial results.
        let partial = kk_coroutine_state_get_spill(continuation, 0)
        _ = kk_coroutine_state_set_spill(continuation, 0, partial + 20)
        _ = kk_coroutine_state_set_label(continuation, 2)
        return kk_kxmini_delay(1, continuation)
    default:
        // After second suspension: return accumulated value.
        let result = kk_coroutine_state_get_spill(continuation, 0)
        outThrown?.pointee = 0
        return kk_coroutine_state_exit(continuation, result)
    }
}

private let advCoroCancelLoopFunctionID = 8804

/// A cancellable suspend function that keeps looping until cancellation is observed.
@_cdecl("advcoro_cancel_loop")
func advcoro_cancel_loop(_ continuation: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    let label = kk_coroutine_state_enter(continuation, advCoroCancelLoopFunctionID)
    advancedCoroTestState.recordIteration()
    if label == 0 {
        _ = kk_coroutine_state_set_label(continuation, 1)
    }
    if kk_coroutine_check_cancellation(continuation, outThrown) != 0 {
        return kk_coroutine_state_exit(continuation, 0)
    }
    return kk_kxmini_delay(50, continuation)
}

/// Probes that `kk_with_context_full` propagates the coroutine name and dispatcher.
@_cdecl("advcoro_probe_with_context_full")
func advcoro_probe_with_context_full(_ continuation: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let nameMatches = RuntimeCoroutineScope.current?.name == "full-context" ? 1 : 0
    let dispatcherMatches = RuntimeDispatcher.current?.tag == kk_dispatcher_io() ? 1 : 0
    return kk_coroutine_state_exit(continuation, nameMatches * 10 + dispatcherMatches)
}

/// Produces three values into the channel received from `produce { ... }`.
@_cdecl("advcoro_produce_values")
func advcoro_produce_values(_ continuation: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    let channel = Int(kk_coroutine_launcher_arg_get(continuation, 0))
    let seed = Int(kk_coroutine_launcher_arg_get(continuation, 1))
    outThrown?.pointee = 0
    _ = kk_channel_send(channel, seed, continuation)
    _ = kk_channel_send(channel, seed + 1, continuation)
    _ = kk_channel_send(channel, seed + 2, continuation)
    return kk_coroutine_state_exit(continuation, 0)
}

// MARK: - Advanced Coroutine Tests (TEST-CORO-003)

/// Covers advanced coroutine runtime behaviours beyond the base 29 tests:
/// nested suspension, spill/reload across suspension points, exception propagation,
/// supervisor scope semantics, dispatcher dispatch, Result round-trips through
/// resumeWith, multi-spill slot state, timeout-or-null, exception handler invocation,
/// and recursive / chained suspend patterns.
final class RuntimeCoroutineAdvancedTests: IsolatedRuntimeXCTestCase {
    // swiftlint:disable:next static_over_final_class
    override class var requiredLockSet: RuntimeLockSet { .gcOnly }
    override func resetIsolatedRuntimeTestState() {
        advancedCoroTestState.reset()
    }

    // MARK: - Test 1: Two suspension labels / nested suspend state machine

    /// A CPS state machine that passes through two suspension labels correctly
    /// accumulates values in spill slots and returns the right result.
    func testNestedSuspendTwoLabelsAccumulatesSpills() {
        let entryRaw = unsafeBitCast(
            advcoro_nested_two_delays as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int,
            to: Int.self
        )
        let result = kk_kxmini_run_blocking(entryRaw, advCoroNestedFunctionID, nil)
        // First label: 10, second label: +20 = 30
        XCTAssertEqual(result, 30, "Two-label CPS state machine must accumulate spills correctly")
    }

    // MARK: - Test 2: Spill-reload round-trip across a single suspension point

    /// A live value stored in a spill slot before a suspension must survive the resume.
    func testSpillSlotRoundTripAcrossSuspension() {
        let entryRaw = unsafeBitCast(
            advcoro_spill_across_suspension as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int,
            to: Int.self
        )
        let result = kk_kxmini_run_blocking(entryRaw, advCoroSpillFunctionID, nil)
        // spill slot 0 = 777 before suspension; after resume we add 1 → 778
        XCTAssertEqual(result, 778, "Spill slot must survive one suspension-resume cycle")
    }

    // MARK: - Test 3: resumeWithException propagates through Result<T> round-trip

    /// A Result<T> that wraps a failure and is fed to resumeWith must propagate the exception
    /// to the continuation's thrownException field.
    func testResumeWithResultFailurePropagatesExceptionToState() {
        let fnID = 8810
        let cont = kk_coroutine_continuation_new(fnID)
        XCTAssertNotEqual(cont, 0)

        let exc = runtimeAllocateThrowable(message: "result-failure-advcoro")
        advCoroFailExcRaw = exc
        let failFn = unsafeBitCast(
            advcoro_fail_with_exc as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int,
            to: Int.self
        )
        var thrown = 0
        let resultRaw = runtimeResultRunCatching(failFn, 0, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(runtimeResultFailureFlag(resultRaw), 1)

        let sem = DispatchSemaphore(value: 0)

        let ptr = UnsafeMutableRawPointer(bitPattern: cont)!
        let state = Unmanaged<RuntimeContinuationState>.fromOpaque(ptr).takeUnretainedValue()
        // Capture thrownException via a separate nonisolated variable to avoid
        // Sendable analysis of RuntimeContinuationState inside the @Sendable closure.
        let thrownCapture = AdvThrownCapture()
        state.installResumeContinuation { [weak state] in
            thrownCapture.value = state?.thrownException ?? 0
            sem.signal()
        }

        DispatchQueue.global().async {
            kk_coroutine_continuation_resume_with(cont, resultRaw)
        }

        XCTAssertEqual(sem.wait(timeout: .now() + 5), .success)
        XCTAssertEqual(thrownCapture.value, exc, "Result.failure must propagate exception via resumeWith")
    }

    // MARK: - Test 4: Result<T> success round-trip through resumeWith

    /// A Result.success value fed to resumeWith must propagate the value (not an exception).
    func testResumeWithResultSuccessDeliversValue() {
        let fnID = 8811
        let cont = kk_coroutine_continuation_new(fnID)
        XCTAssertNotEqual(cont, 0)

        let successFn = unsafeBitCast(
            advcoro_return_512 as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int,
            to: Int.self
        )
        var thrown = 0
        let resultRaw = runtimeResultRunCatching(successFn, 0, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(runtimeResultSuccessFlag(resultRaw), 1)

        let sem = DispatchSemaphore(value: 0)

        let ptr = UnsafeMutableRawPointer(bitPattern: cont)!
        let state = Unmanaged<RuntimeContinuationState>.fromOpaque(ptr).takeUnretainedValue()
        let completionCapture = AdvThrownCapture()
        state.installResumeContinuation { [weak state] in
            completionCapture.value = state.map { Int($0.completion) } ?? -1
            sem.signal()
        }

        DispatchQueue.global().async {
            kk_coroutine_continuation_resume_with(cont, resultRaw)
        }

        XCTAssertEqual(sem.wait(timeout: .now() + 5), .success)
        XCTAssertEqual(completionCapture.value, 512, "Result.success must propagate value via resumeWith")
    }

    // MARK: - Test 5: Exception handler is invoked on uncaught exception

    /// kk_kxmini_launch_with_exception_handler must invoke the handler when the
    /// coroutine throws an uncaught exception.
    func testExceptionHandlerInvokedOnUncaughtException() {
        let handlerHandle = kk_exception_handler_new()
        XCTAssertNotEqual(handlerHandle, 0)

        // We track invocation via a side-channel: launch a coroutine that always
        // throws, and verify that the job completes with a non-zero "failure" value.
        let entryRaw = unsafeBitCast(
            advcoro_throw_immediately as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int,
            to: Int.self
        )
        let functionID = 8812
        let jobHandle = kk_kxmini_launch_with_exception_handler(entryRaw, functionID, handlerHandle)
        XCTAssertNotEqual(jobHandle, 0)

        // When an exception handler is installed and the coroutine throws,
        // the handler is invoked and the job is completed with 0 (handler consumes the exception).
        let joinResult = kk_job_join(jobHandle, 0)
        XCTAssertEqual(joinResult, 0, "Exception handler should consume the exception; job completes with 0")
    }

    /// kk_kxmini_launch_with_exception_handler must fail the job (not silently
    /// report success) when the coroutine throws and no handler was installed
    /// (handlerRaw == 0). Regression test for a fix flagged by PR review: this
    /// variant's no-handler fall-through used to call job.complete(with: result)
    /// unconditionally, discarding the thrown exception.
    func testExceptionHandlerVariantFailsJobWhenNoHandlerInstalled() {
        let entryRaw = unsafeBitCast(
            advcoro_throw_immediately as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int,
            to: Int.self
        )
        let functionID = 8815
        let jobHandle = kk_kxmini_launch_with_exception_handler(entryRaw, functionID, 0)
        XCTAssertNotEqual(jobHandle, 0)

        _ = kk_job_join(jobHandle, 0)
        XCTAssertEqual(
            kk_job_is_failed(jobHandle),
            1,
            "Uncaught exception with no handler installed must fail the job, not silently succeed"
        )
    }

    // MARK: - Test 6: launch_with_dispatcher uses the specified dispatcher

    /// kk_kxmini_launch_with_dispatcher should run the coroutine and return a job handle
    /// whose join delivers the expected result, regardless of which dispatcher is used.
    func testLaunchWithDefaultDispatcherDeliversResult() {
        let entryRaw = unsafeBitCast(
            advcoro_return_fixed as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int,
            to: Int.self
        )
        let functionID = 8813
        let dispatcher = kk_dispatcher_default()
        let jobHandle = kk_kxmini_launch_with_dispatcher(entryRaw, functionID, dispatcher)
        XCTAssertNotEqual(jobHandle, 0)
        let result = kk_job_join(jobHandle, 0)
        XCTAssertEqual(result, 42, "launch_with_dispatcher(Default) must deliver the coroutine's return value")
    }

    // MARK: - Test 7: launch_with_dispatcher IO dispatcher

    func testLaunchWithIODispatcherDeliversResult() {
        let entryRaw = unsafeBitCast(
            advcoro_return_fixed as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int,
            to: Int.self
        )
        let functionID = 8814
        let dispatcher = kk_dispatcher_io()
        let jobHandle = kk_kxmini_launch_with_dispatcher(entryRaw, functionID, dispatcher)
        XCTAssertNotEqual(jobHandle, 0)
        let result = kk_job_join(jobHandle, 0)
        XCTAssertEqual(result, 42, "launch_with_dispatcher(IO) must deliver the coroutine's return value")
    }

    // MARK: - Test 8: Supervisor scope isolates child failures

    /// A supervisor scope must not cancel sibling children when one child fails.
    /// Here we use supervisor_scope_run with an immediately-returning coroutine to
    /// verify the scope infrastructure works and returns the block result.
    func testSupervisorScopeRunReturnsBlockResult() {
        let entryRaw = unsafeBitCast(
            advcoro_return_fixed as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int,
            to: Int.self
        )
        var outThrown = 0
        let result = kk_supervisor_scope_run(entryRaw, 8815, &outThrown)
        XCTAssertEqual(outThrown, 0, "supervisor_scope_run with non-throwing block must not throw")
        XCTAssertEqual(result, 42, "supervisor_scope_run must return the block's result")
    }

    // MARK: - Test 9: Supervisor scope is active and not cancelled initially

    func testSupervisorScopeNewIsInitiallyActive() {
        let scopeHandle = kk_supervisor_scope_new()
        XCTAssertNotEqual(scopeHandle, 0)
        XCTAssertEqual(kk_coroutine_scope_is_active(scopeHandle), 1, "Supervisor scope should be active on creation")
        XCTAssertEqual(kk_coroutine_scope_is_cancelled(scopeHandle), 0, "Supervisor scope should not be cancelled on creation")
        XCTAssertEqual(kk_coroutine_scope_wait(scopeHandle), 0)
    }

    // MARK: - Test 10: withTimeoutOrNull returns null when block exceeds timeout

    /// kk_with_timeout_or_null must return the shared null-sentinel value (not raw 0, which
    /// is a legitimate unboxed Int result and indistinguishable from a real value once
    /// printed/compared) when the block takes longer than the deadline.
    func testWithTimeoutOrNullReturnsNullOnTimeout() {
        let entryRaw = unsafeBitCast(
            advcoro_delay_then_return as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int,
            to: Int.self
        )
        let continuation = kk_coroutine_continuation_new(advCoroDelayFunctionID)
        // Use a 0 ms timeout: the block should not complete in time.
        let result = kk_with_timeout_or_null(0, entryRaw, continuation)
        XCTAssertEqual(result, runtimeNullSentinelInt, "withTimeoutOrNull should return the null sentinel when block exceeds timeout")
    }

    // MARK: - Test 11: withTimeoutOrNull returns block value when block completes in time

    func testWithTimeoutOrNullReturnsValueWhenBlockCompletesInTime() {
        let entryRaw = unsafeBitCast(
            advcoro_return_fixed as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int,
            to: Int.self
        )
        let continuation = kk_coroutine_continuation_new(8816)
        // 5000 ms timeout — the instant-return block will always finish in time.
        let result = kk_with_timeout_or_null(5000, entryRaw, continuation)
        XCTAssertEqual(result, 42, "withTimeoutOrNull should return the block value when it completes in time")
    }

    // MARK: - Test 12: Multiple spill slots are independent

    /// Setting two distinct spill slots and reading them back after a suspension
    /// must return the correct value for each slot independently.
    func testMultipleSpillSlotsAreIndependent() {
        let continuation = kk_coroutine_continuation_new(8817)
        defer { _ = kk_coroutine_state_exit(continuation, 0) }

        _ = kk_coroutine_state_set_spill(continuation, 0, 111)
        _ = kk_coroutine_state_set_spill(continuation, 1, 222)
        _ = kk_coroutine_state_set_spill(continuation, 2, 333)

        XCTAssertEqual(kk_coroutine_state_get_spill(continuation, 0), 111)
        XCTAssertEqual(kk_coroutine_state_get_spill(continuation, 1), 222)
        XCTAssertEqual(kk_coroutine_state_get_spill(continuation, 2), 333)
        // Unset slot must return 0.
        XCTAssertEqual(kk_coroutine_state_get_spill(continuation, 9), 0)
    }

    // MARK: - Test 13: CoroutineContext merge: right-hand element wins on collision

    /// When two contexts each containing a CoroutineName are merged with +,
    /// the right-hand name must take precedence (mirrors Kotlin semantics).
    func testContextMergeRightHandWinsOnNameCollision() {
        let boxA = RuntimeStringBox("Alpha")
        let ptrA = runtimeRegisterAdvStringBox(boxA)
        let nameA = kk_coroutine_name_create(ptrA)

        let boxB = RuntimeStringBox("Beta")
        let ptrB = runtimeRegisterAdvStringBox(boxB)
        let nameB = kk_coroutine_name_create(ptrB)

        let emptyCtx = kk_coroutine_continuation_context(kk_coroutine_continuation_new(8818))
        let ctxA = kk_context_plus(emptyCtx, nameA)
        let ctxAB = kk_context_plus(ctxA, nameB)

        let nameHandleRaw = kk_context_get_name(ctxAB)
        XCTAssertNotEqual(nameHandleRaw, 0)
        let nameValue = runtimeAdvStringBoxValue(nameHandleRaw)
        XCTAssertEqual(nameValue, "Beta", "Right-hand CoroutineName must win on context collision")
    }

    // MARK: - Test 14: Coroutine yield is a non-blocking no-op

    /// kk_coroutine_yield must return 0 promptly without blocking or crashing.
    func testCoroutineYieldReturnsZeroAndDoesNotBlock() {
        let start = Date()
        let result = kk_coroutine_yield()
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertEqual(result, 0, "kk_coroutine_yield must return 0 (Unit)")
        XCTAssertLessThan(elapsed, 1.0, "kk_coroutine_yield must not block for more than 1 second")
    }

    // MARK: - Test 15: Concurrent launches converge via job_join

    /// Launching two concurrent coroutines and joining both must return each one's
    /// independent result without interference.
    func testConcurrentLaunchesReturnIndependentResults() {
        let baseline = advancedCoroTestState.iterationsSnapshot()

        let entry1 = unsafeBitCast(
            advcoro_return_fixed as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int,
            to: Int.self
        )
        let entry2 = unsafeBitCast(
            advcoro_add_constant as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int,
            to: Int.self
        )

        let cont2 = kk_coroutine_continuation_new(8820)
        _ = kk_coroutine_launcher_arg_set(cont2, 0, 7)

        let job1 = kk_kxmini_launch(entry1, 8819)
        let job2 = kk_kxmini_launch_with_cont(entry2, cont2)

        XCTAssertNotEqual(job1, 0)
        XCTAssertNotEqual(job2, 0)

        let result1 = kk_job_join(job1, 0)
        let result2 = kk_job_join(job2, 0)

        XCTAssertEqual(result1, 42, "First concurrent launch must return 42")
        XCTAssertEqual(result2, 107, "Second concurrent launch must return arg(7)+100=107")
        _ = baseline // suppress unused warning
    }

    // MARK: - Test 16: withContext_full propagates scope name and dispatcher

    func testWithContextFullPropagatesScopeNameAndDispatcher() {
        let nameBox = RuntimeStringBox("full-context")
        let namePtr = runtimeRegisterAdvStringBox(nameBox)
        let nameHandle = kk_coroutine_name_create(namePtr)
        let contextHandle = kk_context_plus(kk_dispatcher_io(), nameHandle)
        defer { kk_context_release(contextHandle) }

        let continuation = kk_coroutine_continuation_new(8821)
        let scope = RuntimeCoroutineScope()
        let savedScope = RuntimeCoroutineScope.current
        RuntimeCoroutineScope.current = scope
        defer { RuntimeCoroutineScope.current = savedScope }

        if let state = runtimeContinuationState(from: continuation) {
            state.scope = scope
        }

        let entryRaw = unsafeBitCast(
            advcoro_probe_with_context_full as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int,
            to: Int.self
        )
        let result = kk_with_context_full(contextHandle, entryRaw, continuation)
        XCTAssertEqual(result, 11, "withContext_full should propagate both CoroutineName and dispatcher")
    }

    // MARK: - Test 17: coroutineScope run with continuation returns captured value

    func testCoroutineScopeRunWithContReturnsCapturedValue() {
        let continuation = kk_coroutine_continuation_new(8822)
        _ = kk_coroutine_launcher_arg_set(continuation, 0, 7)
        let entryRaw = unsafeBitCast(
            advcoro_add_constant as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int,
            to: Int.self
        )

        var outThrown = 0
        let result = kk_coroutine_scope_run_with_cont(entryRaw, continuation, &outThrown)
        XCTAssertEqual(outThrown, 0, "coroutineScope run with cont should not throw")
        XCTAssertEqual(result, 107, "coroutineScope run with cont should return the block result")
    }

    // MARK: - Test 18: supervisorScope run with continuation returns captured value

    func testSupervisorScopeRunWithContReturnsCapturedValue() {
        let continuation = kk_coroutine_continuation_new(8823)
        _ = kk_coroutine_launcher_arg_set(continuation, 0, 9)
        let entryRaw = unsafeBitCast(
            advcoro_add_constant as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int,
            to: Int.self
        )

        var outThrown = 0
        let result = kk_supervisor_scope_run_with_cont(entryRaw, continuation, &outThrown)
        XCTAssertEqual(outThrown, 0, "supervisorScope run with cont should not throw")
        XCTAssertEqual(result, 109, "supervisorScope run with cont should return the block result")
    }

    // MARK: - Test 19: context_cancel_no_cause cancels a running job

    func testContextCancelNoCauseCancelsRunningJob() {
        let baseline = advancedCoroTestState.iterationsSnapshot()
        let entryRaw = unsafeBitCast(
            advcoro_cancel_loop as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int,
            to: Int.self
        )
        let jobHandle = kk_kxmini_launch(entryRaw, advCoroCancelLoopFunctionID)
        XCTAssertNotEqual(jobHandle, 0)

        let deadline = Date().addingTimeInterval(2.0)
        while advancedCoroTestState.iterationsSnapshot() == baseline && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        XCTAssertGreaterThan(
            advancedCoroTestState.iterationsSnapshot(),
            baseline,
            "Cancellable coroutine should start before cancellation"
        )

        let contextHandle = kk_context_plus(jobHandle, kk_dispatcher_default())
        defer { kk_context_release(contextHandle) }

        _ = kk_context_cancel_no_cause(contextHandle)
        XCTAssertEqual(kk_job_is_cancelled(jobHandle), 1, "Job should report cancellation after context cancel")

        let joinResult = kk_job_join(jobHandle, 0)
        XCTAssertEqual(
            kk_is_cancellation_exception(joinResult),
            1,
            "Joined result should be a CancellationException after context cancel"
        )
    }

    // MARK: - Test 20: produce returns a channel that streams values

    func testProduceReturnsChannelThatStreamsCapturedValues() {
        let entryRaw = unsafeBitCast(
            advcoro_produce_values as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int,
            to: Int.self
        )

        let channelHandle = kk_produce(entryRaw, 20)
        XCTAssertNotEqual(channelHandle, 0)

        var value = 0
        XCTAssertEqual(kk_channel_receive(channelHandle, 0, &value), kChannelResultSuccess)
        XCTAssertEqual(value, 20)
        XCTAssertEqual(kk_channel_receive(channelHandle, 0, &value), kChannelResultSuccess)
        XCTAssertEqual(value, 21)
        XCTAssertEqual(kk_channel_receive(channelHandle, 0, &value), kChannelResultSuccess)
        XCTAssertEqual(value, 22)

        let finalStatus = kk_channel_receive(channelHandle, 0, &value)
        XCTAssertEqual(kk_channel_is_closed_token(finalStatus), 1, "Channel should close after the producer completes")
        XCTAssertEqual(kk_channel_is_closed_for_receive(channelHandle), 1, "Channel should report closed-for-receive after draining")
    }

    // MARK: - Test 21: produce with continuation uses the existing continuation

    func testProduceWithContinuationUsesExistingContinuation() {
        let continuation = kk_coroutine_continuation_new(8824)
        _ = kk_coroutine_launcher_arg_set(continuation, 1, 77)
        let entryRaw = unsafeBitCast(
            advcoro_produce_values as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int,
            to: Int.self
        )

        let channelHandle = kk_kxmini_produce_with_cont(entryRaw, continuation)
        XCTAssertNotEqual(channelHandle, 0)

        var value = 0
        XCTAssertEqual(kk_channel_receive(channelHandle, 0, &value), kChannelResultSuccess)
        XCTAssertEqual(value, 77)
        XCTAssertEqual(kk_channel_receive(channelHandle, 0, &value), kChannelResultSuccess)
        XCTAssertEqual(value, 78)
        XCTAssertEqual(kk_channel_receive(channelHandle, 0, &value), kChannelResultSuccess)
        XCTAssertEqual(value, 79)

        let finalStatus = kk_channel_receive(channelHandle, 0, &value)
        XCTAssertEqual(kk_channel_is_closed_token(finalStatus), 1, "Channel should close after the producer completes")
        XCTAssertEqual(kk_channel_is_closed_for_receive(channelHandle), 1)
    }

    // MARK: - Test 22: Semaphore acquire / release / permit tracking

    func testSemaphoreAcquireReleaseAndPermitTracking() {
        let semaphoreHandle = kk_semaphore_create(1)
        XCTAssertNotEqual(semaphoreHandle, 0)
        XCTAssertEqual(kk_semaphore_availablePermits(semaphoreHandle), 1)
        XCTAssertEqual(kk_semaphore_tryAcquire(semaphoreHandle), 1)
        XCTAssertEqual(kk_semaphore_availablePermits(semaphoreHandle), 0)

        let continuation = kk_coroutine_continuation_new(8825)
        defer { _ = kk_coroutine_state_exit(continuation, 0) }

        let resumed = DispatchSemaphore(value: 0)
        if let state = runtimeContinuationState(from: continuation) {
            state.installResumeContinuation {
                resumed.signal()
            }
        }

        let suspendedToken = Int(bitPattern: kk_coroutine_suspended())
        XCTAssertEqual(kk_semaphore_acquire(semaphoreHandle, continuation), suspendedToken)
        XCTAssertEqual(kk_semaphore_availablePermits(semaphoreHandle), 0)

        XCTAssertEqual(kk_semaphore_release(semaphoreHandle), 0)
        XCTAssertEqual(resumed.wait(timeout: .now() + 2.0), .success, "Semaphore release should resume the suspended continuation")
        XCTAssertEqual(kk_semaphore_availablePermits(semaphoreHandle), 0)
        XCTAssertEqual(kk_semaphore_tryAcquire(semaphoreHandle), 0)
    }
}

// MARK: - Private helpers

/// Sendable capture box for a single Int value (used to capture state fields
/// across @Sendable closures without making RuntimeContinuationState Sendable).
private final class AdvThrownCapture: @unchecked Sendable {
    var value: Int = 0
}

private func runtimeRegisterAdvStringBox(_ box: RuntimeStringBox) -> Int {
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

private func runtimeAdvStringBoxValue(_ raw: Int) -> String {
    guard raw != 0,
          let ptr = UnsafeMutableRawPointer(bitPattern: raw),
          let box = tryCast(ptr, to: RuntimeStringBox.self)
    else { return "" }
    return box.value
}

// MARK: - AdvancedCoroutineTestState

private final class AdvancedCoroutineTestState: @unchecked Sendable {
    private let lock = NSLock()
    private var _iterations = 0

    func reset() {
        lock.lock()
        _iterations = 0
        lock.unlock()
    }

    func iterationsSnapshot() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return _iterations
    }

    func recordIteration() {
        lock.lock()
        _iterations += 1
        lock.unlock()
    }
}
