import Foundation

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
    /// Completion normally arrives via `enqueue`/`wake` (both broadcast), so
    /// this bound only matters for a wait satisfied by a third party that
    /// never signals us: it turns a potential hang into a poll.
    private static let idleWaitSeconds: TimeInterval = 0.005

    private let condition = NSCondition()
    private var pending: [@Sendable () -> Void] = []
    /// Popping by index avoids the O(n) shift that `Array.removeFirst()`
    /// would cost on a busy queue.
    private var nextIndex = 0

    /// KUU-2688: consulted by `run(until:)` only when the queue is empty and
    /// the loop is about to block — the one place "nothing else to do" is
    /// observable. Returning true reports progress and the loop re-checks
    /// `isDone` instead of waiting. `runReadyTasks` deliberately does NOT
    /// consult it, so a synchronous burst (e.g. `advanceTimeBy` inside a
    /// `runTest` body) cannot be preempted by queued virtual-time work; only
    /// a blocking drain counts as idle, matching upstream's TestDispatcher
    /// auto-advance. `RuntimeTestScheduler` installs its pump here while a
    /// `runTest` run is in flight.
    private var idleAction: (@Sendable () -> Bool)?

    func installIdleAction(_ action: (@Sendable () -> Bool)?) {
        condition.lock()
        idleAction = action
        condition.unlock()
    }

    /// Minted lazily so every read of the context resolves to the same
    /// element object.
    private var cachedElementRaw = 0

    /// The runBlocking event-loop context element, as a registered object.
    ///
    /// It is a `RuntimeDispatcher` so `element is CoroutineDispatcher`,
    /// `element is ContinuationInterceptor`, and the `key`/`get`/`fold`/
    /// `minusKey` element members bridge like the named dispatchers do. Its
    /// tag is 0: the loop is the scheduling mechanism itself, so nothing may
    /// resolve the element to a dispatch queue — `resolveToCoroutineContext`
    /// maps it to a handle-only context, and interception through it is a
    /// no-op (`kk_context_get_dispatcher` returns 0).
    func elementHandle() -> Int {
        condition.lock()
        defer { condition.unlock() }
        if cachedElementRaw == 0 {
            let dispatcher = RuntimeDispatcher(
                queue: DispatchQueue(label: "kk.runblocking.eventloop"),
                tag: 0,
                displayName: "BlockingEventLoop"
            )
            dispatcher.blockingEventLoop = self
            cachedElementRaw = runtimeRegisterObject(dispatcher)
        }
        return cachedElementRaw
    }

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

    func enqueue(_ work: @escaping @Sendable () -> Void) {
        condition.lock()
        pending.append(work)
        condition.broadcast()
        condition.unlock()
    }

    /// `DispatchWorkItem` is not `Sendable`, so it travels inside a box. That is
    /// safe here for the same reason it is safe in `RuntimePendingLaunchQueue`:
    /// the loop runs exactly one task at a time and never hands the item to a
    /// second queue.
    func enqueue(workItem: DispatchWorkItem) {
        let box = RuntimeWorkItemBox(workItem)
        enqueue { box.performUnlessCancelled() }
    }

    /// Used when a wait is satisfied by something that is not a queued task --
    /// a job completing on a GCD thread, a dispatcher-bound block finishing --
    /// so the drain does not have to wait out `idleWaitSeconds`.
    func wake() {
        condition.lock()
        condition.broadcast()
        condition.unlock()
    }

    /// `TestCoroutineScheduler` uses this after releasing virtual-time
    /// continuations so child coroutines make progress before the scheduler
    /// reports itself idle. This is also safe when called re-entrantly from a
    /// coroutine that is already running on this loop.
    func runReadyTasks() {
        let saved = RuntimeEventLoop.current
        RuntimeEventLoop.current = self
        defer { RuntimeEventLoop.current = saved }
        while true {
            condition.lock()
            let work = popLocked()
            condition.unlock()
            guard let work else { return }
            work()
        }
    }

    /// Caller must hold `condition`.
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
            let idle = work == nil ? idleAction : nil
            condition.unlock()
            if let work {
                work()
                continue
            }
            if let idle, idle() {
                continue
            }
            condition.lock()
            let limit = min(
                Date().addingTimeInterval(RuntimeEventLoop.idleWaitSeconds),
                deadline ?? Date.distantFuture
            )
            let gcBlocking = runtimeGCSafepoints.beginBlockingIfEnrolled()
            _ = condition.wait(until: limit)
            condition.unlock()
            if gcBlocking { runtimeGCSafepoints.endBlocking() }
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
        let gcBlocking = runtimeGCSafepoints.beginBlockingIfEnrolled()
        semaphore.wait()
        if gcBlocking { runtimeGCSafepoints.endBlocking() }
        return
    }
    while true {
        loop.offloadReadyTasksToGlobalPool()
        let gcBlocking = runtimeGCSafepoints.beginBlockingIfEnrolled()
        let result = semaphore.wait(timeout: .now() + .milliseconds(5))
        if gcBlocking { runtimeGCSafepoints.endBlocking() }
        if result == .success {
            return
        }
    }
}
