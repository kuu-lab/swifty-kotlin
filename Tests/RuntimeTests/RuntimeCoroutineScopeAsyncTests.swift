import Foundation
@testable import Runtime
import Testing

private func scopeAsyncCapture(_ continuation: Int, _ thrown: UnsafeMutablePointer<Int>?) -> Int {
    thrown?.pointee = 0
    return kk_coroutine_state_exit(continuation, Int(kk_coroutine_launcher_arg_get(continuation, 0)) + 1)
}

private func scopeAsyncReceiverFirst(_ continuation: Int, _ thrown: UnsafeMutablePointer<Int>?) -> Int {
    thrown?.pointee = 0
    // Receiver-first thunk shape (`[receiver, cap0..]`): launcherArgs[0] is
    // the receiver scope handle, captures start at slot 1.
    let receiver = kk_coroutine_launcher_arg_get(continuation, 0)
    let capture = kk_coroutine_launcher_arg_get(continuation, 1)
    return kk_coroutine_state_exit(continuation, receiver != 0 ? Int(capture) + 1 : -1)
}

private func scopeAsyncClosure(_ captured: Int, _ receiver: Int, _ thrown: UnsafeMutablePointer<Int>?) -> Int {
    thrown?.pointee = 0
    return receiver != 0 ? captured + 1 : -1
}

private func scopeAsyncFailure(_ continuation: Int, _ thrown: UnsafeMutablePointer<Int>?) -> Int {
    let exception = kk_coroutine_launcher_arg_get(continuation, 0)
    thrown?.pointee = Int(exception)
    return kk_coroutine_state_exit(continuation, 0)
}

@Suite
struct RuntimeCoroutineScopeAsyncTests {
    private typealias Entry = @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int
    private typealias ClosureEntry = @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int

    @Test
    func testSchedulerClockUsesWordABIWithoutTruncatingLongValues() {
        let currentTime: (Int) -> Int = kk_test_scheduler_current_time
        let scopeTime: (Int) -> Int = kk_test_scope_current_time
        let advanceTime: (Int, Int) -> Int = kk_test_scheduler_advance_time_by
        let scope = kk_coroutine_scope_new_with_context(0)
        let scheduler = kk_test_scope_scheduler(scope)

        #expect(currentTime(scheduler) == 0)
        #expect(scopeTime(scope) == 0)
        _ = advanceTime(scheduler, 4_294_967_296)
        #expect(currentTime(scheduler) == 4_294_967_296)
        #expect(scopeTime(scope) == 4_294_967_296)
    }

    @Test(arguments: [0, 1, 2, 3])
    func capturesReturnDeferredValues(start: Int) throws {
        let scope = kk_coroutine_scope_new_with_context(0)
        let continuation = kk_coroutine_continuation_new(9600)
        _ = kk_coroutine_launcher_arg_set(continuation, 0, 41)
        let entry = unsafeBitCast(scopeAsyncCapture as Entry, to: Int.self)
        let handle = kk_coroutine_scope_async_with_cont(scope, 0, start, entry, continuation, 1)
        if start == 1 {
            #expect(kk_job_is_active(handle) == 0)
        }
        #expect(kk_kxmini_async_await(handle, 0) == 42)
        #expect(kk_coroutine_scope_wait(scope) == runtimeNullSentinelInt)
    }

    @Test
    func receiverScopeSeedsMarkedThunkSlotZero() throws {
        let scope = kk_coroutine_scope_new_with_context(0)
        let continuation = kk_coroutine_continuation_new(9605)
        _ = kk_coroutine_launcher_arg_set(continuation, 0, 0)
        _ = kk_coroutine_launcher_arg_set(continuation, 1, 41)
        let entry = unsafeBitCast(scopeAsyncReceiverFirst as Entry, to: Int.self)
        let handle = kk_coroutine_scope_async_with_cont(scope, 0, 3, entry, continuation, 0)
        #expect(kk_kxmini_async_await(handle, 0) == 42)
        #expect(kk_coroutine_scope_wait(scope) == runtimeNullSentinelInt)
    }

    @Test
    func closureValueBridgePreservesEnvironment() {
        let scope = kk_coroutine_scope_new_with_context(0)
        let entry = unsafeBitCast(scopeAsyncClosure as ClosureEntry, to: Int.self)
        let handle = kk_coroutine_scope_async(scope, 0, 3, entry, 41)
        #expect(kk_kxmini_async_await(handle, 0) == 42)
        #expect(kk_coroutine_scope_wait(scope) == runtimeNullSentinelInt)
    }

    @Test
    func boxedClosureWithZeroEnvironmentPreservesAmbientScope() {
        let ambient = kk_coroutine_scope_new_with_context(0)
        let scope = kk_coroutine_scope_new_with_context(0)
        let saved = RuntimeCoroutineScope.current
        RuntimeCoroutineScope.current = runtimeCoroutineScope(from: ambient)
        defer { RuntimeCoroutineScope.current = saved }
        let entry = unsafeBitCast(scopeAsyncClosure as ClosureEntry, to: Int.self)
        var thrown = 0
        let boxed = kk_function_create_0(entry, 0, &thrown)
        let handle = kk_coroutine_scope_async(scope, 0, 3, boxed, 0)
        #expect(kk_kxmini_async_await(handle, 0) == 1)
        #expect(RuntimeCoroutineScope.current === runtimeCoroutineScope(from: ambient))
        _ = kk_coroutine_scope_wait(scope)
        _ = kk_coroutine_scope_wait(ambient)
    }

    @Test
    func receiverOwnsChildRatherThanAmbientScope() {
        let ambient = kk_coroutine_scope_new_with_context(0)
        let receiver = kk_coroutine_scope_new_with_context(0)
        let savedScope = RuntimeCoroutineScope.current
        RuntimeCoroutineScope.current = runtimeCoroutineScope(from: ambient)
        defer { RuntimeCoroutineScope.current = savedScope }
        let continuation = kk_coroutine_continuation_new(9601)
        let entry = unsafeBitCast(scopeAsyncCapture as Entry, to: Int.self)
        let handle = kk_coroutine_scope_async_with_cont(receiver, 0, 1, entry, continuation, 1)
        _ = kk_coroutine_scope_cancel(ambient)
        #expect(kk_job_is_cancelled(handle) == 0)
        _ = kk_coroutine_scope_cancel(receiver)
        #expect(kk_job_is_cancelled(handle) == 1)
        _ = kk_coroutine_scope_wait(ambient)
        _ = kk_coroutine_scope_wait(receiver)
        _ = kk_coroutine_state_exit(continuation, 0)
    }

    @Test
    func contextOverridesReceiverElements() throws {
        let inherited = runtimeRegisterObject(RuntimeCoroutineContext(name: "parent"))
        let scope = kk_coroutine_scope_new_with_context(inherited)
        let override = runtimeRegisterObject(RuntimeCoroutineContext(name: "child"))
        let continuation = kk_coroutine_continuation_new(9602)
        let entry = unsafeBitCast(scopeAsyncCapture as Entry, to: Int.self)
        let handle = kk_coroutine_scope_async_with_cont(scope, override, 1, entry, continuation, 1)
        let state = try #require(runtimeContinuationState(from: continuation))
        #expect(state.makeContinuationContext().name == "child")
        #expect(state.scope === runtimeCoroutineScope(from: scope))
        #expect(kk_kxmini_async_await(handle, 0) == 1)
        #expect(kk_coroutine_scope_wait(scope) == runtimeNullSentinelInt)
    }

    @Test(arguments: [0, 3])
    func failureIsStoredAndPublishedToAwait(start: Int) throws {
        let scope = kk_coroutine_scope_new_with_context(0)
        let exception = runtimeAllocateThrowable(message: "scope-async-failure")
        let continuation = kk_coroutine_continuation_new(9603)
        _ = kk_coroutine_launcher_arg_set(continuation, 0, Int64(exception))
        let entry = unsafeBitCast(scopeAsyncFailure as Entry, to: Int.self)
        let handle = kk_coroutine_scope_async_with_cont(scope, 0, start, entry, continuation, 1)
        let caller = kk_coroutine_continuation_new(9604)
        let callerState = try #require(runtimeContinuationState(from: caller))
        _ = kk_kxmini_async_await(handle, caller)
        #expect(kk_coroutine_scope_wait(scope) == exception)
        #expect(callerState.thrownException == exception)
        _ = kk_coroutine_state_exit(caller, 0)
    }
}
