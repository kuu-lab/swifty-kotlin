import Dispatch
import Foundation
@testable import Runtime
import Testing

private final class ScopeFailurePublicationGate: @unchecked Sendable {
    let entered = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)
}

private func scopeFailureCloseGate(_ closure: Int, _ cause: Int, _ thrown: UnsafeMutablePointer<Int>?) -> Int {
    let gate = Unmanaged<ScopeFailurePublicationGate>.fromOpaque(UnsafeRawPointer(bitPattern: closure)!).takeUnretainedValue()
    gate.entered.signal()
    _ = gate.release.wait(timeout: .now() + .seconds(5))
    thrown?.pointee = 0
    return 0
}

private func scopeContextWithContextReceiver(_ continuation: Int, _ thrown: UnsafeMutablePointer<Int>?) -> Int {
    thrown?.pointee = 0
    let scope = runtimeCoroutineScope(from: kk_coroutine_current_scope())!
    return kk_coroutine_state_exit(continuation, runtimeRegisterObject(scope))
}

private func scopeContextWithContextFailure(_ continuation: Int, _ thrown: UnsafeMutablePointer<Int>?) -> Int {
    let failure = Int(kk_coroutine_launcher_arg_get(continuation, 0))
    thrown?.pointee = failure
    return kk_coroutine_state_exit(continuation, 0)
}

@Suite(.serialized)
struct RuntimeCoroutineScopeContextTests {
    private func cancellationBox(_ raw: Int) -> RuntimeCancellationBox {
        Unmanaged<RuntimeCancellationBox>.fromOpaque(UnsafeRawPointer(bitPattern: raw)!).takeUnretainedValue()
    }

    @Test(arguments: [false, true])
    func withContextReceiverRetainsItsOwnContextAfterReturn(emptyOverride: Bool) throws {
        let savedState = RuntimeContinuationState.current
        let savedScope = RuntimeCoroutineScope.current
        let savedJob = RuntimeJobHandle.current
        RuntimeContinuationState.current = nil
        let parent = RuntimeCoroutineScope(context: RuntimeCoroutineContext(name: "parent"))
        let parentJob = parent.installJob()
        RuntimeCoroutineScope.current = parent
        RuntimeJobHandle.current = parentJob
        defer {
            RuntimeContinuationState.current = savedState
            RuntimeCoroutineScope.current = savedScope
            RuntimeJobHandle.current = savedJob
        }
        let override = emptyOverride ? 0 : runtimeRegisterObject(RuntimeCoroutineContext(name: "child"))
        let continuation = kk_coroutine_continuation_new(9_596)
        let state = try #require(runtimeContinuationState(from: continuation))
        let entry = unsafeBitCast(scopeContextWithContextReceiver as @convention(c)
            (Int, UnsafeMutablePointer<Int>?) -> Int, to: Int.self)
        var thrown = 0
        let raw = kk_with_context_full(override, entry, continuation, &thrown)
        #expect(thrown == 0)
        let receiver = try #require(runtimeCoroutineScope(from: raw))
        #expect(receiver !== parent)
        #expect(receiver.job !== parentJob)
        #expect(receiver.job?.completedSnapshot() == true)
        let context = __kk_coroutine_scope_context(raw)
        #expect(resolveToCoroutineContext(context).name == (emptyOverride ? "parent" : "child"))
        #expect(kk_context_get_job(context) == receiver.job?.identityHandle)
        #expect(receiver.context.jobHandleRaw == receiver.job?.identityHandle)
        #expect(parent.context.name == "parent")
        #expect(parentJob.isActiveSnapshot())
        #expect(state.scope == nil)
    }

    @Test
    func withContextSynchronousFailureUsesItsThrowingABI() {
        let saved = RuntimeContinuationState.current
        RuntimeContinuationState.current = nil
        defer { RuntimeContinuationState.current = saved }
        let failure = runtimeAllocateThrowable(message: "withContext body")
        let continuation = kk_coroutine_continuation_new(9_597)
        kk_coroutine_launcher_arg_set(continuation, 0, Int64(failure))
        let entry = unsafeBitCast(scopeContextWithContextFailure as @convention(c)
            (Int, UnsafeMutablePointer<Int>?) -> Int, to: Int.self)
        var thrown = 0
        _ = kk_with_context_full(0, entry, continuation, &thrown)
        #expect(thrown == failure)
    }

    @Test(arguments: [false, true])
    func handledScopedFailureDetachesFromItsParent(supervisor: Bool) {
        let savedState = RuntimeContinuationState.current
        let savedScope = RuntimeCoroutineScope.current
        let savedJob = RuntimeJobHandle.current
        let parent = RuntimeCoroutineScope()
        let parentJob = parent.installJob()
        let state = RuntimeContinuationState(functionID: 9_598)
        state.scope = parent
        state.jobHandle = parentJob
        RuntimeContinuationState.current = state
        RuntimeCoroutineScope.current = parent
        RuntimeJobHandle.current = parentJob
        defer {
            RuntimeContinuationState.current = savedState
            RuntimeCoroutineScope.current = savedScope
            RuntimeJobHandle.current = savedJob
        }
        let raw = supervisor ? kk_supervisor_scope_new() : kk_coroutine_scope_new()
        #expect(parentJob.registeredChildrenSnapshot().count == 1)
        let failure = runtimeAllocateThrowable(message: "handled scoped failure")
        _ = kk_coroutine_scope_fail(raw, failure)
        #expect(kk_coroutine_scope_wait(raw) == failure)
        #expect(parentJob.registeredChildrenSnapshot().isEmpty)
        #expect(parentJob.isActiveSnapshot())
    }

    @Test(arguments: [false, true])
    func receiverContextUsesItsOwnJobInsteadOfAmbientJob(producerHandle: Bool) {
        let receiver = RuntimeCoroutineScope(context: RuntimeCoroutineContext(name: "receiver"))
        let job = receiver.installJob()
        let channel = RuntimeChannelHandle(capacity: 0)
        channel.bindProducerScope(receiver)
        let receiverRaw = runtimeRegisterObject(receiver)
        let channelRaw = runtimeRegisterObject(channel)
        let handle = producerHandle ? channelRaw : receiverRaw
        let saved = RuntimeContinuationState.current
        let ambient = RuntimeContinuationState(functionID: 9_591)
        ambient.scope = RuntimeCoroutineScope(context: RuntimeCoroutineContext(name: "ambient"))
        let ambientJob = RuntimeJobHandle()
        ambient.jobHandle = ambientJob
        RuntimeContinuationState.current = ambient
        defer { RuntimeContinuationState.current = saved }
        let contextRaw = __kk_coroutine_scope_context(handle)
        #expect(resolveToCoroutineContext(contextRaw).name == "receiver")
        #expect(kk_context_get_job(contextRaw) == job.identityHandle)
        #expect(__kk_coroutine_scope_context(handle) == contextRaw)
        #expect(receiver.context.jobHandleRaw == 0)
        #expect(ambient.jobHandle === ambientJob)
    }

    @Test(arguments: [false, true])
    func scopedBuilderInheritsContextAndRetainsItsOwnCancellation(supervisor: Bool) {
        let savedState = RuntimeContinuationState.current
        let savedScope = RuntimeCoroutineScope.current
        let savedJob = RuntimeJobHandle.current
        let parent = RuntimeCoroutineScope(context: RuntimeCoroutineContext(name: "parent"))
        let parentJob = parent.installJob()
        let state = RuntimeContinuationState(functionID: 9_592)
        state.scope = parent
        state.jobHandle = parentJob
        RuntimeContinuationState.current = state
        RuntimeCoroutineScope.current = parent
        RuntimeJobHandle.current = parentJob
        defer {
            RuntimeContinuationState.current = savedState
            RuntimeCoroutineScope.current = savedScope
            RuntimeJobHandle.current = savedJob
        }
        let raw = supervisor ? kk_supervisor_scope_new() : kk_coroutine_scope_new()
        let scope = runtimeCoroutineScope(from: raw)!
        #expect(scope.context.name == "parent")
        #expect(scope.job !== parentJob)
        let cause = runtimeAllocateCancellationException(message: "original scope reason")
        _ = scope.job!.cancel(cause: cause)
        #expect(kk_coroutine_scope_wait(raw) == cause)
        #expect(state.scope === parent)
        #expect(state.jobHandle === parentJob)
        #expect(parentJob.isActiveSnapshot())
    }

    @Test
    func contextScopeAdoptsTaskBackedJobIdentity() {
        let task = RuntimeAsyncTask()
        let taskRaw = runtimeRegisterObject(task)
        let contextRaw = runtimeRegisterObject(RuntimeCoroutineContext(name: "task", jobHandleRaw: taskRaw))
        let raw = kk_coroutine_scope_new_with_context(contextRaw)
        let scope = runtimeCoroutineScope(from: raw)!
        #expect(scope.job === task.completionJob)
        #expect(kk_context_get_job(__kk_coroutine_scope_context(raw)) == taskRaw)
        _ = kk_coroutine_scope_cancel(raw)
        #expect(task.completionJob.cancellationSnapshot())
    }

    @Test
    func escapedReceiverRetainsTaskIdentityAfterParentJoins() {
        let parent = RuntimeCoroutineScope()
        var escaped: RuntimeCoroutineScope?
        weak var observedTask: RuntimeAsyncTask?
        var taskRaw = 0
        do {
            let task = RuntimeAsyncTask()
            _ = task.markStarted()
            taskRaw = Int(bitPattern: Unmanaged.passRetained(task).toOpaque())
            parent.registerChild(taskRaw)
            escaped = RuntimeCoroutineScope()
            escaped!.adoptJob(task.completionJob)
            observedTask = task
            task.complete(with: 0)
        }
        #expect(parent.waitForChildren() == 0)
        #expect(observedTask != nil)
        #expect(runtimeAsyncTask(from: taskRaw) != nil)
        if runtimeAsyncTask(from: taskRaw) != nil {
            #expect(kk_job_is_completed(taskRaw) == 1)
        }
        escaped = nil
        #expect(observedTask == nil)
    }

    @Test(arguments: [false, true])
    func settlingUnstartedLazyTaskReleasesItsCapturedScope(cancel: Bool) {
        var scope: RuntimeCoroutineScope? = RuntimeCoroutineScope()
        weak var observedTask: RuntimeAsyncTask?
        do {
            let task = RuntimeAsyncTask()
            scope!.adoptJob(task.completionJob)
            task.installLazyStartBody { [task, capturedScope = scope!] in
                _ = capturedScope
                task.complete(with: 0)
            }
            observedTask = task
            if cancel { task.cancel() }
            else { task.complete(with: 0) }
        }
        #expect(observedTask != nil)
        scope = nil
        #expect(observedTask == nil)
    }

    @Test(arguments: [false, true])
    func cancellationCheckPreservesTheOriginalException(ambientCheck: Bool) {
        let saved = RuntimeJobHandle.current
        let job = RuntimeJobHandle()
        job.markStarted()
        let cause = runtimeAllocateCancellationException(message: "original")
        _ = job.cancel(cause: cause)
        RuntimeJobHandle.current = job
        defer { RuntimeJobHandle.current = saved }
        let continuation = kk_coroutine_continuation_new(9_593)
        runtimeContinuationState(from: continuation)!.jobHandle = job
        var thrown = 0
        if ambientCheck { _ = kk_ensure_active(&thrown) }
        else { #expect(kk_coroutine_check_cancellation(continuation, &thrown) == 1) }
        #expect(thrown == cause)
        #expect(kk_job_get_cancellation_exception(job.identityHandle) == cause)
        #expect(cancellationBox(cause).cancellationJob == nil)
    }

    @Test(arguments: [false, true], [false, true])
    func scopeFailureAndCapturedJobKeepTheSameRoot(cleanupAfterCancellation: Bool, supervisor: Bool) {
        let savedScope = RuntimeCoroutineScope.current
        let savedJob = RuntimeJobHandle.current
        let savedState = RuntimeContinuationState.current
        RuntimeCoroutineScope.current = nil
        RuntimeJobHandle.current = nil
        RuntimeContinuationState.current = nil
        defer {
            RuntimeCoroutineScope.current = savedScope
            RuntimeJobHandle.current = savedJob
            RuntimeContinuationState.current = savedState
        }
        let raw = supervisor ? kk_supervisor_scope_new() : kk_coroutine_scope_new()
        let job = runtimeCoroutineScope(from: raw)!.job!
        let first = runtimeAllocateThrowable(message: "first failure")
        let cleanup = runtimeAllocateThrowable(message: "cleanup failure")
        if cleanupAfterCancellation {
            _ = job.cancel(cause: runtimeAllocateCancellationException(message: "prior cancellation"))
        } else {
            _ = kk_coroutine_scope_fail(raw, first)
        }
        _ = kk_coroutine_scope_fail(raw, cleanup)
        let expected = cleanupAfterCancellation ? cleanup : first
        #expect(kk_coroutine_scope_wait(raw) == expected)
        let exception = kk_job_get_cancellation_exception(job.identityHandle)
        #expect(kk_is_cancellation_exception(exception) == 1)
        #expect(cancellationBox(exception).cause == expected)
        #expect(cancellationBox(exception).message == (supervisor
            ? "SupervisorCoroutine was cancelled" : "ScopeCoroutine was cancelled"))
        #expect(cancellationBox(exception).cancellationJob === job)
    }

    @Test
    func parentFailureCancelsContinuationWithACancellationException() {
        let parent = RuntimeJobHandle()
        parent.markStarted()
        let delegate = kk_coroutine_continuation_new(9_594)
        runtimeContinuationState(from: delegate)!.jobHandle = parent
        let continuation = __kk_cancellable_continuation_new(delegate)
        let failure = runtimeAllocateThrowable(message: "parent failure")
        _ = parent.completeExceptionally(with: failure)
        var thrown = 0
        _ = __kk_cancellable_continuation_get_result(continuation, &thrown)
        #expect(kk_is_cancellation_exception(thrown) == 1)
        #expect(cancellationBox(thrown).cause == failure)
    }

    @Test
    func undeliveredSuccessObservesFailureBeforeProducerCloseNotification() {
        let parent = RuntimeJobHandle()
        parent.markStarted()
        let channel = RuntimeChannelHandle(capacity: 0)
        parent.producerChannel = runtimeRegisterObject(channel)
        let gate = ScopeFailurePublicationGate()
        let callback = unsafeBitCast(scopeFailureCloseGate as @convention(c)
            (Int, Int, UnsafeMutablePointer<Int>?) -> Int, to: Int.self)
        channel.addCloseHandler(fnPtr: callback, closureRaw: runtimeRegisterObject(gate))
        let delegate = kk_coroutine_continuation_new(9_595)
        runtimeContinuationState(from: delegate)!.jobHandle = parent
        let continuation = __kk_cancellable_continuation_new(delegate)
        var thrown = 0
        __kk_cancellable_continuation_resume(continuation, runtimeResultSuccess(42), 0, &thrown)
        let failure = runtimeAllocateThrowable(message: "producer failure")
        let finished = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            _ = parent.completeExceptionally(with: failure)
            finished.signal()
        }
        defer {
            gate.release.signal()
            #expect(finished.wait(timeout: .now() + .seconds(2)) == .success)
        }
        let entered = gate.entered.wait(timeout: .now() + .seconds(2)) == .success
        #expect(entered)
        guard entered else { return }
        #expect(parent.isFailedSnapshot())
        #expect(!parent.completedSnapshot())
        _ = __kk_cancellable_continuation_get_result(continuation, &thrown)
        #expect(kk_is_cancellation_exception(thrown) == 1)
        if kk_is_cancellation_exception(thrown) != 0 {
            #expect(cancellationBox(thrown).cause == failure)
        }
    }
}
