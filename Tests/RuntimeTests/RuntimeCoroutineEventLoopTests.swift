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

// The FIFO run queue that gives `runBlocking` deterministic
// resumption order, and the UNDISPATCHED start mode built on top of it.
@Suite(.runtimeIsolation(.gcOnly, resetAdditionalState: resetEventLoopTestState))
struct RuntimeCoroutineEventLoopTests {

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
