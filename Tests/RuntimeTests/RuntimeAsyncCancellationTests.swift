import Foundation
@testable import Runtime
import Testing

private final class AsyncCancellationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func record() {
        lock.lock()
        count += 1
        lock.unlock()
    }

    func snapshot() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func reset() {
        lock.lock()
        count = 0
        lock.unlock()
    }
}

private let asyncCancellationCounter = AsyncCancellationCounter()

private func asyncCancellationBody(_ continuation: Int, _ thrown: UnsafeMutablePointer<Int>?) -> Int {
    asyncCancellationCounter.record()
    thrown?.pointee = 0
    return kk_coroutine_state_exit(continuation, 42)
}

@Suite(.runtimeIsolation(.gcOnly, resetAdditionalState: { asyncCancellationCounter.reset() }))
struct RuntimeAsyncCancellationTests {
    private typealias Entry = @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int

    @Test(arguments: ["default", "lazy", "atomic", "scopeDefault", "scopeLazy", "scopeAtomic"], [false, true])
    func cancelBeforeDispatch(mode: String, withContinuation: Bool) throws {
        let savedLoop = RuntimeEventLoop.current
        let loop = RuntimeEventLoop()
        RuntimeEventLoop.current = loop
        defer { RuntimeEventLoop.current = savedLoop }
        let entry = unsafeBitCast(asyncCancellationBody as Entry, to: Int.self)
        let continuation = kk_coroutine_continuation_new(9700)
        let scope = kk_coroutine_scope_new_with_context(0)
        let handle: Int
        switch mode {
        case "default":
            handle = withContinuation ? kk_kxmini_async_with_cont(entry, continuation) : kk_kxmini_async(entry, 9700)
        case "lazy":
            handle = withContinuation ? kk_kxmini_async_lazy_with_cont(entry, continuation) : kk_kxmini_async_lazy(entry, 9700)
        case "atomic":
            handle = withContinuation ? kk_kxmini_async_atomic_with_cont(entry, continuation) : kk_kxmini_async_atomic(entry, 9700)
        default:
            let start = mode == "scopeLazy" ? 1 : (mode == "scopeAtomic" ? 2 : 0)
            handle = kk_coroutine_scope_async_with_cont(scope, 0, start, entry, continuation)
        }
        let task = try #require(runtimeAsyncTask(from: handle))
        // Exercise cancellation after a LAZY start has enqueued work, too.
        if withContinuation { task.startIfNeeded() }
        _ = kk_job_cancel(handle)
        let atomic = mode == "atomic" || mode == "scopeAtomic"
        #expect(task.isCompletedSnapshot() == !atomic)
        #expect(kk_job_join(handle, 0) == 0)
        let drained = RuntimeCompletionFlag()
        loop.enqueue { drained.set() }
        let didDrain = loop.run(until: { drained.isSet }, deadline: Date().addingTimeInterval(2))
        #expect(didDrain)
        #expect(asyncCancellationCounter.snapshot() == (atomic ? 1 : 0))
        #expect(kk_job_is_completed(handle) == 1)
        #expect(kk_job_is_cancelled(handle) == 1)
        let caller = kk_coroutine_continuation_new(9701)
        #expect(kk_kxmini_async_await(handle, caller) == Int(bitPattern: kk_coroutine_suspended()))
        #expect(kk_is_cancellation_exception(Int(kk_coroutine_state_get_thrown_exception(caller))) == 1)
        _ = kk_coroutine_state_exit(caller, 0)
        _ = kk_coroutine_scope_wait(scope)
    }

    @Test(arguments: [false, true])
    func completedJoinIgnoresFailureButAwaitPropagates(cancelled: Bool) throws {
        let task = RuntimeAsyncTask()
        let handle = Int(bitPattern: Unmanaged.passRetained(task).toOpaque())
        defer { Unmanaged<RuntimeAsyncTask>.fromOpaque(UnsafeRawPointer(bitPattern: handle)!).release() }
        if cancelled {
            task.cancel()
        } else {
            task.completeExceptionally(with: runtimeAllocateThrowable(message: "failed"))
        }
        let exception = task.completionSnapshot().exception
        let joiner = kk_coroutine_continuation_new(9702)
        #expect(kk_job_join(handle, joiner) == 0)
        #expect(kk_job_join(handle, 0) == 0)
        #expect(kk_coroutine_state_get_thrown_exception(joiner) == 0)
        #expect(kk_kxmini_async_await(handle, joiner) == Int(bitPattern: kk_coroutine_suspended()))
        #expect(kk_coroutine_state_get_thrown_exception(joiner) == exception)
        _ = kk_coroutine_state_exit(joiner, 0)
    }

    @Test(arguments: [false, true])
    func pendingJoinAndAwaitHaveDistinctResumers(cancelled: Bool) throws {
        let task = RuntimeAsyncTask()
        let handle = Int(bitPattern: Unmanaged.passRetained(task).toOpaque())
        defer { Unmanaged<RuntimeAsyncTask>.fromOpaque(UnsafeRawPointer(bitPattern: handle)!).release() }
        #expect(task.markStarted())
        let joiner = kk_coroutine_continuation_new(9703)
        let awaiter = kk_coroutine_continuation_new(9704)
        #expect(kk_job_join(handle, joiner) == Int(bitPattern: kk_coroutine_suspended()))
        #expect(kk_kxmini_async_await(handle, awaiter) == Int(bitPattern: kk_coroutine_suspended()))
        let completion = AsyncCancellationCounter()
        task.addCompletionResumer { _, _ in completion.record() }
        let failure = runtimeAllocateThrowable(message: "failed")
        if cancelled {
            task.cancel()
            task.cancel()
            #expect(!task.isCompletedSnapshot())
            #expect(!task.completionJob.completedSnapshot())
            #expect(completion.snapshot() == 0)
            task.complete(with: 42)
        } else {
            task.completeExceptionally(with: failure)
        }
        #expect(task.isCompletedSnapshot())
        #expect(task.completionJob.completedSnapshot())
        #expect(kk_coroutine_state_get_thrown_exception(joiner) == 0)
        #expect(kk_coroutine_state_get_thrown_exception(awaiter) == task.completionSnapshot().exception)
        task.complete(with: 99)
        task.cancel()
        #expect(completion.snapshot() == 1)
        _ = kk_coroutine_state_exit(joiner, 0)
        _ = kk_coroutine_state_exit(awaiter, 0)
    }

    @Test
    func cancellationPreservesExplicitCauseAndNormalizesNull() {
        let cause = runtimeAllocateCancellationException(message: "explicit cause")
        let task = RuntimeAsyncTask()
        task.cancel(cause: cause)
        #expect(task.completionSnapshot().exception == cause)
        let nullCauseTask = RuntimeAsyncTask()
        nullCauseTask.cancel(cause: runtimeNullSentinelInt)
        #expect(kk_is_cancellation_exception(nullCauseTask.completionSnapshot().exception) == 1)
    }

    @Test
    func cancelledBodyFailureStillPropagatesThroughAwait() throws {
        let task = RuntimeAsyncTask()
        #expect(task.markStarted())
        task.cancel()
        let failure = runtimeAllocateThrowable(message: "finally failed")
        task.completeExceptionally(with: failure)
        let outcome = task.awaitResult(callerState: nil)
        guard case .completed(let result, let exception) = outcome else {
            Issue.record("completed task suspended")
            return
        }
        #expect(result == 0)
        #expect(exception == failure)
        #expect(task.isCancelledSnapshot())
        #expect(task.completionJob.completedSnapshot())
    }

    @Test
    func cancellationRacingCompletionKeepsJobStateConsistent() {
        for _ in 0..<100 {
            let task = RuntimeAsyncTask()
            #expect(task.markStarted())
            let group = DispatchGroup()
            DispatchQueue.global().async(group: group) { task.cancel() }
            DispatchQueue.global().async(group: group) { task.complete(with: 42) }
            group.wait()
            #expect(task.isCompletedSnapshot())
            #expect(task.completionJob.completedSnapshot())
            #expect(task.isCancelledSnapshot() == task.completionJob.cancellationSnapshot())
        }
    }

    @Test
    func joinStillChecksCallingCoroutineCancellation() throws {
        let task = RuntimeAsyncTask()
        let handle = Int(bitPattern: Unmanaged.passRetained(task).toOpaque())
        defer { Unmanaged<RuntimeAsyncTask>.fromOpaque(UnsafeRawPointer(bitPattern: handle)!).release() }
        task.complete(with: 42)
        let caller = kk_coroutine_continuation_new(9705)
        let state = try #require(runtimeContinuationState(from: caller))
        let callerJob = RuntimeJobHandle()
        state.jobHandle = callerJob
        _ = callerJob.cancel()
        #expect(kk_job_join(handle, caller) == Int(bitPattern: kk_coroutine_suspended()))
        #expect(kk_is_cancellation_exception(state.thrownException) == 1)
        _ = kk_coroutine_state_exit(caller, 0)
    }
}
