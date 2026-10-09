import Foundation
@testable import Runtime
import Testing

private func failLaunchDescendant(
    _ failure: Int, _ scopeHandle: Int, _ thrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let scope = runtimeCoroutineScope(from: scopeHandle) else { return 0 }
    let child = RuntimeJobHandle()
    child.markStarted()
    scope.registerChild(Int(bitPattern: Unmanaged.passRetained(child).toOpaque()))
    _ = child.completeExceptionally(with: failure)
    thrown?.pointee = runtimeAllocateCancellationException()
    return 0
}

@Suite
struct RuntimeStructuredConcurrencyFailureTests {
    @Test
    func supervisorLaunchReportsDescendantFailureInsteadOfBodyCancellation() {
        let failure = runtimeAllocateIllegalStateException(message: "child")
        let notified = DispatchSemaphore(value: 0)
        let handler = RuntimeExceptionHandlerBox { _, exception in
            #expect(exception == failure)
            notified.signal()
        }
        let parent = kk_supervisor_job_new()
        let context = runtimeRegisterObject(RuntimeCoroutineContext(
            exceptionHandler: handler, jobHandleRaw: parent
        ))
        let scope = kk_coroutine_scope_new_with_context(context)
        typealias Entry = @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int
        let entry = unsafeBitCast(failLaunchDescendant as Entry, to: Int.self)
        let job = __kk_coroutine_scope_launch_context(scope, 0, 3, entry, failure)
        _ = kk_job_join(job, 0)
        #expect(notified.wait(timeout: .now() + 2) == .success)
        #expect(notified.wait(timeout: .now()) == .timedOut)
        #expect(runtimeAsyncTask(from: job)?.completionSnapshot().exception == failure)
        #expect(kk_job_is_active(parent) == 1)
        _ = kk_coroutine_scope_wait(scope)
    }

    @Test(arguments: [false, true])
    func childFailureCancelsAncestorsBeforeCompletionObservers(async: Bool) {
        let root = RuntimeJobHandle()
        root.markStarted()
        let parent = RuntimeJobHandle()
        parent.markStarted()
        let sibling = RuntimeJobHandle()
        sibling.markScheduled()
        let failed = RuntimeAsyncTask()
        let failedJob = async ? failed.completionJob : RuntimeJobHandle()
        failedJob.markStarted()
        let parentHandle = runtimeRegisterObject(parent)
        let siblingHandle = runtimeRegisterObject(sibling)
        let failedHandle = runtimeRegisterObject(async ? failed as AnyObject : failedJob as AnyObject)
        root.registerChild(parentHandle)
        root.registerChild(siblingHandle)
        parent.registerChild(failedHandle)
        let exception = runtimeAllocateIllegalStateException(message: "kill")
        _ = failedJob.addCompletionHandler(onCancelling: false) { cause in
            #expect(cause == exception)
            #expect(root.cancellationSnapshot())
            #expect(parent.cancellationSnapshot())
            #expect(sibling.cancellationSnapshot())
        }
        if async {
            failed.completeExceptionally(with: exception)
        } else {
            _ = failedJob.completeExceptionally(with: exception)
        }
        #expect(root.cancellationCauseSnapshot() == exception)
    }

    @Test(arguments: [false, true])
    func scopeFailureIsImmediateAndSupervisorsIsolateIt(supervisor: Bool) {
        let scope = RuntimeCoroutineScope(isSupervisor: supervisor)
        let job = scope.installJob()
        let sibling = RuntimeJobHandle()
        sibling.markScheduled()
        let failed = RuntimeAsyncTask()
        let siblingHandle = Int(bitPattern: Unmanaged.passRetained(sibling).toOpaque())
        let failedHandle = Int(bitPattern: Unmanaged.passRetained(failed).toOpaque())
        scope.registerChild(siblingHandle)
        scope.registerChild(failedHandle)
        let exception = runtimeAllocateIllegalStateException(message: "kill")
        failed.completeExceptionally(with: exception)
        #expect(job.isActiveSnapshot() == supervisor)
        #expect(sibling.cancellationSnapshot() == !supervisor)
        _ = sibling.complete(with: 0)
        #expect(scope.waitForChildren() == (supervisor ? 0 : exception))
    }

    @Test(arguments: [false, true])
    func cleanupFailureAfterCancellationIsNotLost(nullableCause: Bool) {
        let scope = RuntimeCoroutineScope()
        scope.installJob()
        let child = RuntimeJobHandle()
        child.markStarted()
        let handle = Int(bitPattern: Unmanaged.passRetained(child).toOpaque())
        scope.registerChild(handle)
        if nullableCause {
            _ = scope.job?.cancel(cause: runtimeNullSentinelInt)
        } else {
            scope.cancel()
        }
        #expect(kk_is_cancellation_exception(scope.job?.cancellationCauseSnapshot() ?? 0) == 1)
        let failure = runtimeAllocateIllegalStateException(message: "cleanup")
        _ = child.completeExceptionally(with: failure)
        #expect(child.join() == failure)
        #expect(scope.waitForChildren() == failure)
    }

    @Test(arguments: [false, true])
    func firstFailureSurvivesFinallyFailure(async: Bool) {
        let task = RuntimeAsyncTask()
        let job = async ? task.completionJob : RuntimeJobHandle()
        job.markStarted()
        let first = runtimeAllocateIllegalStateException(message: "first")
        let cleanup = runtimeAllocateIllegalStateException(message: "cleanup")
        _ = job.cancel(cause: first)
        if async {
            task.completeExceptionally(with: cleanup)
            #expect(task.completionSnapshot().exception == first)
        } else {
            _ = job.completeExceptionally(with: cleanup)
        }
        #expect(job.join() == first)
    }

    @Test(arguments: [false, true])
    func successfulChildDoesNotCancelScopeWithoutJob(async: Bool) {
        let scope = RuntimeCoroutineScope()
        let task = RuntimeAsyncTask()
        let completed = async ? task.completionJob : RuntimeJobHandle()
        let sibling = RuntimeJobHandle()
        sibling.markScheduled()
        let childObject: AnyObject = async ? task : completed
        let childHandle = Int(bitPattern: Unmanaged.passRetained(childObject).toOpaque())
        let siblingHandle = Int(bitPattern: Unmanaged.passRetained(sibling).toOpaque())
        scope.registerChild(childHandle)
        scope.registerChild(siblingHandle)
        if async { task.complete(with: 42) } else { _ = completed.complete(with: 42) }
        #expect(!scope.isCancelled)
        #expect(sibling.isActiveSnapshot())
        _ = sibling.complete(with: 0)
        #expect(scope.waitForChildren() == 0)
    }

    @Test
    func childCancellationDoesNotFailParent() {
        let parent = RuntimeJobHandle()
        parent.markStarted()
        let child = RuntimeJobHandle()
        parent.registerChild(runtimeRegisterObject(child))
        _ = child.completeExceptionally(with: runtimeAllocateCancellationException())
        #expect(parent.isActiveSnapshot())
    }

    @Test(arguments: [false, true])
    func childCancelledNonCancellationFailureCancelsParentSynchronously(async: Bool) {
        let parent = RuntimeJobHandle()
        parent.markStarted()
        let task = RuntimeAsyncTask()
        let childJob = async ? task.completionJob : RuntimeJobHandle()
        childJob.markStarted()
        let childObject: AnyObject = async ? (task as AnyObject) : childJob
        let childHandle = runtimeRegisterObject(childObject)
        parent.registerChild(childHandle)

        let failure = runtimeAllocateIllegalStateException(message: "child failure")
        #expect(kk_job_child_cancelled(childHandle, failure) == 1)
        #expect(childJob.cancellationSnapshot())
        #expect(!parent.isActiveSnapshot())
        #expect(parent.cancellationCauseSnapshot() == failure)
    }

    @Test
    func childCancelledCancellationExceptionLeavesJobAndParentActive() {
        let parent = RuntimeJobHandle()
        parent.markStarted()
        let child = RuntimeJobHandle()
        child.markStarted()
        let childHandle = runtimeRegisterObject(child)
        parent.registerChild(childHandle)

        let cancellation = runtimeAllocateCancellationException(message: "normal cancellation")
        #expect(kk_job_child_cancelled(childHandle, cancellation) == 1)
        #expect(child.isActiveSnapshot())
        #expect(parent.isActiveSnapshot())
    }

    @Test
    func coroutineScopeJobCancellationWakesItsBlockContinuation() throws {
        let outerTaskKey = RuntimeCoroutineScopeTaskKey.installedKey
        let outerJob = RuntimeJobHandle.current
        let continuation = kk_coroutine_continuation_new(1410)
        let state = try #require(runtimeContinuationState(from: continuation))
        let previousStateJob = state.jobHandle
        let taskKey = RuntimeCoroutineScopeTaskKey.installFreshKey()
        RuntimeContinuationState.installState(state, forTask: taskKey)
        RuntimeCoroutineScope.installScope(nil, forTask: taskKey)
        RuntimeJobHandle.current = nil

        let scopeHandle = kk_coroutine_scope_new()
        defer {
            _ = kk_coroutine_scope_wait(scopeHandle)
            state.jobHandle = previousStateJob
            RuntimeContinuationState.removeCurrent(forTask: taskKey)
            RuntimeCoroutineScope.removeScope(forTask: taskKey)
            RuntimeCoroutineScopeTaskKey.restoreKey(outerTaskKey)
            RuntimeJobHandle.current = outerJob
            _ = kk_coroutine_state_exit(continuation, 0)
        }

        let scope = try #require(runtimeCoroutineScope(from: scopeHandle))
        let scopeJob = try #require(scope.job)
        let resumed = RuntimeCompletionFlag()
        state.resumesInline = true
        state.installResumeContinuation { resumed.set() }

        _ = scopeJob.cancel(cause: runtimeAllocateIllegalStateException(message: "child failure"))

        #expect(scopeJob.continuationState === state)
        #expect(resumed.isSet)
    }
}
