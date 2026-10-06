import Foundation
@testable import Runtime
import Testing

private typealias AwaitCancellationEntry = @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int

@_cdecl("runtime_test_await_cancellation_wrapper_body")
func runtime_test_await_cancellation_wrapper_body(_ continuation: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    if kk_coroutine_state_enter(continuation, 9_584) == 0 {
        _ = kk_coroutine_state_set_label(continuation, 1)
        return kk_await_cancellation(continuation)
    }
    outThrown?.pointee = kk_coroutine_state_get_thrown_exception(continuation)
    return kk_coroutine_state_exit(continuation, 0)
}

@_cdecl("runtime_test_suspend_wrapper_throw_body")
func runtime_test_suspend_wrapper_throw_body(_ continuation: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = runtimeAllocateThrowable(message: "wrapper failure")
    return kk_coroutine_state_exit(continuation, 0)
}

@_cdecl("runtime_test_suspend_wrapper_throw_thunk")
func runtime_test_suspend_wrapper_throw_thunk(_ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    let entry = unsafeBitCast(runtime_test_suspend_wrapper_throw_body as AwaitCancellationEntry, to: Int.self)
    return kk_coroutine_call_suspend_wrapper(entry, kk_coroutine_continuation_new(9_585), outThrown)
}

@Suite(.runtimeIsolation(.gcOnly))
struct RuntimeAwaitCancellationTests {
    @Test(arguments: [false, true])
    func scopeJobCancellationWakesAwaitAndRestoresEnclosingJob(isSupervisor: Bool) {
        let previousState = RuntimeContinuationState.current
        let previousScope = RuntimeCoroutineScope.current
        let previousJob = RuntimeJobHandle.current
        let previousLoop = RuntimeEventLoop.current
        defer {
            RuntimeContinuationState.current = previousState
            RuntimeCoroutineScope.current = previousScope
            RuntimeJobHandle.current = previousJob
            RuntimeEventLoop.current = previousLoop
        }
        let continuation = kk_coroutine_continuation_new(9_588)
        let state = runtimeContinuationState(from: continuation)!
        let enclosingJob = RuntimeJobHandle()
        enclosingJob.markStarted()
        state.jobHandle = enclosingJob
        RuntimeContinuationState.current = state
        RuntimeCoroutineScope.current = nil
        RuntimeJobHandle.current = enclosingJob
        let scopeRaw = isSupervisor ? kk_supervisor_scope_new() : kk_coroutine_scope_new()
        let scope = runtimeCoroutineScope(from: scopeRaw)!
        #expect(state.jobHandle === scope.job)
        #expect(RuntimeJobHandle.current === scope.job)
        let loop = RuntimeEventLoop()
        state.eventLoop = loop
        RuntimeEventLoop.current = loop
        #expect(kk_await_cancellation(continuation) == Int(bitPattern: kk_coroutine_suspended()))
        let resumed = RuntimeCompletionFlag()
        state.installResumeContinuation { resumed.set() }
        _ = scope.job!.cancel()
        let didResume = loop.run(until: { resumed.isSet }, deadline: Date().addingTimeInterval(1))
        #expect(didResume)
        state.consumeCancellableDelivery()
        #expect(state.thrownException == scope.job!.cancellationCauseSnapshot())
        _ = kk_coroutine_scope_wait(scopeRaw)
        #expect(state.jobHandle === enclosingJob)
        #expect(RuntimeJobHandle.current === enclosingJob)
        #expect(!enclosingJob.cancellationSnapshot())
        _ = enclosingJob.complete(with: 0)
    }

    @Test func suspendWrapperReturnsBeforeItsParkedBodyCompletes() {
        let previousState = RuntimeContinuationState.current
        let previousLoop = RuntimeEventLoop.current
        defer {
            RuntimeContinuationState.current = previousState
            RuntimeEventLoop.current = previousLoop
        }
        let callerRaw = kk_coroutine_continuation_new(9_586)
        let caller = runtimeContinuationState(from: callerRaw)!
        let job = RuntimeJobHandle()
        job.markStarted()
        caller.jobHandle = job
        let loop = RuntimeEventLoop()
        caller.eventLoop = loop
        RuntimeEventLoop.current = loop
        RuntimeContinuationState.current = caller
        let entry = unsafeBitCast(runtime_test_await_cancellation_wrapper_body as AwaitCancellationEntry, to: Int.self)
        var thrown = 0
        let result = kk_coroutine_call_suspend_wrapper(entry, kk_coroutine_continuation_new(9_584), &thrown)
        #expect(result == Int(bitPattern: kk_coroutine_suspended()))
        #expect(thrown == 0)
        let resumed = RuntimeCompletionFlag()
        caller.installResumeContinuation { resumed.set() }
        _ = job.cancel()
        let didResume = loop.run(until: { resumed.isSet }, deadline: Date().addingTimeInterval(1))
        #expect(didResume)
        #expect(caller.thrownException == job.cancellationCauseSnapshot())
        _ = job.complete(with: 0)
    }

    @Test func suspendFunctionValuePreservesImmediateWrapperFailure() {
        let previousState = RuntimeContinuationState.current
        defer { RuntimeContinuationState.current = previousState }
        let callerRaw = kk_coroutine_continuation_new(9_587)
        let caller = runtimeContinuationState(from: callerRaw)!
        RuntimeContinuationState.current = caller
        typealias Thunk = @convention(c) (UnsafeMutablePointer<Int>?) -> Int
        let thunk = unsafeBitCast(runtime_test_suspend_wrapper_throw_thunk as Thunk, to: Int.self)
        var thrown = 0
        let result = kk_suspend_function_invoke_0(thunk, callerRaw, &thrown)
        #expect(result == Int(bitPattern: kk_coroutine_suspended()))
        #expect(thrown == 0)
        #expect(caller.thrownException != 0)
    }

    @Test func suspendWrapperForOrdinaryCallerForwardsFailure() {
        let previousState = RuntimeContinuationState.current
        defer { RuntimeContinuationState.current = previousState }
        RuntimeContinuationState.current = nil
        var thrown = 0
        _ = runtime_test_suspend_wrapper_throw_thunk(&thrown)
        #expect(thrown != 0)
    }

    @Test(arguments: [false, true], [false, true])
    func scopeCancellationWakesParkedContinuation(isSupervisor: Bool, cancelledBeforeParking: Bool) {
        let previousJob = RuntimeJobHandle.current
        let parent = RuntimeJobHandle()
        parent.markStarted()
        RuntimeJobHandle.current = parent
        defer { RuntimeJobHandle.current = previousJob }

        let scope = RuntimeCoroutineScope(isSupervisor: isSupervisor)
        let scopeJob = scope.installJob()
        let continuation = kk_coroutine_continuation_new(9_580)
        let state = runtimeContinuationState(from: continuation)!
        state.scope = scope
        state.jobHandle = scopeJob
        // A scope block's continuation is not the job's launcher continuation.
        #expect(scopeJob.continuationState == nil)
        let loop = RuntimeEventLoop()
        state.eventLoop = loop
        let resumed = RuntimeCompletionFlag()

        if cancelledBeforeParking {
            _ = parent.cancel()
        }
        let suspended = Int(bitPattern: kk_coroutine_suspended())
        #expect(kk_await_cancellation(continuation) == suspended)
        state.installResumeContinuation { resumed.set() }
        if !cancelledBeforeParking {
            _ = parent.cancel()
        }

        let didResume = loop.run(until: { resumed.isSet }, deadline: Date().addingTimeInterval(1))
        #expect(didResume)
        state.consumeCancellableDelivery()
        #expect(state.thrownException == scopeJob.cancellationCauseSnapshot())
        #expect(scopeJob.cancellationSnapshot())
        #expect(scope.isCancelled)
        _ = scopeJob.complete(with: 0)
        _ = parent.complete(with: 0)
    }

    @Test func cancellingJobWakesEveryParkedContinuation() {
        let job = RuntimeJobHandle()
        job.markStarted()
        let loop = RuntimeEventLoop()
        let continuations = (0..<2).map { offset in
            let continuation = kk_coroutine_continuation_new(9_581 + offset)
            let state = runtimeContinuationState(from: continuation)!
            state.jobHandle = job
            state.eventLoop = loop
            let resumed = RuntimeCompletionFlag()
            #expect(kk_await_cancellation(continuation) == Int(bitPattern: kk_coroutine_suspended()))
            state.installResumeContinuation { resumed.set() }
            return (state, resumed)
        }

        _ = job.cancel()
        for (state, resumed) in continuations {
            let didResume = loop.run(until: { resumed.isSet }, deadline: Date().addingTimeInterval(1))
            #expect(didResume)
            state.consumeCancellableDelivery()
            #expect(state.thrownException == job.cancellationCauseSnapshot())
        }
        _ = job.complete(with: 0)
    }

    @Test func normalJobCompletionDoesNotResumeAwaitCancellation() {
        let job = RuntimeJobHandle()
        job.markStarted()
        let continuation = kk_coroutine_continuation_new(9_583)
        let state = runtimeContinuationState(from: continuation)!
        state.jobHandle = job
        let loop = RuntimeEventLoop()
        state.eventLoop = loop
        let resumed = RuntimeCompletionFlag()
        #expect(kk_await_cancellation(continuation) == Int(bitPattern: kk_coroutine_suspended()))
        state.installResumeContinuation { resumed.set() }

        _ = job.complete(with: 0)
        let didResume = loop.run(until: { resumed.isSet }, deadline: Date().addingTimeInterval(0.02))
        #expect(!didResume)
        #expect(state.thrownException == 0)
    }
}
