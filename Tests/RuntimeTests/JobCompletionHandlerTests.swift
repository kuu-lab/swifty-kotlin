import Foundation
@testable import Runtime
import Testing

private final class JobHandlerEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Int] = []

    func append(_ value: Int) {
        lock.lock()
        values.append(value)
        lock.unlock()
    }

    func snapshot() -> [Int] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}

@Suite(.runtimeIsolation(.gcOnly))
struct JobCompletionHandlerTests {
    @Test func normalCompletionPreservesOrderAndDisposal() {
        let job = RuntimeJobHandle()
        let events = JobHandlerEvents()
        job.markStarted()
        _ = job.addCompletionHandler(onCancelling: false) { cause in
            #expect(cause == runtimeNullSentinelInt)
            #expect(job.completedSnapshot())
            events.append(1)
        }
        let disposed = job.addCompletionHandler(onCancelling: false) { _ in events.append(2) }
        _ = job.addCompletionHandler(onCancelling: true) { _ in events.append(3) }
        job.removeCompletionHandler(id: disposed)
        job.removeCompletionHandler(id: disposed)
        #expect(job.complete(with: 42))
        #expect(!job.complete(with: 43))
        #expect(events.snapshot() == [1, 3])
    }

    @Test func cancellationHandlersRunBeforeTerminalHandlersAndLateRegistrationHonorsFlags() {
        let job = RuntimeJobHandle()
        let events = JobHandlerEvents()
        let cause = runtimeAllocateCancellationException(message: "cancelled")
        job.markStarted()
        _ = job.addCompletionHandler(onCancelling: false) { value in
            #expect(value == cause)
            events.append(4)
        }
        _ = job.addCompletionHandler(onCancelling: true) { value in
            #expect(value == cause)
            events.append(1)
        }
        #expect(job.cancel(cause: cause))
        #expect(events.snapshot() == [1])
        #expect(job.addCompletionHandler(onCancelling: true) { _ in events.append(2) } == 0)
        #expect(job.addCompletionHandler(onCancelling: true, invokeImmediately: false) { _ in
            events.append(99)
        } == 0)
        let terminal = job.addCompletionHandler(onCancelling: false, invokeImmediately: false) { _ in
            events.append(5)
        }
        #expect(terminal != 0)
        #expect(events.snapshot() == [1, 2])
        #expect(job.complete(with: 0))
        #expect(events.snapshot() == [1, 2, 4, 5])
    }

    @Test func exceptionalCompletionAndTerminalRegistrationDeliverTheFailureOnce() {
        let job = RuntimeJobHandle()
        let events = JobHandlerEvents()
        let failure = runtimeAllocateThrowable(message: "failed")
        job.markStarted()
        _ = job.addCompletionHandler(onCancelling: true) { events.append($0) }
        #expect(job.completeExceptionally(with: failure))
        #expect(job.addCompletionHandler(onCancelling: false) { events.append($0) } == 0)
        #expect(job.addCompletionHandler(onCancelling: false, invokeImmediately: false) {
            events.append($0)
        } == 0)
        #expect(events.snapshot() == [failure, failure])
    }

    @Test func hierarchyBridgesExcludeCompletedChildrenAndDetachTheirParent() throws {
        let parent = RuntimeJobHandle()
        let first = RuntimeJobHandle()
        let second = RuntimeJobHandle()
        let parentRaw = runtimeRegisterObject(parent)
        let firstRaw = runtimeRegisterObject(first)
        let secondRaw = runtimeRegisterObject(second)
        parent.markStarted()
        first.markStarted()
        second.markStarted()
        parent.registerChild(firstRaw)
        parent.registerChild(secondRaw)
        #expect(__kk_job_parent(firstRaw) == parentRaw)
        #expect(__kk_job_parent(secondRaw) == parentRaw)
        #expect(__kk_job_parent(parentRaw) == runtimeNullSentinelInt)
        let listRaw = __kk_job_children(parentRaw)
        let list = try #require(runtimeListBox(from: listRaw))
        #expect(list.elements == [firstRaw, secondRaw])
        #expect(first.complete(with: 0))
        #expect(parent.childrenSnapshot() == [secondRaw])
        #expect(__kk_job_parent(firstRaw) == runtimeNullSentinelInt)
        #expect(parent.isActiveSnapshot())
        #expect(__kk_job_parent(0) == runtimeNullSentinelInt)
        #expect(try #require(runtimeListBox(from: __kk_job_children(0))).elements.isEmpty)
    }

    @Test func contextScopeLaunchAttachesToItsContextJob() {
        let parentRaw = kk_job_new()
        let scopeRaw = kk_coroutine_scope_new_with_context(parentRaw)
        let scope = runtimeCoroutineScope(from: scopeRaw)
        #expect(scope?.contextJob === runtimeJobHandle(from: parentRaw))
    }

    @Test func deferredCompletionAndCancellationParticipateInJobCallbacksAndHierarchy() {
        let parent = RuntimeJobHandle()
        let task = RuntimeAsyncTask()
        let taskRaw = runtimeRegisterObject(task)
        let parentRaw = runtimeRegisterObject(parent)
        let events = JobHandlerEvents()
        parent.registerChild(taskRaw)
        _ = task.completionJob.addCompletionHandler(onCancelling: false) { events.append($0) }
        #expect(__kk_job_parent(taskRaw) == parentRaw)
        #expect(parent.childrenSnapshot() == [taskRaw])
        task.complete(with: 42)
        #expect(events.snapshot() == [runtimeNullSentinelInt])
        #expect(__kk_job_parent(taskRaw) == runtimeNullSentinelInt)
        #expect(parent.childrenSnapshot().isEmpty)

        let cancelled = RuntimeAsyncTask()
        let cause = runtimeAllocateCancellationException(message: "cancelled")
        _ = cancelled.completionJob.addCompletionHandler(onCancelling: true) { events.append($0) }
        cancelled.cancel(cause: cause)
        cancelled.cancel()
        #expect(events.snapshot() == [runtimeNullSentinelInt, cause])
    }
}
