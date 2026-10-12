import Dispatch
import Foundation

// MARK: - Lightweight pthread-based Thread-Local Storage (CORO-003)
//
// These helpers replace `Thread.current.threadDictionary` lookups with direct
// `pthread_key_t` thread-locals.  Each key stores an `Unmanaged` pointer to a
// Swift class instance.  A destructor callback releases the object when the
// thread exits, so there are no leaks.

/// Create a `pthread_key_t` with a destructor that releases the stored object.
func makePthreadKey() -> pthread_key_t {
    var key = pthread_key_t()
    #if canImport(Glibc) || canImport(Musl)
    // Linux: pthread destructor expects Optional pointer.
    pthread_key_create(&key) { (ptr: UnsafeMutableRawPointer?) in
        guard let ptr else { return }
        Unmanaged<AnyObject>.fromOpaque(ptr).release()
    }
    #else
    // Darwin: pthread destructor expects non-optional pointer.
    pthread_key_create(&key) { (ptr: UnsafeMutableRawPointer) in
        Unmanaged<AnyObject>.fromOpaque(ptr).release()
    }
    #endif
    return key
}
/// Read the object stored under `key` for the current thread.
func pthreadGetValue<T: AnyObject>(_ key: pthread_key_t) -> T? {
    guard let raw = pthread_getspecific(key) else { return nil }
    return Unmanaged<T>.fromOpaque(raw).takeUnretainedValue()
}

/// Store `value` under `key` for the current thread, releasing any previous value.
func pthreadSetValue<T: AnyObject>(_ key: pthread_key_t, _ value: T?) {
    // Release previous value if present.
    if let prev = pthread_getspecific(key) {
        Unmanaged<AnyObject>.fromOpaque(prev).release()
    }
    if let value {
        let raw = Unmanaged.passRetained(value).toOpaque()
        pthread_setspecific(key, raw)
    } else {
        pthread_setspecific(key, nil)
    }
}

/// Identifier of a suspend-entry-loop invocation ("task").
///
/// Values are drawn from a global monotonic counter and are never reused, so a
/// map entry that outlives the invocation it belongs to (the async path leaves
/// entries in place for the resume-continuation chain) can never be picked up
/// by a later, unrelated invocation. An `ObjectIdentifier` of a per-invocation
/// token cannot give that guarantee: the allocator reuses the address of a
/// deallocated token, which silently aliases the two invocations and makes
/// `RuntimeContinuationState.current` / `RuntimeCoroutineScope.current` resolve
/// to another coroutine's state.
struct RuntimeTaskKey: Hashable, Sendable {
    let rawValue: UInt64

    private static let lock = NSLock()
    nonisolated(unsafe) private static var nextRawValue: UInt64 = 1

    static func makeUnique() -> RuntimeTaskKey {
        lock.lock()
        let value = nextRawValue
        nextRawValue &+= 1
        lock.unlock()
        return RuntimeTaskKey(rawValue: value)
    }
}

// MARK: - CORO-004 Migration Plan: DispatchSemaphore -> Continuation Model
//
// The suspend-entry loop (`runSuspendEntryLoopWithContinuation`) has already
// been migrated to a non-blocking continuation model.  When a coroutine
// suspends (e.g. `delay()`), a resume closure is installed via
// `installResumeContinuation` and the GCD thread is released immediately.
// The `completionGate` semaphore blocks only at the outermost caller
// (runBlocking / join / await), which is acceptable because those are
// inherently synchronous wait points.
//
// Remaining DispatchSemaphore.wait() sites and migration status:
//
// [DONE] runSuspendEntryLoopWithContinuation: internal suspend points use
//        installResumeContinuation; only completionGate blocks (outermost).
//
// [DONE] RuntimeAsyncTask.awaitResult() and RuntimeJobHandle.join() (CORO-004,
//        Phase 2): suspend-aware via kk_kxmini_async_await / kk_job_join /
//        kk_job_await_completion.  When a caller continuation is supplied, they
//        register a completion resumer (addCompletionResumer / addJoinResumer)
//        and return the coroutine-suspended sentinel instead of blocking; the
//        awaiting coroutine is resumed when the task/job completes (normally,
//        exceptionally, or via cancel).  The lowering treats these callees as
//        suspend points and injects the caller continuation.  The blocking
//        awaitResult()/join() paths remain only as the continuation==0 fallback
//        used by non-suspend contexts (e.g. structured-concurrency child joins).
//        RuntimeAsyncTask no longer uses a task-level `ready` semaphore;
//        completion is delivered exclusively through completionResumers, and
//        sync awaitResult() blocks on a per-waiter gate registered via
//        addCompletionResumer.
//
// [TODO] runtimeFlowDeliverValue (RuntimeCoroutineFlow.swift): the suspend
//        collector path still blocks via waitForResumeSignal().  Full
//        migration requires making runtimeFlowDeliverValue itself async
//        (return via continuation instead of Bool) and restructuring the
//        flow collect loop as a suspend-entry loop.
//
// [DONE] kk_with_context (RuntimeCoroutineContext.swift): caller-blocking
//        semaphore removed for the IO/Default dispatcher path.  When called
//        from inside a coroutine, RuntimeContinuationState.current is captured
//        before the dispatch; the dispatched block calls callerState.resume()
//        on completion, releasing the caller's GCD thread immediately.
//        The non-coroutine fallback (runBlocking top-level, tests) retains the
//        semaphore for backward compatibility.
//
// [TODO] Channel send/receive (RuntimeCoroutineChannel.swift): functionally
//        correct but still blocks on the per-waiter DispatchSemaphore.  The
//        resumeClosure scaffolding exists in SuspendedSender/SuspendedReceiver
//        but is not wired, and the lowering passes continuation=0.  Migration:
//        wire resumeClosure and replace the continuation=0 placeholder with the
//        real caller continuation.  This is the most complex migration because
//        channels involve two independent parties (sender/receiver), each of
//        which may be a coroutine or a raw thread, plus post-wakeup state
//        inspection (delivered / result / cancelledWakeup).
//
// [DEBT-CORO-002 PHASE 1 DONE] RuntimeTypes.swift —
//        RuntimeSequenceCoroutine / RuntimeIteratorBuilderBox: producer now runs
//        on a dedicated OS Thread (Thread.detachNewThread) instead of a GCD
//        pool thread.  Only one thread blocks per iteration step (the consumer);
//        the GCD pool is no longer occupied by the producer between yields.
//        Each type exposes invokeBuilderLambda() for the next phase.
//
// [DEBT-CORO-002 PHASE 2 DONE] RuntimeTypes.swift / RuntimeSequenceBuilders.swift —
//        Consumer-side suspension infrastructure is wired and covered for both
//        runtime types.  Activation from generated code is still pending.
//
//        RuntimeIteratorBuilderBox: probeHasNextAsync(callerState:) installs a
//        resume continuation in consumerGate so no GCD thread is held while the
//        producer runs.  New C entry points __kk_iterator_builder_hasNext_coro /
//        __kk_iterator_builder_next_coro expose this for coroutine-aware callers.
//        Existing __kk_iterator_builder_hasNext / __kk_iterator_builder_next are
//        unchanged — callers do not yet check for COROUTINE_SUSPENDED.
//
//        RuntimeSequenceCoroutine: awaitProducerYieldAsync(callerState:) and
//        nextElementAsync(callerState:) provide the same non-blocking consumer
//        path.  End-of-sequence is signalled via kk_sequence_completed_sentinel()
//        (backed by runtimeStorage.sequenceCompletedBox).  Not yet wired to
//        runtimeTraverseSequenceWithState; that function must become
//        suspension-aware to activate this path.
//
// [DEBT-CORO-002 PHASE 3 DONE] RuntimeTypes.swift / RuntimeSequenceBuilders.swift /
//        CoroutineLoweringPass.swift — compiler-generated sequence/iterator
//        builders now route through kk_*_builder_build_coro.  yield() returns
//        COROUTINE_SUSPENDED from the builder body and the consumer resumes the
//        stored continuation on demand, so generated producers no longer need a
//        dedicated thread.  The old Thread-backed entry points remain as a
//        compatibility fallback for direct non-CPS runtime callbacks/tests.
//
// Priority order (remaining): Channel > flow
// (await/join completed in Phase 2; withContext completed in Phase 3.)
