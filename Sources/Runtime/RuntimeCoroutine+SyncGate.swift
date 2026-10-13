import Dispatch
import Foundation

private final class RuntimeResumeContinuationBox: @unchecked Sendable {
    let closure: @Sendable () -> Void

    init(_ closure: @escaping @Sendable () -> Void) {
        self.closure = closure
    }

    func invoke() {
        closure()
    }
}

// MARK: - CORO-004: Cooperative Sync Gate

/// One-shot gate for cooperative producer/consumer synchronization.
///
/// Used by lazy sequence/iterator builders during the CORO-004 migration.
/// Supports non-blocking resume via a continuation closure (for suspend-point
/// wiring) with a `DispatchSemaphore` fallback for legacy synchronous callers.
final class RuntimeCoroutineSyncGate: @unchecked Sendable {
    private let lock = NSLock()
    private var resumeContinuation: RuntimeResumeContinuationBox?
    private var fallbackSemaphore: DispatchSemaphore?
    private var signalPending = false

    /// Wake a waiter. Prefer an installed continuation (async dispatch) over a
    /// fallback semaphore signal.
    func signal() {
        lock.lock()
        if let cont = resumeContinuation {
            resumeContinuation = nil
            lock.unlock()
            DispatchQueue.global(qos: .userInitiated).async {
                cont.invoke()
            }
            return
        }
        if let sem = fallbackSemaphore {
            lock.unlock()
            sem.signal()
            return
        }
        signalPending = true
        lock.unlock()
    }

    /// Wait until `signal()`.
    ///
    /// When `resumeContinuation` is provided, installs it instead of blocking
    /// the current thread and returns `true`. Returns `false` when the wait was
    /// satisfied synchronously (pending signal or semaphore wakeup).
    @discardableResult
    func wait(resumeContinuation continuation: (@Sendable () -> Void)? = nil) -> Bool {
        lock.lock()
        if signalPending {
            signalPending = false
            lock.unlock()
            return false
        }
        if let continuation {
            resumeContinuation = RuntimeResumeContinuationBox(continuation)
            lock.unlock()
            return true
        }
        if fallbackSemaphore == nil {
            fallbackSemaphore = DispatchSemaphore(value: 0)
        }
        let sem = fallbackSemaphore!
        lock.unlock()
        runtimeWaitDrainingEventLoop(sem)
        return false
    }
}

final class RuntimeContinuationState: @unchecked Sendable {
    var functionID: Int64
    var label: Int64
    var completion: Int64
    var spillSlots: [Int64: Int64]
    var launcherArgs: [Int64: Int64]
    // The link from continuation state to job handle is weak on purpose:
    // - to avoid retain cycles between RuntimeJobHandle and RuntimeContinuationState
    // - because job handle lifetime is managed externally and cancellation is best-effort.
    // If the jobHandle is deallocated before cancellation is observed, the continuation
    // will simply not be woken by cancellation, which is an accepted behavior.
    weak var jobHandle: RuntimeJobHandle?
    /// CORO-003: The coroutine scope is carried in the continuation context instead
    /// of Thread Local Storage, so it survives suspend/resume across threads.
    var scope: RuntimeCoroutineScope?
    /// Flow collect context carried with the continuation so a flow emitter can
    /// continue delivering values after a suspend/resume on another thread.
    var flowCollectContext: RuntimeFlowCollectContext?
    /// Stores a thrown exception pointer when the coroutine body throws.
    /// Zero means no exception was thrown.  Set by runSuspendEntryLoopWithContinuation
    /// and consumed by kk_kxmini_launch_with_exception_handler to reliably
    /// distinguish exception returns from normal (possibly non-zero) return values.
    var thrownException: Int = 0
    /// The `runBlocking` event loop this coroutine is bound to, if any.
    ///
    /// Adopted from `RuntimeEventLoop.current` the first time the suspend-entry
    /// loop runs this continuation, and consulted by every resumption hop
    /// (`signalResume`, `installResumeContinuation`) so a resumption is queued
    /// on the loop -- in FIFO order -- instead of racing on the concurrent
    /// global pool. `nil` keeps the original global-pool behaviour, which is
    /// what dispatcher-bound bodies and direct runtime (test) calls get.
    var eventLoop: RuntimeEventLoop?
    // Public builders leave scheduling to the intercepted continuation itself.
    var resumesInline = false
    var builderContext: RuntimeCoroutineContext?
    private var uninterceptedEntryPointRaw: Int = 0
    private var uninterceptedCompletionContinuation: Int = 0
    private var hasStartedUninterceptedCoroutine = false
    // Cancellation must wake the innermost call and let it unwind before its caller.
    private var suspendedCallChild: RuntimeContinuationState?
    private let interceptionLock = NSRecursiveLock()
    private var generatedContextRaw: Int?
    private var interceptedContinuationRaw: Int?
    private var continuationInterceptorRaw: Int = 0
    private var interceptionReleased = false
    private let stateLock = NSLock()
    /// STDLIB-CORO-BUG-01: one-shot resume guard.
    /// Set to `true` atomically (under `stateLock`) by the first successful resume
    /// so that any subsequent resume call is rejected with an `IllegalStateException`.
    /// Reset by `resetResumeState()` when the coroutine advances to the next suspend point.
    private var hasResumed: Bool = false
    private var cancellableDelivery: RuntimeCancellableContinuation?
    private var delayTimers: [ObjectIdentifier: DispatchSourceTimer]
    private static let taskStateLock = NSLock()
    nonisolated(unsafe) private static var taskStateMap: [RuntimeTaskKey: RuntimeContinuationState] = [:]

    /// CORO-004: Continuation-based resume model.
    ///
    /// Instead of blocking a GCD thread with DispatchSemaphore.wait(), we store
    /// a resume closure when the coroutine suspends.  When signalResume() is
    /// called (from a timer, cancellation, etc.) the closure is dispatched on a
    /// GCD queue, releasing the original thread back to the pool.
    ///
    /// If no continuation closure is installed (e.g. during tests that call
    /// waitForResumeSignal() synchronously), we fall back to a one-shot
    /// DispatchSemaphore for backward compatibility.
    private var resumeContinuation: RuntimeResumeContinuationBox?
    /// Lazily created fallback semaphore, only used by legacy synchronous
    /// callers that invoke waitForResumeSignal() without a continuation.
    private var fallbackSemaphore: DispatchSemaphore?
    /// True if signalResume() was called before any continuation or wait was
    /// installed (edge case: timer fires immediately).
    private var resumeSignalPending = false
    private var cancellationShieldDepth = 0

    // CORO-003: Task-local continuation state registry (replaces TLS).
    // Maps an opaque task token (assigned by the suspend-entry loop on entry) to
    // the continuation state that is current for that execution context. This allows
    // `RuntimeContinuationState.current` to work from code that runs inside a
    // suspend-entry loop without an explicit continuation handle.

    /// Install continuation state for the given task key. Called at the top of the
    /// suspend-entry loop so that suspend function calls can discover the current state.
    static func installState(_ state: RuntimeContinuationState?, forTask key: RuntimeTaskKey) {
        taskStateLock.lock()
        if let state {
            taskStateMap[key] = state
        } else {
            taskStateMap.removeValue(forKey: key)
        }
        taskStateLock.unlock()
    }

    /// Remove the task-state mapping when a suspend-entry loop finishes.
    static func removeState(forTask key: RuntimeTaskKey) {
        taskStateLock.lock()
        taskStateMap.removeValue(forKey: key)
        taskStateLock.unlock()
    }

    /// Look up the continuation state installed for the current GCD dispatch work-item.
    /// Falls back to nil if the current thread is not inside a suspend-entry loop.
    static func stateForTask(_ key: RuntimeTaskKey) -> RuntimeContinuationState? {
        taskStateLock.lock()
        defer { taskStateLock.unlock() }
        return taskStateMap[key]
    }

    /// Convenience accessor used by suspend function invocations when they don't have a
    /// continuation handle. Uses the thread-level task key installed by the
    /// nearest enclosing suspend-entry loop.
    ///
    /// NOTE: This is *not* TLS for the state itself -- the state lives on the
    /// continuation. The task key is only used to *find* which continuation's
    /// state is active on this thread right now.
    static var current: RuntimeContinuationState? {
        get {
            let key = RuntimeCoroutineScopeTaskKey.currentTaskKey
            return stateForTask(key)
        }
        set {
            let key = RuntimeCoroutineScopeTaskKey.currentTaskKey
            installState(newValue, forTask: key)
        }
    }

    init(
        functionID: Int64,
        label: Int64 = 0,
        completion: Int64 = 0,
        spillSlots: [Int64: Int64] = [:],
        launcherArgs: [Int64: Int64] = [:],
        delayTimers: [ObjectIdentifier: DispatchSourceTimer] = [:]
    ) {
        self.functionID = functionID
        self.label = label
        self.completion = completion
        self.spillSlots = spillSlots
        self.launcherArgs = launcherArgs
        self.delayTimers = delayTimers
        RuntimeLiveHandles.register(self)
    }

    func configureUninterceptedCoroutine(entryPointRaw: Int, completionContinuation: Int) {
        stateLock.lock()
        self.resumesInline = true
        self.uninterceptedEntryPointRaw = entryPointRaw
        self.uninterceptedCompletionContinuation = completionContinuation
        self.hasStartedUninterceptedCoroutine = false
        stateLock.unlock()
    }

    func takeUninterceptedCoroutineStart() -> (entryPointRaw: Int, completionContinuation: Int)? {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard uninterceptedEntryPointRaw != 0, !hasStartedUninterceptedCoroutine else {
            return nil
        }
        hasStartedUninterceptedCoroutine = true
        return (
            entryPointRaw: uninterceptedEntryPointRaw,
            completionContinuation: uninterceptedCompletionContinuation
        )
    }

    func generatedCoroutineContext(outThrown: UnsafeMutablePointer<Int>?) -> Int? {
        interceptionLock.lock()
        defer { interceptionLock.unlock() }
        guard uninterceptedCompletionContinuation != 0 else {
            return nil
        }
        if let generatedContextRaw {
            return generatedContextRaw
        }
        var thrown = 0
        let context = __kk_coroutine_continuation_context(uninterceptedCompletionContinuation, &thrown)
        outThrown?.pointee = thrown
        if thrown == 0 {
            generatedContextRaw = context
        }
        return context
    }

    func intercepted(continuationRaw: Int, interceptorKey: Int, outThrown: UnsafeMutablePointer<Int>?) -> Int {
        interceptionLock.lock()
        defer { interceptionLock.unlock() }
        if let interceptedContinuationRaw {
            return interceptedContinuationRaw
        }
        if interceptionReleased {
            return continuationRaw
        }
        var thrown = 0
        let context = generatedCoroutineContext(outThrown: &thrown)
            ?? runtimeRegisterObject(makeContinuationContext())
        if thrown != 0 {
            outThrown?.pointee = thrown
            return continuationRaw
        }
        let interceptor = runtimeContinuationInterceptor(context: context, key: interceptorKey, outThrown: &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            return continuationRaw
        }
        let result = runtimeInterceptGeneratedContinuation(
            interceptor: interceptor, continuation: continuationRaw, outThrown: &thrown
        )
        outThrown?.pointee = thrown
        if thrown == 0 {
            continuationInterceptorRaw = interceptor
            interceptedContinuationRaw = result
        }
        return result
    }

    func releaseInterception(continuationRaw: Int) {
        interceptionLock.lock()
        guard !interceptionReleased else {
            interceptionLock.unlock()
            return
        }
        interceptionReleased = true
        let intercepted = interceptedContinuationRaw ?? continuationRaw
        let interceptor = continuationInterceptorRaw
        interceptionLock.unlock()
        if intercepted != continuationRaw, interceptor != 0 {
            runtimeReleaseInterceptedContinuation(interceptor: interceptor, continuation: intercepted)
        }
    }

    deinit {
        RuntimeLiveHandles.unregister(self)
        let timers = releaseAllDelayTimers()
        for timer in timers {
            timer.setEventHandler(handler: nil)
            timer.cancel()
        }
    }

    /// Install the current continuation state for the given task key.
    static func installCurrent(_ state: RuntimeContinuationState?, forTask key: RuntimeTaskKey) {
        taskStateLock.lock()
        if let state {
            taskStateMap[key] = state
        } else {
            taskStateMap.removeValue(forKey: key)
        }
        taskStateLock.unlock()
    }

    /// Remove the current continuation state for the given task key.
    static func removeCurrent(forTask key: RuntimeTaskKey) {
        taskStateLock.lock()
        taskStateMap.removeValue(forKey: key)
        taskStateLock.unlock()
    }

    func scheduleDelay(milliseconds: Int) {
        if let scheduler = scope?.testSchedulerIfPresent() {
            scheduler.schedule(after: Int64(max(0, milliseconds))) { [weak self] in
                self?.signalResume()
            }
            return
        }

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
        let timerID = ObjectIdentifier(timer as AnyObject)
        stateLock.lock()
        delayTimers[timerID] = timer
        stateLock.unlock()

        timer.schedule(deadline: .now() + .milliseconds(max(0, milliseconds)))
        timer.setEventHandler { [weak self] in
            self?.completeDelayTimer(timerID: timerID)
        }
        timer.resume()
    }

    /// CORO-004: Install a resume continuation.  Called by the suspend-entry
    /// loop right before it would otherwise block.  If a resume signal has
    /// already been delivered (pending), the continuation is dispatched
    /// immediately.
    func installResumeContinuation(_ continuation: @escaping @Sendable () -> Void) {
        let boxedContinuation = RuntimeResumeContinuationBox(continuation)
        stateLock.lock()
        if resumeSignalPending {
            resumeSignalPending = false
            let loop = eventLoop
            stateLock.unlock()
            // Signal already arrived — re-queue the continuation immediately.
            //
            // On a runBlocking event loop this lands at the TAIL of the queue,
            // and that is precisely what makes `yield()` FIFO: `yield()` resumes
            // its own continuation synchronously during the burst (marking a
            // pending signal, since nothing is installed yet), the suspension
            // handler flushes the coroutines this burst launched, and only then
            // installs -- so the yielding coroutine queues up behind them.
            if let loop {
                loop.enqueue { boxedContinuation.invoke() }
            } else {
                DispatchQueue.global().async {
                    boxedContinuation.invoke()
                }
            }
            return
        }
        resumeContinuation = boxedContinuation
        stateLock.unlock()
    }

    func consumePendingExceptionalResume() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard resumeSignalPending, thrownException != 0 else {
            return false
        }
        resumeSignalPending = false
        hasResumed = false
        return true
    }

    func installCancellableDelivery(_ continuation: RuntimeCancellableContinuation) {
        stateLock.lock()
        cancellableDelivery = continuation
        stateLock.unlock()
    }

    func consumeCancellableDelivery() {
        stateLock.lock()
        let delivery = cancellableDelivery
        cancellableDelivery = nil
        stateLock.unlock()
        guard let delivery else { return }
        let result = delivery.takeResultForDelivery()
        stateLock.lock()
        completion = Int64(runtimeResultValueOrNull(result))
        thrownException = runtimeResultIsSuccess(result) ? 0 : runtimeResultExceptionOrNull(result)
        stateLock.unlock()
    }

    /// Legacy blocking wait.  Used only when no continuation has been installed
    /// (e.g. direct test calls).  Creates a one-shot semaphore on demand.
    func waitForResumeSignal() {
        stateLock.lock()
        if resumeSignalPending {
            resumeSignalPending = false
            stateLock.unlock()
            return
        }
        if fallbackSemaphore == nil {
            fallbackSemaphore = DispatchSemaphore(value: 0)
        }
        let sem = fallbackSemaphore!
        stateLock.unlock()
        runtimeWaitDrainingEventLoop(sem)
    }

    func beginCancellationShield() {
        stateLock.lock()
        cancellationShieldDepth += 1
        stateLock.unlock()
    }

    func endCancellationShield() {
        stateLock.lock()
        cancellationShieldDepth -= 1
        stateLock.unlock()
    }

    /// Wake the coroutine. Cancellation from a replaced Job must not resume
    /// a shielded withContext caller, but ordinary block completion still can.
    func signalResume(isCancellation: Bool = false) {
        stateLock.lock()
        if isCancellation, cancellationShieldDepth > 0 {
            stateLock.unlock()
            return
        }
        if let child = suspendedCallChild {
            stateLock.unlock()
            child.signalResume(isCancellation: isCancellation)
            return
        }
        if let cont = resumeContinuation {
            resumeContinuation = nil
            let loop = eventLoop
            let inlineResume = resumesInline
            stateLock.unlock()
            // Queue the resumption on the coroutine's event loop when it has
            // one, so resumptions keep the loop's FIFO order instead of being
            // ordered by whichever global-pool thread happens to pick them up.
            if inlineResume {
                cont.invoke()
            } else if let loop {
                loop.enqueue { cont.invoke() }
            } else {
                DispatchQueue.global().async {
                    cont.invoke()
                }
            }
            return
        }
        if let sem = fallbackSemaphore {
            stateLock.unlock()
            sem.signal()
            return
        }
        // Neither continuation nor semaphore installed yet — mark pending.
        resumeSignalPending = true
        stateLock.unlock()
    }

    /// Resume the continuation with a successful value.
    ///
    /// Returns `nil` on success. If the continuation has already been resumed
    /// (one-shot guard), returns a raw pointer to a `RuntimeIllegalStateExceptionBox`
    /// describing the double-resume violation (STDLIB-CORO-BUG-01).
    /// The flag is set BEFORE delivering the result to prevent re-entrant resume.
    @discardableResult
    func resume(with value: Int) -> Int? {
        stateLock.lock()
        if hasResumed {
            stateLock.unlock()
            let ise = runtimeAllocateIllegalStateException(
                message: "Already resumed, but proposed with update \(value)"
            )
            return ise
        }
        hasResumed = true
        completion = Int64(value)
        thrownException = 0
        stateLock.unlock()
        signalResume()
        return nil
    }

    /// Resume the continuation with a thrown exception.
    ///
    /// Returns `nil` on success. If the continuation has already been resumed
    /// (one-shot guard), returns a raw pointer to a `RuntimeIllegalStateExceptionBox`
    /// describing the double-resume violation (STDLIB-CORO-BUG-01).
    /// The flag is set BEFORE delivering the result to prevent re-entrant resume.
    @discardableResult
    func resume(withException exception: Int) -> Int? {
        stateLock.lock()
        if hasResumed {
            stateLock.unlock()
            let ise = runtimeAllocateIllegalStateException(
                message: "Already resumed, but proposed with exception"
            )
            return ise
        }
        hasResumed = true
        completion = 0
        thrownException = exception
        stateLock.unlock()
        signalResume()
        return nil
    }

    /// Deliver a double-resume `IllegalStateException` so that the coroutine body
    /// observes the violation the next time it reads state.  Overwrites `thrownException`
    /// and resets `completion` to 0.  Called by C-level entry points when the one-shot
    /// guard fires (STDLIB-CORO-BUG-01).
    func deliverDoubleResumeException(_ ise: Int) {
        stateLock.lock()
        thrownException = ise
        completion = 0
        stateLock.unlock()
    }

    func makeContinuationContext() -> RuntimeCoroutineContext {
        let jobRaw = jobHandle?.identityHandle ?? 0
        let inherited = scope?.context
        let builder = builderContext
        // Merge `inherited.plus(builderContext)` without allocating so the
        // canonicalizer lookup below is allocation-free on a hit: the
        // builder's dispatcher/name/handler win when present (KUU-1387). A
        // handle-only dispatcher element (the event loop, or one propagated
        // by a withContext merge) occupies the slot the same way a tag does.
        let builderHasDispatcher = (builder?.dispatcherElementHandle ?? 0) != 0
        let mergedName = (builder?.name ?? inherited?.name) ?? scope?.name
        let mergedDispatcher = builderHasDispatcher
            ? (builder?.dispatcher ?? 0)
            : (inherited?.dispatcher ?? 0)
        var mergedDispatcherHandle = builderHasDispatcher
            ? (builder?.dispatcherHandleRaw ?? 0)
            : (inherited?.dispatcherHandleRaw ?? 0)
        let mergedHandler = builder?.exceptionHandler ?? inherited?.exceptionHandler
        // KUU-1405: carry source-defined elements through; builder extras win
        // per key over inherited ones, and any extras claiming a built-in key
        // lose to the merged built-in field (e.g. the coroutine's own Job).
        let mergedExtras = runtimeMergedContextExtras(
            inherited: inherited?.extras ?? [],
            override: builder?.extras ?? [],
            jobPresent: jobRaw != 0,
            namePresent: mergedName != nil,
            dispatcherPresent: mergedDispatcher != 0 || mergedDispatcherHandle != 0,
            handlerPresent: mergedHandler != nil
        )
        // KUU-1395: a coroutine bound to a runBlocking event loop exposes the
        // loop's element as its `ContinuationInterceptor` — the runtime
        // analogue of kotlinx's BlockingEventLoop — whenever nothing else
        // occupies the dispatcher slot (an explicit dispatcher wins on JVM
        // too).
        if mergedDispatcher == 0 && mergedDispatcherHandle == 0,
           !mergedExtras.contains(where: {
               $0.key == kk_continuation_interceptor_key()
                   || $0.key == kk_coroutine_dispatcher_key()
           }),
           let elementRaw = eventLoop?.elementHandle()
        {
            mergedDispatcherHandle = elementRaw
        }
        return runtimeCanonicalCoroutineContext(
            dispatcher: mergedDispatcher,
            dispatcherHandleRaw: mergedDispatcherHandle,
            name: mergedName,
            nameHandleRaw: builder?.name != nil
                ? (builder?.nameHandleRaw ?? 0)
                : (inherited?.nameHandleRaw ?? 0),
            exceptionHandler: mergedHandler,
            jobHandleRaw: jobRaw,
            extras: mergedExtras
        )
    }

    /// Whether this coroutine's resumptions are queued on a `runBlocking`
    /// event loop rather than dispatched to the concurrent global pool.
    var isBoundToEventLoop: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return eventLoop != nil
    }

    /// Reset resume state for the next suspend point.  Called after the
    /// coroutine loop resumes to prepare for the next potential suspension.
    /// Also resets the one-shot guard (STDLIB-CORO-BUG-01) so the next
    /// suspend point can accept a fresh resume.
    func resetResumeState() {
        stateLock.lock()
        resumeContinuation = nil
        fallbackSemaphore = nil
        resumeSignalPending = false
        hasResumed = false
        stateLock.unlock()
    }

    func bindSuspendedCallChild(_ child: RuntimeContinuationState) {
        stateLock.lock()
        suspendedCallChild = child
        let pending = resumeSignalPending
        resumeSignalPending = false
        stateLock.unlock()
        if pending {
            child.signalResume()
        }
    }

    func unbindSuspendedCallChild(_ child: RuntimeContinuationState) {
        stateLock.lock()
        if suspendedCallChild === child {
            suspendedCallChild = nil
        }
        stateLock.unlock()
    }

    private func completeDelayTimer(timerID: ObjectIdentifier) {
        stateLock.lock()
        delayTimers.removeValue(forKey: timerID)
        stateLock.unlock()
        signalResume()
    }

    private func releaseAllDelayTimers() -> [DispatchSourceTimer] {
        stateLock.lock()
        defer { stateLock.unlock() }
        let timers = Array(delayTimers.values)
        delayTimers.removeAll(keepingCapacity: false)
        return timers
    }
}

/// CORO-004: Outcome of a suspend-aware task await.
enum RuntimeTaskAwaitOutcome: Equatable {
    /// Task finished (already complete, or blocking wait returned).
    case completed(result: Int, thrownException: Int)
    /// Registered a completion resumer; the caller must return `kk_coroutine_suspended()`.
    case suspended
}

private final class RuntimeTaskAwaitSnapshot: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Int = 0
    private var thrownException: Int = 0

    func store(result: Int, thrownException: Int) {
        lock.lock()
        self.result = result
        self.thrownException = thrownException
        lock.unlock()
    }

    func load() -> RuntimeTaskAwaitOutcome {
        lock.lock()
        let value = result
        let thrown = thrownException
        lock.unlock()
        return .completed(result: value, thrownException: thrown)
    }
}

final class RuntimeAsyncTask: @unchecked Sendable {
    let completionJob = RuntimeJobHandle()
    private let atomicStart: Bool
    private let lock = NSLock()
    private var isCompleted = false
    private(set) var isCancelled = false
    private var result: Int = 0
    /// Stores a thrown exception (as a raw pointer Int) when the async body fails.
    /// Zero means no exception was thrown.
    private(set) var thrownException: Int = 0
    /// Set to true when user code consumes this handle's passRetained
    /// (via kk_kxmini_async_await or kk_job_join). Checked by scope's waitForChildren
    /// to avoid double-releasing the original passRetained.
    private var isConsumedByUserCode = false
    /// Actual body entry, distinct from an explicit LAZY start request.
    private var isBodyStarted = false
    private var isStartRequested = false
    /// CORO-004: Resumers invoked with (result, thrownException) when the task completes
    /// (normally, exceptionally, or via cancel). Suspend-aware awaiters
    /// (`kk_kxmini_async_await`) and the synchronous `awaitResult()` fallback both
    /// register here so completion never blocks on a task-level semaphore.
    private var completionResumers: [@Sendable (Int, Int) -> Void] = []
    /// STDLIB-CORO-001: the deferred-start action of an
    /// `async(start = CoroutineStart.LAZY)` task. Set when
    /// `kk_kxmini_async_lazy` returns; `startIfNeeded()` runs it exactly once.
    private var lazyStartBody: (@Sendable () -> Void)?

    /// KUU-1386: tasks minted by `async`-family launchers answer `is Deferred`
    /// (DeferredCoroutine shape); launch/produce tasks do not. Read by the
    /// `kk_op_is` job-family nominal recovery.
    var isDeferredResult = false

    init(atomicStart: Bool = false, debugName: String? = nil) {
        self.atomicStart = atomicStart
        // KUU-1352: the task IS the kotlinx coroutine object; its toString
        // delegates to the completion job's name/state.
        completionJob.debugName = debugName
        if atomicStart {
            completionJob.markStarted()
        }
        RuntimeLiveHandles.register(self)
        completionJob.associatedHandle = Int(bitPattern: Unmanaged.passUnretained(self).toOpaque())
    }

    deinit {
        RuntimeLiveHandles.unregister(self)
    }

    /// CORO-004: Register a resumer invoked when this task completes. If the task is
    /// already complete, the resumer runs immediately on the calling thread.
    func addCompletionResumer(_ resumer: @escaping @Sendable (Int, Int) -> Void) {
        lock.lock()
        if isCompleted {
            let snapshotResult = result
            let snapshotThrown = thrownException
            lock.unlock()
            resumer(snapshotResult, snapshotThrown)
            return
        }
        completionResumers.append(resumer)
        lock.unlock()
    }

    @discardableResult
    func markStarted() -> Bool {
        lock.lock()
        guard !isCompleted, !isCancelled || atomicStart else {
            lock.unlock()
            return false
        }
        isBodyStarted = true
        completionJob.markStarted()
        lock.unlock()
        return true
    }

    /// STDLIB-CORO-001: Capture the deferred-start action for a LAZY task.
    /// Mirrors `RuntimeJobHandle.installLazyStartBody`.
    func installLazyStartBody(_ body: @escaping @Sendable () -> Void) {
        lock.lock()
        if !isBodyStarted, !isStartRequested, !isCompleted {
            lazyStartBody = body
        }
        lock.unlock()
    }

    /// STDLIB-CORO-001: Start a LAZY task by dispatching its body exactly once.
    ///
    /// Called from `awaitResult(callerState:afterResume:)`, which every await
    /// and structured-concurrency join funnels through, so demanding the result
    /// of a lazily started `async` is what starts it -- as in Kotlin, where
    /// `Deferred.await()` starts a `CoroutineStart.LAZY` coroutine.
    ///
    /// A task cancelled before it started never runs, which is what
    /// `RuntimeJobHandle.startIfNeeded()` gets from its `state == .new` guard.
    /// `cancel()` marks the task completed, so `isCompleted` alone would cover
    /// it; `isCancelled` is named too because that is the property that matters.
    ///
    /// `body` runs after the lock is released: it dispatches the block, and
    /// `NSLock` is not recursive.
    @discardableResult
    func startIfNeeded() -> Bool {
        lock.lock()
        guard let body = lazyStartBody, !isCompleted, !isCancelled else {
            lazyStartBody = nil
            lock.unlock()
            return false
        }
        lazyStartBody = nil
        isStartRequested = true
        completionJob.markScheduled()
        lock.unlock()
        body()
        return true
    }

    func markScheduledForLaunch() {
        lock.lock()
        isStartRequested = true
        completionJob.markScheduled()
        lock.unlock()
    }

    func markConsumedByUserCode() {
        lock.lock()
        isConsumedByUserCode = true
        lock.unlock()
    }

    func consumedByUserCodeSnapshot() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return isConsumedByUserCode
    }

    /// Thread-safe snapshot of the completion state.
    func isCompletedSnapshot() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return isCompleted
    }

    /// Thread-safe snapshot of the cancellation flag.
    func isCancelledSnapshot() -> Bool {
        lock.lock()
        let taskIsCancelled = isCancelled
        lock.unlock()
        // A scope may cancel the task's completion job before the task itself
        // receives its final exceptional completion.
        return taskIsCancelled || completionJob.cancellationSnapshot()
    }

    /// Thread-safe snapshot of the active state (started, not completed, not cancelled).
    func isActiveSnapshot() -> Bool {
        lock.lock()
        let taskIsActive = (isBodyStarted || isStartRequested) && !isCompleted && !isCancelled
        lock.unlock()
        // Job.isActive becomes false as soon as its completion job is cancelling,
        // even while the task body is still unwinding.
        return taskIsActive
            && !completionJob.cancellationSnapshot()
            && !completionJob.isFailedSnapshot()
    }

    /// Thread-safe snapshot for `kk_job_is_failed` (aligned with `RuntimeJobHandle.isFailedSnapshot`).
    func isFailedSnapshot() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return isCompleted && thrownException != 0
    }

    func completionSnapshot() -> (completed: Bool, value: Int, exception: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (isCompleted, result, thrownException)
    }

    func complete(with result: Int) {
        finish(result: result, exception: 0)
    }

    /// Complete the task with an exception (CORO-071: async exception handling).
    func completeExceptionally(with exception: Int) {
        finish(result: 0, exception: exception)
    }

    private func finish(result: Int, exception: Int) {
        let jobCause = completionJob.cancellationCauseSnapshot()
        let failure = jobCause != 0 && jobCause != runtimeNullSentinelInt
            && kk_is_cancellation_exception(jobCause) == 0 ? jobCause : exception
        lock.lock()
        guard !isCompleted else {
            lock.unlock()
            return
        }
        self.result = isCancelled ? 0 : result
        let cancellationCause = thrownException
        if !isCancelled || (failure != 0 && kk_is_cancellation_exception(failure) == 0) {
            thrownException = failure
        }
        isCompleted = true
        let snapshotResult = self.result
        let snapshotThrown = thrownException
        let snapshotCancelled = isCancelled
        let resumers = completionResumers
        completionResumers = []
        lock.unlock()
        if snapshotCancelled {
            // Cancellation may still be publishing the job state on another thread.
            _ = completionJob.cancel(cause: cancellationCause)
        }
        if snapshotThrown != 0 {
            _ = completionJob.completeExceptionally(with: snapshotThrown)
        } else {
            _ = completionJob.complete(with: snapshotResult)
        }
        for resumer in resumers {
            resumer(snapshotResult, snapshotThrown)
        }
    }

    func cancel(cause: Int = 0) {
        lock.lock()
        guard !isCompleted, !isCancelled else {
            lock.unlock()
            return
        }
        isCancelled = true
        thrownException = cause != 0 && cause != runtimeNullSentinelInt
            ? cause
            : runtimeAllocateCancellationException(message: completionJob.defaultCancellationMessage)
        lazyStartBody = nil
        // Running and ATOMIC bodies must finish (including finally) before join resumes.
        isCompleted = !isBodyStarted && !atomicStart
        let resumers = isCompleted ? completionResumers : []
        if isCompleted {
            completionResumers = []
        }
        let snapshotResult = result
        let snapshotThrown = thrownException
        lock.unlock()
        _ = completionJob.cancel(cause: snapshotThrown)
        for resumer in resumers {
            resumer(snapshotResult, snapshotThrown)
        }
    }

    /// CORO-004: Await the task result, optionally suspending via `callerState`.
    ///
    /// When `callerState` is non-nil and the task has not completed yet, registers a
    /// completion resumer and returns `.suspended` instead of blocking a GCD thread.
    /// `afterResume` runs after the caller continuation is resumed (e.g. to release a
    /// passRetained handle). Pass `callerState: nil` for the blocking fallback used by
    /// non-suspend contexts (structured-concurrency child joins, `kk_await_all`, etc.).
    func awaitResult(
        callerState: RuntimeContinuationState?,
        afterResume: (@Sendable () -> Void)? = nil,
        propagateFailure: Bool = true
    ) -> RuntimeTaskAwaitOutcome {
        // STDLIB-CORO-001: start a LAZY task on demand before awaiting it, the
        // same way `RuntimeJobHandle.join()` does. This is the one choke point
        // every await reaches -- `awaitResult()`, `kk_kxmini_async_await` and
        // `kk_job_join` all route through here -- so no await path can register
        // for a completion that nothing would ever produce.
        startIfNeeded()
        lock.lock()
        if isCompleted {
            let value = propagateFailure ? result : 0
            let thrown = propagateFailure ? thrownException : 0
            lock.unlock()
            if thrown != 0, let callerState {
                // Already completed exceptionally: resume the caller's continuation
                // with the exception and report suspension so the state machine
                // throws after it returns.
                _ = callerState.resume(withException: thrown)
                return .suspended
            }
            return .completed(result: value, thrownException: thrown)
        }
        lock.unlock()

        if let callerState {
            addCompletionResumer { result, thrown in
                if propagateFailure, thrown != 0 {
                    callerState.resume(withException: thrown)
                } else {
                    callerState.resume(with: propagateFailure ? result : 0)
                }
                afterResume?()
            }
            return .suspended
        }

        // BUG-041: blocking fallback (see RuntimeJobHandle.join()) -- flush
        // undispatched launches from this thread before the gate.wait() below
        // so a task that's still pending in RuntimePendingLaunchQueue actually
        // gets a chance to run and signal completion.
        RuntimePendingLaunchQueue.flush()
        let gate = DispatchSemaphore(value: 0)
        let snapshot = RuntimeTaskAwaitSnapshot()
        // Same reasoning as RuntimeJobHandle.join(): when the caller is draining
        // a runBlocking event loop, the awaited body is probably queued on it,
        // so drain rather than park.
        let completed = RuntimeCompletionFlag()
        let callerLoop = RuntimeEventLoop.current
        addCompletionResumer { result, thrown in
            snapshot.store(result: propagateFailure ? result : 0, thrownException: propagateFailure ? thrown : 0)
            completed.set()
            gate.signal()
            callerLoop?.wake()
        }
        if let callerLoop {
            callerLoop.run(until: { completed.isSet })
        } else {
            gate.wait()
        }
        return snapshot.load()
    }

    /// Blocking await for non-suspend contexts. Suspend-aware awaiting is handled by
    /// `awaitResult(callerState:afterResume:)` (CORO-004); see `kk_kxmini_async_await`.
    func awaitResult() -> Int {
        switch awaitResult(callerState: nil) {
        case .completed(let result, let thrown):
            return thrown != 0 ? thrown : result
        case .suspended:
            fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: blocking awaitResult cannot suspend")
        }
    }

}
