// Scratch implementation proposal: not Swift type-checked or executed.
import Dispatch
import Foundation
@testable import Runtime
import Testing

private final class BlockingContextProbe: @unchecked Sendable {
    private let lock = NSLock()
    var parent = 0
    var failure = 0
    var mode = "observe"
    private var entries: [(thread: pthread_t, job: Int, name: String?, dispatcher: RuntimeDispatcher?)] = []
    private var finallySeen = false
    func reset(parent: Int = 0, failure: Int = 0, mode: String = "observe") {
        lock.lock()
        defer { lock.unlock() }
        self.parent = parent
        self.failure = failure
        self.mode = mode
        entries = []
        finallySeen = false
    }
    func record() {
        lock.lock()
        defer { lock.unlock() }
        entries.append((pthread_self(), RuntimeJobHandle.current?.identityHandle ?? 0,
                        RuntimeContinuationState.current?.makeContinuationContext().name,
                        RuntimeDispatcher.current))
    }
    func markFinally() { lock.lock(); finallySeen = true; lock.unlock() }
    func snapshot() -> (entries: [(pthread_t, Int, String?, RuntimeDispatcher?)], finallySeen: Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (entries, finallySeen)
    }
}
private let blockingContextProbe = BlockingContextProbe()
private typealias BlockingValueEntry = @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int
private typealias BlockingSuspendEntry = @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int

private let blockingContextValue: BlockingValueEntry = { _, _, thrown in
    blockingContextProbe.record()
    if blockingContextProbe.mode == "finalCancel" {
        _ = RuntimeJobHandle.current?.cancel()
    } else if blockingContextProbe.mode == "bodyFailure" {
        thrown?.pointee = blockingContextProbe.failure
        return 0
    } else if blockingContextProbe.mode == "childFailure" || blockingContextProbe.mode == "childObserve" {
        let scope = RuntimeCoroutineScope.current!
        let scopeRaw = Int(bitPattern: Unmanaged.passUnretained(scope).toOpaque())
        let child = unsafeBitCast(blockingContextProbe.mode == "childFailure"
            ? blockingContextFailedChild : blockingContextObservedChild, to: Int.self)
        _ = __kk_coroutine_scope_launch_context(scopeRaw, 0, 0, child, 0)
    }
    thrown?.pointee = 0
    return 17
}
private let blockingContextFailedChild: BlockingSuspendEntry = { _, thrown in
    thrown?.pointee = blockingContextProbe.failure
    return 0
}
private let blockingContextObservedChild: BlockingSuspendEntry = { _, thrown in
    blockingContextProbe.record()
    thrown?.pointee = 0
    return 0
}
private let blockingContextSuspending: BlockingSuspendEntry = { continuation, thrown in
    let state = runtimeContinuationState(from: continuation)!
    blockingContextProbe.record()
    switch state.label {
    case 0:
        state.label = 1
        if blockingContextProbe.mode == "midCancel" { _ = kk_job_cancel(blockingContextProbe.parent) }
        return kk_coroutine_yield(continuation)
    case 1:
        if blockingContextProbe.mode == "midCancel" {
            blockingContextProbe.markFinally()
            _ = kk_coroutine_check_cancellation(continuation, thrown)
            return 0
        }
        state.label = 2
        state.scheduleDelay(milliseconds: 1)
        return Int(bitPattern: kk_coroutine_suspended())
    default:
        thrown?.pointee = 0
        return kk_coroutine_state_exit(continuation, 17)
    }
}

@Suite(.serialized)
struct RuntimeRunBlockingContextTests {
    private func valueBox() -> Int {
        kk_function_create_1(unsafeBitCast(blockingContextValue, to: Int.self), 0, nil)
    }
    private func suspendBox() -> Int {
        kk_suspend_function_create(
            unsafeBitCast(blockingContextValue, to: Int.self), 0, 1,
            unsafeBitCast(blockingContextSuspending, to: Int.self)
        )
    }

    @Test func ownsFreshJobPreservesInputAndDetachesWithoutCompletingParent() throws {
        let parent = kk_job_new()
        let input = RuntimeCoroutineContext(name: "parent", jobHandleRaw: parent)
        let context = runtimeRegisterObject(input)
        blockingContextProbe.reset(parent: parent)
        let oldKey = RuntimeCoroutineScopeTaskKey.installedKey
        let oldJob = RuntimeJobHandle.current
        let oldLoop = RuntimeEventLoop.current
        let oldDispatcher = RuntimeDispatcher.current
        var thrown = 0
        #expect(__kk_run_blocking_context(context, valueBox(), 0, &thrown) == 17)
        #expect(thrown == 0)
        let row = try #require(blockingContextProbe.snapshot().entries.first)
        #expect(row.1 != 0 && row.1 != parent && row.2 == "parent")
        #expect(runtimeJobHandle(from: row.1)?.completedSnapshot() == true)
        #expect(runtimeJobHandle(from: parent)?.isActiveSnapshot() == true)
        #expect(runtimeJobHandle(from: parent)?.childrenSnapshot().isEmpty == true)
        #expect(input.jobHandleRaw == parent && input.dispatcherElementHandle == 0 && input.name == "parent")
        #expect(RuntimeCoroutineScopeTaskKey.installedKey == oldKey)
        #expect(RuntimeJobHandle.current === oldJob)
        #expect(RuntimeEventLoop.current === oldLoop)
        #expect(RuntimeDispatcher.current === oldDispatcher)
    }

    @Test(arguments: [0, 1, 2])
    func initialPendingYieldAndInstalledDelayFollowSpecifiedScheduler(kind: Int) throws {
        let caller = pthread_self()
        let dispatcherRaw = kk_dispatcher_named(kind)
        let dispatcher = runtimeResolveDispatcher(from: dispatcherRaw)
        blockingContextProbe.reset()
        var thrown = 0
        #expect(__kk_run_blocking_context(dispatcherRaw, suspendBox(), 0, &thrown) == 17)
        #expect(thrown == 0)
        let rows = blockingContextProbe.snapshot().entries
        #expect(rows.count == 3, "initial + pending yield + installed delay must all execute")
        for row in rows { #expect(row.3 === dispatcher) }
        if kind == 2 { #expect(pthread_equal(try #require(rows.first).0, caller) != 0) }
        else {
            for row in rows { #expect(pthread_equal(row.0, caller) == 0) }
        }
    }

    @Test func preMidAndFinalCancellationRetainFailureAndFinallyPath() {
        let parent = kk_job_new()
        _ = kk_job_cancel(parent)
        blockingContextProbe.reset(parent: parent)
        var thrown = 0
        #expect(__kk_run_blocking_context(parent, valueBox(), 0, &thrown) == 0)
        #expect(kk_is_cancellation_exception(thrown) != 0)
        #expect(blockingContextProbe.snapshot().entries.isEmpty)
        let active = kk_job_new()
        blockingContextProbe.reset(parent: active, mode: "midCancel")
        thrown = 0
        #expect(__kk_run_blocking_context(active, suspendBox(), 0, &thrown) == 0)
        #expect(kk_is_cancellation_exception(thrown) != 0)
        #expect(blockingContextProbe.snapshot().finallySeen)
        #expect(runtimeJobHandle(from: active)?.childrenSnapshot().isEmpty == true)
        blockingContextProbe.reset(mode: "finalCancel")
        thrown = 0
        #expect(__kk_run_blocking_context(0, valueBox(), 0, &thrown) == 0)
        #expect(kk_is_cancellation_exception(thrown) != 0)
    }

    @Test(arguments: [0, 1, 2])
    func specifiedSchedulerAlsoOwnsChildInitialWorkAndJoinsItBeforeReturn(kind: Int) throws {
        let caller = pthread_self()
        let dispatcherRaw = kk_dispatcher_named(kind)
        let dispatcher = runtimeResolveDispatcher(from: dispatcherRaw)
        blockingContextProbe.reset(mode: "childObserve")
        var thrown = 0
        #expect(__kk_run_blocking_context(dispatcherRaw, valueBox(), 0, &thrown) == 17)
        #expect(thrown == 0)
        let rows = blockingContextProbe.snapshot().entries
        #expect(rows.count == 2, "body and attached child must execute before return")
        for row in rows {
            #expect(row.3 === dispatcher)
            #expect((pthread_equal(row.0, caller) != 0) == (kind == 2))
        }
    }

    @Test(arguments: ["bodyFailure", "childFailure"])
    func failuresRethrowOriginalAndLeaveSuppliedParentActive(mode: String) {
        let parent = kk_job_new()
        let failure = runtimeAllocateIllegalStateException(message: mode)
        blockingContextProbe.reset(parent: parent, failure: failure, mode: mode)
        var thrown = 0
        #expect(__kk_run_blocking_context(parent, valueBox(), 0, &thrown) == 0)
        #expect(thrown == failure)
        #expect(runtimeJobHandle(from: parent)?.isActiveSnapshot() == true)
        #expect(runtimeJobHandle(from: parent)?.childrenSnapshot().isEmpty == true)
    }

    @Test func legacyBorrowedInvocationKeepsExistingScopeJobAndNilPolicy() throws {
        let scope = RuntimeCoroutineScope()
        let job = scope.installJob()
        let continuation = kk_coroutine_continuation_new(0)
        let state = try #require(runtimeContinuationState(from: continuation))
        state.scope = scope
        state.jobHandle = job
        blockingContextProbe.reset()
        var thrown = 0
        #expect(kk_kxmini_run_blocking_with_cont(
            unsafeBitCast(blockingContextSuspending, to: Int.self), continuation, &thrown
        ) == 17)
        #expect(thrown == 0 && state.blockingScheduler == nil)
        #expect(job.isActiveSnapshot(), "borrowed invoke must not complete the enclosing Job")
        for row in blockingContextProbe.snapshot().entries { #expect(row.1 == job.identityHandle) }
    }
}
