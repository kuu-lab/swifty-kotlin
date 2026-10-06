import Foundation

/// A single-threaded FIFO run queue ("event loop") owned by a `runBlocking`
/// invocation.
///
/// `kotlinx.coroutines`' `runBlocking` installs a `BlockingEventLoop` as the
/// dispatcher for its own body and for every child launched into it, then
/// drains that loop on the thread that called `runBlocking`. Resumptions
/// therefore happen in strict FIFO order, which is what makes `yield()`
/// deterministic: it re-queues the current coroutine at the tail, behind
/// everything already waiting for a turn.
///
/// Before this type existed, every resumption hop in this runtime went to
/// `DispatchQueue.global()` -- a *concurrent* pool -- and `yield()` additionally
/// waited a millisecond of timer leeway before resuming. The relative order of
/// two coroutines' resumptions was then decided by thread races rather than by
/// a queue, so a program's output varied from run to run.
///
/// `run(until:)` is deliberately re-entrant. A blocking wait that happens *on*
/// the loop thread -- a nested `runBlocking`, `Job.join()` from a non-suspend
/// context, `coroutineScope`'s wait for its children -- drains the queue
/// instead of parking the only thread that can make the awaited work progress.
final class RuntimeEventLoop: @unchecked Sendable {
    /// How long an idle drain parks before re-checking its completion
    /// predicate. Completion normally arrives via `enqueue`/`wake` (both
    /// broadcast), so this bound only matters for a wait satisfied by a
    /// third party that never signals us: it turns a potential hang into a
    /// poll.
    private static let idleWaitSeconds: TimeInterval = 0.005

    private let condition = NSCondition()
    private var pending: [@Sendable () -> Void] = []
    /// Index of the next task to run. Popping by index avoids the O(n) shift
    /// that `Array.removeFirst()` would cost on a busy queue.
    private var nextIndex = 0

    private static let pthreadKey: pthread_key_t = makePthreadKey()

    /// The event loop the current thread is draining, if any.
    ///
    /// Read by the launch entry points and by the suspend-entry loop to decide
    /// whether a coroutine is loop-bound. A body dispatched onto a real
    /// dispatcher queue (`withContext(Dispatchers.IO)`, `launch(Dispatchers.Default)`)
    /// starts on a pool thread where this is `nil`, and so keeps the previous
    /// global-pool behaviour.
    static var current: RuntimeEventLoop? {
        get { pthreadGetValue(pthreadKey) }
        set { pthreadSetValue(pthreadKey, newValue) }
    }

    /// Append `work` to the tail of the queue and wake a draining thread.
    func enqueue(_ work: @escaping @Sendable () -> Void) {
        condition.lock()
        pending.append(work)
        condition.broadcast()
        condition.unlock()
    }

    /// Append a dispatch work item to the tail of the queue.
    ///
    /// `DispatchWorkItem` is not `Sendable`, so it travels inside a box. That is
    /// safe here for the same reason it is safe in `RuntimePendingLaunchQueue`:
    /// the loop runs exactly one task at a time and never hands the item to a
    /// second queue.
    func enqueue(workItem: DispatchWorkItem) {
        let box = RuntimeWorkItemBox(workItem)
        enqueue { box.performUnlessCancelled() }
    }

    /// Wake every draining thread so it re-evaluates its completion predicate.
    ///
    /// Used when a wait is satisfied by something that is not a queued task --
    /// a job completing on a GCD thread, a dispatcher-bound block finishing --
    /// so the drain does not have to wait out `idleWaitSeconds`.
    func wake() {
        condition.lock()
        condition.broadcast()
        condition.unlock()
    }

    /// Pop the head of the queue. Caller must hold `condition`.
    private func popLocked() -> (@Sendable () -> Void)? {
        guard nextIndex < pending.count else {
            if !pending.isEmpty {
                pending.removeAll(keepingCapacity: true)
                nextIndex = 0
            }
            return nil
        }
        let work = pending[nextIndex]
        // Drop the queue's reference so the task (and anything it captured)
        // is released as soon as it has run, not when the queue next compacts.
        pending[nextIndex] = {}
        nextIndex += 1
        if nextIndex == pending.count {
            pending.removeAll(keepingCapacity: true)
            nextIndex = 0
        }
        return work
    }

    /// Hand every task queued right now to the concurrent global dispatch pool,
    /// removing it from this queue.
    ///
    /// The escape hatch for a thread that is about to block on something that is
    /// not a suspension point (see `runtimeWaitDrainingEventLoop`). Running a
    /// queued coroutine inline there would nest it on the blocking thread's own
    /// stack, where it cannot be left suspended: if it then blocks as well --
    /// a channel `send` that arrives before its receiver is ready -- neither
    /// side can move. On its own pool thread it can block independently, which
    /// is what these paths did before this queue existed.
    ///
    /// Each task keeps its event-loop binding, so its *resumptions* still queue
    /// here; only this one turn runs off-loop.
    func offloadReadyTasksToGlobalPool() {
        condition.lock()
        var ready: [@Sendable () -> Void] = []
        while let work = popLocked() {
            ready.append(work)
        }
        condition.unlock()
        for work in ready {
            DispatchQueue.global().async { work() }
        }
    }

    /// Drain tasks until `isDone()` reports completion, or `deadline` passes.
    ///
    /// Returns whether `isDone()` was satisfied. `isDone` is never called while
    /// `condition` is held: completion predicates read their own locks (a job's
    /// state lock, say) and a task-completing thread takes those locks before
    /// calling `enqueue`, so evaluating under `condition` would invert the lock
    /// order between the two.
    @discardableResult
    func run(until isDone: @Sendable () -> Bool, deadline: Date? = nil) -> Bool {
        let saved = RuntimeEventLoop.current
        RuntimeEventLoop.current = self
        defer { RuntimeEventLoop.current = saved }
        while true {
            if isDone() {
                return true
            }
            if let deadline, Date() >= deadline {
                return false
            }
            condition.lock()
            let work = popLocked()
            if work == nil {
                let limit = min(
                    Date().addingTimeInterval(RuntimeEventLoop.idleWaitSeconds),
                    deadline ?? Date.distantFuture
                )
                _ = condition.wait(until: limit)
            }
            condition.unlock()
            work?()
        }
    }
}

/// One-shot completion flag for waits that need a predicate rather than a
/// semaphore, because they may be satisfied while the waiting thread is
/// draining a `RuntimeEventLoop`.
final class RuntimeCompletionFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false

    func set() {
        lock.lock()
        flag = true
        lock.unlock()
    }

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return flag
    }
}

/// Carries a `DispatchWorkItem` into a `RuntimeEventLoop` task.
final class RuntimeWorkItemBox: @unchecked Sendable {
    private let workItem: DispatchWorkItem

    init(_ workItem: DispatchWorkItem) {
        self.workItem = workItem
    }

    /// Mirrors `DispatchQueue.async(execute:)`, which skips a work item that
    /// was cancelled before it began running.
    func performUnlessCancelled() {
        guard !workItem.isCancelled else { return }
        workItem.perform()
    }
}

/// Waits on `semaphore` from a thread that might be draining an event loop.
///
/// Several runtime waits are still plain blocking waits rather than real
/// suspension points: a channel `send`/`receive` rendezvous, and acquiring a
/// `Mutex`/`Semaphore` from a non-suspend context. Parking the loop thread on
/// one of those deadlocks whenever the party that will signal it is a coroutine
/// queued on that same loop -- `launch { ch.send(x) }` followed by
/// `ch.receive()` being the canonical case.
///
/// So this releases the queue before parking, by moving the queued work to the
/// global pool where it can run (and block) on its own thread. The bounded
/// re-check repeats that for work queued while this thread was already waiting.
///
/// This deliberately gives up the queue's ordering for the duration of the
/// wait. These paths were concurrent before the queue existed, and no ordering
/// can be promised while a thread is parked on a non-suspension wait anyway.
func runtimeWaitDrainingEventLoop(_ semaphore: DispatchSemaphore) {
    guard let loop = RuntimeEventLoop.current else {
        semaphore.wait()
        return
    }
    while true {
        loop.offloadReadyTasksToGlobalPool()
        if semaphore.wait(timeout: .now() + .milliseconds(5)) == .success {
            return
        }
    }
}
