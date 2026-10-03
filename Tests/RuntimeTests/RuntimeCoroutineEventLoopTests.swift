import Dispatch
import Foundation
@testable import Runtime
import Testing

private typealias EventLoopTestSuspendEntry = @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int

/// Ordered log shared between the C entry points below and the tests.
private final class EventLoopTestLog: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String] = []

    func record(_ entry: String) {
        lock.lock()
        entries.append(entry)
        lock.unlock()
    }

    func snapshot() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }

    func reset() {
        lock.lock()
        entries.removeAll()
        lock.unlock()
    }
}

private let eventLoopTestLog = EventLoopTestLog()

private func resetEventLoopTestState() {
    eventLoopTestLog.reset()
}

private let undispatchedBodyFunctionID = 8_901

/// Body for the UNDISPATCHED launch tests: records that it ran, then returns.
@_cdecl("runtime_test_undispatched_body")
func runtime_test_undispatched_body(_ continuation: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    eventLoopTestLog.record("body")
    outThrown?.pointee = 0
    return kk_coroutine_state_exit(continuation, 7)
}

private let blockingActorFunctionID = 8_902
private let blockingRootFunctionID = 8_903
private let blockingDescendantFunctionID = 8_904

private func launchEventLoopTestActor(_ entry: EventLoopTestSuspendEntry, functionID: Int) {
    let channel = kk_channel_create(1)
    let continuation = kk_coroutine_continuation_new(functionID)
    _ = __kk_produce_launch_with_cont(channel, unsafeBitCast(entry, to: Int.self), continuation)
}

@_cdecl("runtime_test_blocking_actor")
func runtime_test_blocking_actor(_ continuation: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    if kk_coroutine_state_enter(continuation, blockingActorFunctionID) == 0 {
        eventLoopTestLog.record("actor started")
        _ = kk_coroutine_state_set_label(continuation, 1)
        return kk_kxmini_delay(1, continuation)
    }
    // This inner suspend-value invocation borrows the actor's scope. It must
    // return without joining that scope, which contains the actor itself.
    let callerTaskKey = RuntimeCoroutineScopeTaskKey.currentTaskKey
    let callerState = RuntimeContinuationState.current
    let callerJob = RuntimeJobHandle.current
    let inner = kk_coroutine_continuation_new(undispatchedBodyFunctionID)
    _ = kk_kxmini_run_blocking_with_cont(
        unsafeBitCast(runtime_test_undispatched_body as EventLoopTestSuspendEntry, to: Int.self),
        inner,
        outThrown
    )
    #expect(RuntimeCoroutineScopeTaskKey.currentTaskKey == callerTaskKey)
    #expect(RuntimeContinuationState.current === callerState)
    #expect(RuntimeJobHandle.current === callerJob)
    eventLoopTestLog.record("actor finished")
    return kk_coroutine_state_exit(continuation, 0)
}

@_cdecl("runtime_test_blocking_root")
func runtime_test_blocking_root(_ continuation: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    launchEventLoopTestActor(runtime_test_blocking_actor, functionID: blockingActorFunctionID)
    eventLoopTestLog.record("parent finished")
    return kk_coroutine_state_exit(continuation, 42)
}

@_cdecl("runtime_test_blocking_descendant")
func runtime_test_blocking_descendant(_ continuation: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    launchEventLoopTestActor(runtime_test_blocking_actor, functionID: blockingActorFunctionID)
    eventLoopTestLog.record("child finished")
    return kk_coroutine_state_exit(continuation, 0)
}

@_cdecl("runtime_test_blocking_descendant_root")
func runtime_test_blocking_descendant_root(_ continuation: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    launchEventLoopTestActor(runtime_test_blocking_descendant, functionID: blockingDescendantFunctionID)
    return kk_coroutine_state_exit(continuation, 42)
}

@_cdecl("runtime_test_blocking_actor_failure")
func runtime_test_blocking_actor_failure(_ continuation: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    eventLoopTestLog.record("actor failed")
    outThrown?.pointee = runtimeAllocateThrowable(message: "actor failure")
    return kk_coroutine_state_exit(continuation, 0)
}

@_cdecl("runtime_test_blocking_failure_root")
func runtime_test_blocking_failure_root(_ continuation: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    launchEventLoopTestActor(runtime_test_blocking_actor_failure, functionID: blockingActorFunctionID)
    return kk_coroutine_state_exit(continuation, 42)
}

@_cdecl("runtime_test_blocking_body_failure")
func runtime_test_blocking_body_failure(_ continuation: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    launchEventLoopTestActor(runtime_test_blocking_actor, functionID: blockingActorFunctionID)
    outThrown?.pointee = runtimeAllocateThrowable(message: "body failure")
    return kk_coroutine_state_exit(continuation, 0)
}

@_cdecl("runtime_test_blocking_return_job")
func runtime_test_blocking_return_job(_ continuation: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let handle = kk_kxmini_launch(
        unsafeBitCast(runtime_test_undispatched_body as EventLoopTestSuspendEntry, to: Int.self),
        undispatchedBodyFunctionID
    )
    return kk_coroutine_state_exit(continuation, handle)
}

@_cdecl("runtime_test_blocking_return_deferred")
func runtime_test_blocking_return_deferred(_ continuation: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let handle = kk_kxmini_async(
        unsafeBitCast(runtime_test_undispatched_body as EventLoopTestSuspendEntry, to: Int.self),
        undispatchedBodyFunctionID
    )
    return kk_coroutine_state_exit(continuation, handle)
}

// The FIFO run queue that gives `runBlocking` deterministic
// resumption order, and the UNDISPATCHED start mode built on top of it.
@Suite(.runtimeIsolation(.gcOnly, resetAdditionalState: resetEventLoopTestState))
struct RuntimeCoroutineEventLoopTests {

    // MARK: - runBlocking child completion

    @Test func testRunBlockingWaitsForActorAfterBodyReturnsWithoutSuspending() {
        var thrown = 0
        let result = kk_kxmini_run_blocking(
            unsafeBitCast(runtime_test_blocking_root as EventLoopTestSuspendEntry, to: Int.self),
            blockingRootFunctionID,
            &thrown
        )
        eventLoopTestLog.record("runBlocking returned")
        #expect(thrown == 0)
        #expect(result == 42)
        #expect(eventLoopTestLog.snapshot() == [
            "parent finished", "actor started", "body", "actor finished", "runBlocking returned",
        ])
    }

    @Test func testRunBlockingWaitsForDescendantsRegisteredWhileJoining() {
        var thrown = 0
        let result = kk_kxmini_run_blocking(
            unsafeBitCast(runtime_test_blocking_descendant_root as EventLoopTestSuspendEntry, to: Int.self),
            blockingRootFunctionID,
            &thrown
        )
        #expect(thrown == 0)
        #expect(result == 42)
        #expect(eventLoopTestLog.snapshot() == ["child finished", "actor started", "body", "actor finished"])
    }

    @Test func testRunBlockingPropagatesActorFailure() {
        var thrown = 0
        let result = kk_kxmini_run_blocking(
            unsafeBitCast(runtime_test_blocking_failure_root as EventLoopTestSuspendEntry, to: Int.self),
            blockingRootFunctionID,
            &thrown
        )
        #expect(result == 0)
        #expect(thrown != 0)
        #expect(eventLoopTestLog.snapshot() == ["actor failed"])
    }

    @Test func testRunBlockingCancelsActorOnBodyFailure() {
        var thrown = 0
        let result = kk_kxmini_run_blocking(
            unsafeBitCast(runtime_test_blocking_body_failure as EventLoopTestSuspendEntry, to: Int.self),
            blockingRootFunctionID,
            &thrown
        )
        #expect(result == 0)
        #expect(thrown != 0)
        #expect(eventLoopTestLog.snapshot().isEmpty, "the queued actor must be cancelled before it starts")
    }

    @Test func testRunBlockingKeepsReturnedJobAliveAfterJoining() {
        var thrown = 0
        let handle = kk_kxmini_run_blocking(
            unsafeBitCast(runtime_test_blocking_return_job as EventLoopTestSuspendEntry, to: Int.self),
            blockingRootFunctionID,
            &thrown
        )
        #expect(thrown == 0)
        let job = resolveLiveRuntimeHandle(handle, as: RuntimeJobHandle.self)
        #expect(job != nil, "a returned Job must remain registered after its scope completes")
        #expect(job?.completedSnapshot() == true)
    }

    @Test func testRunBlockingKeepsReturnedDeferredAliveAfterJoining() {
        var thrown = 0
        let handle = kk_kxmini_run_blocking(
            unsafeBitCast(runtime_test_blocking_return_deferred as EventLoopTestSuspendEntry, to: Int.self),
            blockingRootFunctionID,
            &thrown
        )
        #expect(thrown == 0)
        let task = resolveLiveRuntimeHandle(handle, as: RuntimeAsyncTask.self)
        #expect(task != nil, "a returned Deferred must remain registered after its scope completes")
        #expect(task?.isCompletedSnapshot() == true)
    }

    // MARK: - RuntimeEventLoop

    @Test func testRunDrainsTasksInEnqueueOrder() {
        let loop = RuntimeEventLoop()
        let log = EventLoopTestLog()
        for index in 0 ..< 5 {
            loop.enqueue { log.record("task \(index)") }
        }
        let done = RuntimeCompletionFlag()
        loop.enqueue { done.set() }

        let finished = loop.run(until: { done.isSet })
        #expect(finished)
        #expect(log.snapshot() == (0 ..< 5).map { "task \($0)" })
    }

    @Test func testTaskEnqueuedWhileDrainingRunsAfterTasksAlreadyQueued() {
        let loop = RuntimeEventLoop()
        let log = EventLoopTestLog()
        let done = RuntimeCompletionFlag()

        // "first" re-queues itself, exactly as `yield()` does. The re-queued
        // turn must come after "second", which was already waiting. The drain
        // ends on that re-queued turn, so reaching it is part of the assertion.
        loop.enqueue {
            log.record("first")
            loop.enqueue {
                log.record("first again")
                done.set()
            }
        }
        loop.enqueue { log.record("second") }

        let finished = loop.run(until: { done.isSet })
        #expect(finished)
        #expect(log.snapshot() == ["first", "second", "first again"])
    }

    @Test func testCurrentIsInstalledOnlyWhileDraining() {
        let loop = RuntimeEventLoop()
        #expect(RuntimeEventLoop.current == nil)

        let observed = EventLoopTestLog()
        let done = RuntimeCompletionFlag()
        loop.enqueue {
            observed.record(RuntimeEventLoop.current === loop ? "bound" : "unbound")
            done.set()
        }
        let finished = loop.run(until: { done.isSet })
        #expect(finished)

        #expect(observed.snapshot() == ["bound"])
        #expect(RuntimeEventLoop.current == nil, "the drain must restore the previous loop on exit")
    }

    @Test func testRunGivesUpAtItsDeadlineWhenCompletionNeverArrives() {
        let loop = RuntimeEventLoop()
        let started = Date()
        let finished = loop.run(until: { false }, deadline: started.addingTimeInterval(0.05))
        #expect(!finished, "run must report that the predicate was never satisfied")
        #expect(Date().timeIntervalSince(started) < 2.0, "the deadline must be honoured promptly")
    }

    @Test func testNestedRunDrainsTheSameQueue() {
        let loop = RuntimeEventLoop()
        let log = EventLoopTestLog()
        let outerDone = RuntimeCompletionFlag()
        let innerDone = RuntimeCompletionFlag()

        // A task that itself blocks on a nested drain -- the shape taken by a
        // nested runBlocking, and by `join()` called on the loop thread.
        loop.enqueue {
            log.record("outer start")
            loop.enqueue {
                log.record("inner")
                innerDone.set()
            }
            _ = loop.run(until: { innerDone.isSet })
            log.record("outer end")
            outerDone.set()
        }

        let finished = loop.run(until: { outerDone.isSet })
        #expect(finished)
        #expect(log.snapshot() == ["outer start", "inner", "outer end"])
    }

    // MARK: - CoroutineStart.UNDISPATCHED

    @Test func testUndispatchedLaunchRunsBodyBeforeReturning() {
        let entryRaw = unsafeBitCast(
            runtime_test_undispatched_body as EventLoopTestSuspendEntry,
            to: Int.self
        )
        let jobHandle = kk_kxmini_launch_undispatched(entryRaw, undispatchedBodyFunctionID)

        #expect(jobHandle != 0, "launch should return a job handle")
        #expect(
            eventLoopTestLog.snapshot() == ["body"],
            "UNDISPATCHED must run the body inline, before the launch call returns"
        )
        #expect(kk_job_join(jobHandle, 0) == 7)
    }

    @Test func testUndispatchedLaunchRestoresTheCallersCoroutineIdentity() {
        // The nested entry loop installs its own task key and removes it on the
        // way out; the caller's ambient scope has to survive that, or the
        // statements after the launch would lose their parent scope.
        let scopeHandle = kk_coroutine_scope_new()
        let scope = Unmanaged<RuntimeCoroutineScope>.fromOpaque(
            UnsafeMutableRawPointer(bitPattern: scopeHandle)!
        ).takeUnretainedValue()
        #expect(RuntimeCoroutineScope.current === scope)

        let entryRaw = unsafeBitCast(
            runtime_test_undispatched_body as EventLoopTestSuspendEntry,
            to: Int.self
        )
        let jobHandle = kk_kxmini_launch_undispatched(entryRaw, undispatchedBodyFunctionID)
        #expect(jobHandle != 0)

        #expect(
            RuntimeCoroutineScope.current === scope,
            "the caller's ambient scope must be restored after an inline start"
        )
        #expect(kk_job_join(jobHandle, 0) == 7)
        _ = kk_coroutine_scope_wait(scopeHandle)
    }
}
