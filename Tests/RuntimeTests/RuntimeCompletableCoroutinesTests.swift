import Foundation
@testable import Runtime
import Testing

@Suite(.serialized, .runtimeIsolation(.gcOnly))
struct RuntimeCompletableCoroutinesTests {
    private func makeWrapper(parent: Int = runtimeNullSentinelInt) -> Int {
        let wrapper = runtimeRegisterObject(RuntimeObjectBox(length: 0, classID: 1))
        _ = __kk_job_bind_wrapper(wrapper, kk_job_new(), parent)
        return wrapper
    }

    @Test
    func completionQueriesRejectIncompleteAndPreserveResults() {
        let wrapper = makeWrapper()
        var thrown = 0
        #expect(__kk_deferred_get_completed(wrapper, &thrown) == 0)
        #expect(thrown != 0)
        #expect(__kk_deferred_completion_exception(wrapper, &thrown) == runtimeNullSentinelInt)
        #expect(thrown != 0)
        #expect(kk_job_complete(wrapper, 42) == 1)
        #expect(kk_job_complete(wrapper, 99) == 0)
        #expect(__kk_deferred_get_completed(wrapper, &thrown) == 42)
        #expect(thrown == 0)
        #expect(kk_job_is_cancelled(wrapper) == 0)
        #expect(__kk_deferred_completion_exception(wrapper, &thrown) == runtimeNullSentinelInt)
        #expect(kk_job_is_completed(wrapper) == 1)
        #expect(kk_job_is_active(wrapper) == 0)
    }

    @Test
    func suspendedAwaitPropagatesExceptionalCompletion() throws {
        let wrapper = makeWrapper()
        let continuation = kk_coroutine_continuation_new(9310)
        defer { _ = kk_coroutine_state_exit(continuation, 0) }
        let state = try #require(runtimeContinuationState(from: continuation))
        #expect(kk_kxmini_async_await(wrapper, continuation) == Int(bitPattern: kk_coroutine_suspended()))
        let failure = runtimeAllocateIllegalStateException(message: "failed")
        #expect(kk_job_complete_exceptionally(wrapper, failure) == 1)
        #expect(state.thrownException == failure)
        #expect(kk_job_is_cancelled(wrapper) == 1)
        var thrown = 0
        #expect(__kk_deferred_get_completed(wrapper, &thrown) == 0)
        #expect(thrown == failure)
        #expect(__kk_deferred_completion_exception(wrapper, &thrown) == failure)
        #expect(thrown == 0)
        let completedContinuation = kk_coroutine_continuation_new(9311)
        defer { _ = kk_coroutine_state_exit(completedContinuation, 0) }
        let completedState = try #require(runtimeContinuationState(from: completedContinuation))
        #expect(kk_kxmini_async_await(wrapper, completedContinuation) == Int(bitPattern: kk_coroutine_suspended()))
        #expect(completedState.thrownException == failure)
    }

    @Test
    func parentCancellationCompletesBodylessChildrenImmediately() {
        let parent = makeWrapper()
        let child = makeWrapper(parent: parent)
        _ = kk_job_cancel(parent)
        #expect(kk_job_is_cancelled(child) == 1)
        #expect(kk_job_is_completed(child) == 1)
        #expect(kk_job_complete(child, 42) == 0)
        let lateChild = makeWrapper(parent: parent)
        #expect(kk_job_is_cancelled(lateChild) == 1)
        #expect(kk_job_is_completed(lateChild) == 1)
    }

    @Test
    func childFailuresCancelOrdinaryButNotSupervisorParents() {
        let failure = runtimeAllocateIllegalStateException(message: "failure")
        let parent = makeWrapper()
        let child = makeWrapper(parent: parent)
        _ = kk_job_complete_exceptionally(child, failure)
        #expect(kk_job_is_cancelled(parent) == 1)
        let supervisor = kk_supervisor_job_new()
        let supervisedChild = makeWrapper(parent: supervisor)
        _ = kk_job_complete_exceptionally(supervisedChild, failure)
        #expect(kk_job_is_active(supervisor) == 1)
        let cancellationParent = makeWrapper()
        let cancellationChild = makeWrapper(parent: cancellationParent)
        _ = kk_job_complete_exceptionally(cancellationChild, runtimeAllocateCancellationException())
        #expect(kk_job_is_active(cancellationParent) == 1)
    }

    @Test
    func completionQueriesAlsoSupportLegacyAsyncHandles() {
        let task = RuntimeAsyncTask()
        let handle = runtimeRegisterObject(task)
        task.complete(with: 17)
        var thrown = 0
        #expect(__kk_deferred_get_completed(handle, &thrown) == 17)
        #expect(thrown == 0)
        task.cancel()
        #expect(__kk_deferred_get_completed(handle, &thrown) == 17)
        #expect(thrown == 0)
        #expect(__kk_deferred_completion_exception(handle, &thrown) == runtimeNullSentinelInt)
        let failedTask = RuntimeAsyncTask()
        let failedHandle = runtimeRegisterObject(failedTask)
        let failure = runtimeAllocateIllegalStateException(message: "async failed")
        failedTask.completeExceptionally(with: failure)
        #expect(__kk_deferred_get_completed(failedHandle, &thrown) == 0)
        #expect(thrown == failure)
        #expect(__kk_deferred_completion_exception(failedHandle, &thrown) == failure)
        #expect(thrown == 0)
        let cancelledTask = RuntimeAsyncTask()
        let cancelledHandle = runtimeRegisterObject(cancelledTask)
        cancelledTask.cancel()
        #expect(__kk_deferred_get_completed(cancelledHandle, &thrown) == 0)
        #expect(thrown != 0)
        let cancellation = thrown
        #expect(__kk_deferred_completion_exception(cancelledHandle, &thrown) == cancellation)
        #expect(thrown == 0)
    }
}
