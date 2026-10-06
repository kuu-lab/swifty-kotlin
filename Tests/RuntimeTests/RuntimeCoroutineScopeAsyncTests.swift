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

private func scopeLaunchNested(_ continuation: Int, _ thrown: UnsafeMutablePointer<Int>?) -> Int {
    thrown?.pointee = 0
    let scope = Int(kk_coroutine_launcher_arg_get(continuation, 0))
    let childContinuation = Int(kk_coroutine_launcher_arg_get(continuation, 1))
    typealias Entry = @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int
    let entry = unsafeBitCast(scopeAsyncReceiverFirst as Entry, to: Int.self)
    _ = __kk_coroutine_scope_launch_context_with_cont(scope, 0, 1, entry, childContinuation, 0)
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
        // The continuation's scope is a fresh child scope carrying the async
        // task's Job — nested builders must attach to the task, not the
        // receiver scope (DeferredCoroutine contract).
        let task = try #require(runtimeAsyncTask(from: handle))
        #expect(state.scope !== runtimeCoroutineScope(from: scope))
        #expect(state.scope?.job === task.completionJob)
        #expect(state.scope?.context.jobHandleRaw == handle)
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
    @Test(arguments: [0, 1, 2, 3])
    func launchContextReturnsJoinableJobAndPreservesCaptures(start: Int) throws {
        let scope = kk_coroutine_scope_new_with_context(0)
        let context = runtimeRegisterObject(RuntimeCoroutineContext(name: "launch"))
        let continuation = kk_coroutine_continuation_new(9610)
        let state = try #require(runtimeContinuationState(from: continuation))
        _ = kk_coroutine_launcher_arg_set(continuation, 0, 41)
        let entry = unsafeBitCast(scopeAsyncCapture as Entry, to: Int.self)
        let job = __kk_coroutine_scope_launch_context_with_cont(scope, context, start, entry, continuation, 1)
        if start == 1 {
            #expect(kk_job_is_active(job) == 0)
            #expect(kk_job_start(job) == 1)
        }
        _ = kk_job_join(job, 0)
        #expect(kk_job_is_completed(job) == 1)
        #expect(kk_job_is_cancelled(job) == 0)
        #expect(state.builderContext?.name == "launch")
        #expect(state.builderContext?.jobHandleRaw == job)
        let finishedContext = runtimeRegisterObject(try #require(state.builderContext))
        #expect(kk_context_is_active(finishedContext) == 0)
        #expect(kk_coroutine_scope_wait(scope) == runtimeNullSentinelInt)
    }

    @Test
    func launchContextAcceptsBoxedReceiverBlock() {
        let scope = kk_coroutine_scope_new_with_context(0)
        let entry = unsafeBitCast(scopeAsyncClosure as ClosureEntry, to: Int.self)
        var thrown = 0
        let boxed = kk_function_create_0(entry, 41, &thrown)
        let job = __kk_coroutine_scope_launch_context(scope, 0, 3, boxed, 0)
        _ = kk_job_join(job, 0)
        #expect(kk_job_is_completed(job) == 1)
        #expect(kk_coroutine_scope_wait(scope) == runtimeNullSentinelInt)
    }

    @Test
    func launchWaitsForDescendantsAndInheritsChildContext() throws {
        let scope = kk_coroutine_scope_new_with_context(0)
        let context = runtimeRegisterObject(RuntimeCoroutineContext(name: "outer"))
        let outer = kk_coroutine_continuation_new(9620)
        let inner = kk_coroutine_continuation_new(9621)
        let state = try #require(runtimeContinuationState(from: inner))
        _ = kk_coroutine_launcher_arg_set(outer, 1, Int64(inner))
        _ = kk_coroutine_launcher_arg_set(inner, 1, 41)
        let entry = unsafeBitCast(scopeLaunchNested as Entry, to: Int.self)
        let job = __kk_coroutine_scope_launch_context_with_cont(scope, context, 1, entry, outer, 0)
        _ = kk_job_join(job, 0)
        #expect(state.builderContext?.name == "outer")
        #expect(kk_job_is_completed(job) == 1)
        #expect(state.jobHandle?.completedSnapshot() == true)
        #expect(kk_coroutine_scope_wait(scope) == runtimeNullSentinelInt)
    }

    @Test
    func supervisorLaunchReportsFailureToContextHandler() {
        let exception = runtimeAllocateThrowable(message: "launch-failure")
        let called = DispatchSemaphore(value: 0)
        let handler = RuntimeExceptionHandlerBox { context, failure in
            #expect(failure == exception)
            #expect(kk_context_get_name(context) != 0)
            #expect(runtimeAsyncTask(from: kk_context_get_job(context)) != nil)
            #expect(kk_job_is_completed(kk_context_get_job(context)) == 1)
            #expect(kk_job_is_cancelled(kk_context_get_job(context)) == 1)
            called.signal()
        }
        let parent = kk_supervisor_job_new()
        let context = runtimeRegisterObject(RuntimeCoroutineContext(
            name: "handler", exceptionHandler: handler, jobHandleRaw: parent
        ))
        let scope = kk_coroutine_scope_new_with_context(context)
        let continuation = kk_coroutine_continuation_new(9630)
        _ = kk_coroutine_launcher_arg_set(continuation, 0, Int64(exception))
        let entry = unsafeBitCast(scopeAsyncFailure as Entry, to: Int.self)
        let job = __kk_coroutine_scope_launch_context_with_cont(scope, 0, 3, entry, continuation, 1)
        _ = kk_job_join(job, 0)
        #expect(called.wait(timeout: .now() + 2) == .success)
        #expect(kk_job_is_cancelled(parent) == 0)
        #expect(kk_job_is_cancelled(job) == 1)
        _ = kk_coroutine_scope_wait(scope)
    }

    @Test
    func nonCancellableOverrideDoesNotCancelSingletonOnFailure() {
        let exception = runtimeAllocateThrowable(message: "detached-launch-failure")
        let called = DispatchSemaphore(value: 0)
        let handler = RuntimeExceptionHandlerBox { _, failure in
            #expect(failure == exception)
            called.signal()
        }
        let scopeContext = runtimeRegisterObject(RuntimeCoroutineContext(exceptionHandler: handler))
        let scope = kk_coroutine_scope_new_with_context(scopeContext)
        let continuation = kk_coroutine_continuation_new(9631)
        _ = kk_coroutine_launcher_arg_set(continuation, 0, Int64(exception))
        let entry = unsafeBitCast(scopeAsyncFailure as Entry, to: Int.self)
        let parent = kk_non_cancellable_instance()
        let job = __kk_coroutine_scope_launch_context_with_cont(scope, parent, 3, entry, continuation, 1)
        _ = kk_job_join(job, 0)
        #expect(called.wait(timeout: .now() + 2) == .success)
        #expect(kk_job_is_active(parent) == 1)
        #expect(kk_job_is_cancelled(parent) == 0)
        #expect(kk_coroutine_scope_wait(scope) == runtimeNullSentinelInt)
    }

    @Test
    func taskBackedLaunchExposesItsCancellationCause() {
        let scope = kk_coroutine_scope_new_with_context(0)
        let continuation = kk_coroutine_continuation_new(9640)
        let entry = unsafeBitCast(scopeAsyncReceiverFirst as Entry, to: Int.self)
        let job = __kk_coroutine_scope_launch_context_with_cont(scope, 0, 1, entry, continuation, 0)
        let cause = runtimeAllocateCancellationException(message: "launch-cancelled")
        _ = kk_job_cancel_with_cause(job, cause)
        _ = kk_job_join(job, 0)
        #expect(kk_job_get_cancellation_exception(job) == cause)
        #expect(kk_coroutine_scope_wait(scope) == runtimeNullSentinelInt)
        _ = kk_coroutine_state_exit(continuation, 0)
    }

}
