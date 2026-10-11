import Dispatch
import Foundation

// MARK: - Structured Concurrency (P5-89)

private enum RuntimeJobState: Equatable, Sendable {
    case new
    case active
    case completing
    case completed
    case cancelling
    case cancelled
    case failed

    var isCompleted: Bool {
        switch self {
        case .completed, .cancelled, .failed:
            return true
        case .new, .active, .completing, .cancelling:
            return false
        }
    }

    var isCancelled: Bool {
        switch self {
        case .cancelling, .cancelled:
            return true
        case .new, .active, .completing, .completed, .failed:
            return false
        }
    }

    var isActive: Bool {
        self == .active
    }
}

/// Per-task key for the current job handle. Mirrors the scope task-key bridge.

/// Per-thread holder of the current task key. The key itself is a plain value;
/// this box only provides pthread-TLS storage for it.
private final class RuntimeTaskKeyBox {
    let key: RuntimeTaskKey

    init(key: RuntimeTaskKey) {
        self.key = key
    }
}

enum RuntimeJobHandleTaskKey {
    private static let pthreadKey: pthread_key_t = makePthreadKey()

    static var currentTaskKey: RuntimeTaskKey {
        if let existing: RuntimeTaskKeyBox = pthreadGetValue(pthreadKey) {
            return existing.key
        }
        let box = RuntimeTaskKeyBox(key: .makeUnique())
        pthreadSetValue(pthreadKey, box)
        return box.key
    }

}

/// BUG-041 fix: tracks whether the current thread is synchronously inside a
/// `runSuspendEntryLoopWithContinuation` burst (running compiled Kotlin
/// coroutine body code), as opposed to a raw/host call straight into a
/// `kk_kxmini_*` entry point (e.g. white-box runtime tests that call
/// `kk_kxmini_launch` directly and never suspend or join anything). Only the
/// former can race a synchronous `cancel()` against the dispatch queue --
/// there's no "next yield" to defer to for the latter, so deferring
/// unconditionally would leave those launches stranded forever.
///
/// A depth counter (not a flag) so a burst that itself synchronously drives a
/// nested `runSuspendEntryLoopWithContinuation` (e.g. a nested `runBlocking`)
/// doesn't have the inner call's exit clear the outer burst's "active" status
/// early.
enum RuntimeCoroutineBurstDepth {
    private static let pthreadKey: pthread_key_t = makePthreadKey()
    private final class Box: @unchecked Sendable { var depth: Int = 0 }

    private static func currentBox() -> Box {
        if let existing: Box = pthreadGetValue(pthreadKey) {
            return existing
        }
        let box = Box()
        pthreadSetValue(pthreadKey, box)
        return box
    }

    static func enter() { currentBox().depth += 1 }
    static func exit() { let box = currentBox(); box.depth = max(0, box.depth - 1) }
    static var isActive: Bool { currentBox().depth > 0 }
}

/// BUG-041 fix: defers the real GCD dispatch of a launched job's work item
/// until the enqueuing thread's current synchronous burst actually yields
/// (the next suspension or completion inside `runSuspendEntryLoopWithContinuation`).
///
/// Real kotlinx.coroutines schedules a freshly `launch`-ed child onto the same
/// single-threaded event loop as its parent, so the child never gets a turn to
/// run until the parent suspends or finishes. `DispatchQueue.global()` gives
/// this runtime true OS-thread parallelism instead, so without this queue a
/// pool thread can start running the child (and observe "not yet cancelled")
/// before a synchronous, same-thread `job.cancel()` right after `launch{}`
/// takes effect -- the exact race in BUG-041. Deferring dispatch until this
/// thread's burst yields makes that race impossible: a `cancel()` called
/// before the next yield always finds the job still undispatched.
enum RuntimePendingLaunchQueue {
    private static let pthreadKey: pthread_key_t = makePthreadKey()

    private final class Box: @unchecked Sendable {
        var items: [(job: RuntimeJobHandle, workItem: DispatchWorkItem)] = []
    }

    private static func currentBox() -> Box {
        if let existing: Box = pthreadGetValue(pthreadKey) {
            return existing
        }
        let box = Box()
        pthreadSetValue(pthreadKey, box)
        return box
    }

    /// Event-loop work joins the FIFO immediately; the loop cannot run it until
    /// the caller yields. Only pool-bound work needs staging until `flush()` to
    /// keep synchronous cancellation from racing with dispatch.
    static func enqueue(job: RuntimeJobHandle, workItem: DispatchWorkItem) {
        if let scheduler = job.continuationState?.scope?.testSchedulerIfPresent() {
            let boxedWorkItem = RuntimeWorkItemBox(workItem)
            scheduler.schedule(after: 0) {
                boxedWorkItem.performUnlessCancelled()
            }
            return
        }

        guard RuntimeEventLoop.current == nil, RuntimeCoroutineBurstDepth.isActive else {
            KxMiniRuntime.launch(workItem: workItem)
            return
        }
        currentBox().items.append((job, workItem))
    }

    /// Dispatch every work item queued on this thread since the last flush.
    /// Jobs already cancelled while pending are dropped instead of dispatched --
    /// equivalent to `DispatchWorkItem.cancel()` winning before the block runs.
    static func flush() {
        let box = currentBox()
        guard !box.items.isEmpty else { return }
        let pending = box.items
        box.items = []
        for entry in pending where !entry.job.cancellationSnapshot() {
            KxMiniRuntime.launch(workItem: entry.workItem)
        }
    }
}

/// A job handle representing a launched coroutine. Supports join, cancellation,
/// explicit completion, and parent-child propagation.
final class RuntimeJobHandle: @unchecked Sendable {
    var associatedHandle: Int = 0
    var identityHandle: Int {
        associatedHandle != 0 ? associatedHandle : Int(bitPattern: Unmanaged.passUnretained(self).toOpaque())
    }
    private let lock = NSLock()
    // A source factory can expose a Kotlin wrapper while the hierarchy keeps
    // raw runtime handles internally. Do not retain a wrapper through its job.
    private weak var sourceWrapper: RuntimeObjectBox?

    func bindSourceWrapper(_ wrapper: RuntimeObjectBox) {
        lock.lock()
        sourceWrapper = wrapper
        lock.unlock()
    }

    var sourceIdentityHandle: Int {
        lock.lock()
        let wrapper = sourceWrapper
        lock.unlock()
        guard let wrapper else { return identityHandle }
        let raw = Int(bitPattern: Unmanaged.passUnretained(wrapper).toOpaque())
        guard wrapper.coroutineJobHandle == identityHandle,
              runtimeStorage.withGCLock({ $0.objectPointers.contains(UInt(bitPattern: raw)) })
        else { return identityHandle }
        return raw
    }

    private let completionSemaphore = DispatchSemaphore(value: 0)
    private var state: RuntimeJobState = .new
    private var result: Int = 0
    private var failure: Int = 0
    private var cancelCause: Int = 0
    private var cancelMessage: String = "CancellationException"
    private var usesDefaultCancellationMessage = false
    private let defaultCancellationMessageFallback: String
    weak var continuationState: RuntimeContinuationState?
    var producerChannel: Int?
    private var childJobHandles: [Int] = []
    private weak var parentJob: RuntimeJobHandle?
    /// Set on the handle returned by `kotlinx.coroutines.SupervisorJob()`. Lets
    /// `CoroutineScope(context)` (see `kk_coroutine_scope_new_with_context`) tell a plain
    /// `Job()` in the context apart from a `SupervisorJob()`, so the constructed scope gets
    /// the right sibling-failure-isolation semantics.
    var isSupervisorMarker = false
    /// Scoped builders report failures through their caller's throw channel.
    var propagatesFailureToParent = true
    private var childFailureObservers: [@Sendable (Int) -> Void] = []
    /// KUU-1386: nominal identity a bare job handle claims in `kk_op_is`
    /// nominal checks. Bound wrapper jobs take their wrapper's nominal (so a
    /// `Job()` job surfaced via `coroutineContext.job` still answers
    /// `is CompletableJob`/`is JobImpl`), `kk_job_new`/`kk_supervisor_job_new`
    /// factory jobs claim JobImpl, and 0 falls back to the generic
    /// coroutine-job claim (AbstractCoroutine-family, like kotlinx's
    /// BlockingCoroutine/StandaloneCoroutine jobs).
    var nominalJobTypeID: Int64 = 0
    /// KUU-1352: kotlinx `toDebugString()` class name for jobs that have no
    /// bound source wrapper — set by the launcher that mints the handle
    /// (`"BlockingCoroutine"`, `"StandaloneCoroutine"`, ...). Bound wrapper
    /// jobs ignore this: `runtimeJobToStringName` resolves their name from
    /// the wrapper class's nominal ID instead, like kotlinx's
    /// `classSimpleName`.
    var debugName: String? = nil
    /// Set to true when user code consumes this handle's passRetained
    /// (via kk_job_join). Checked by scope's waitForChildren
    /// to avoid double-releasing the original passRetained.
    private var isConsumedByUserCode = false
    /// The underlying dispatch work item for fire-and-forget launches. Kept weak
    /// so that cancellation can prevent the body from starting when the job is
    /// cancelled before the dispatched closure begins.
    weak var dispatchWorkItem: DispatchWorkItem? = nil
    /// Distinguishes a scheduled active job from one whose body has begun.
    /// Cancellation can complete the former immediately when its work item is
    /// cancelled before execution starts.
    private var hasStartedExecuting = false
    /// CORO-004: Resumers invoked with the terminal value when the job completes.
    /// Lets a suspend-aware `Job.join()` caller resume via its continuation instead
    /// of blocking a GCD thread on `completionSemaphore`.
    private var joinResumers: [@Sendable (Int) -> Void] = []
    /// KUU-CORO-101: backing for `Job.invokeOnCompletion`. Each entry fires at
    /// most once and is then removed: an `onCancelling` entry fires as soon as
    /// the job enters `.cancelling` (or immediately, for a job cancelled before
    /// it started executing); every remaining entry fires once the job reaches
    /// a terminal state. `dispose()` (via `removeCompletionHandler`) removes an
    /// entry that has not fired yet.
    private struct CompletionHandlerEntry {
        let id: Int
        let onCancelling: Bool
        let handler: @Sendable (Int) -> Void
    }
    private var completionHandlers: [CompletionHandlerEntry] = []
    private var nextCompletionHandlerID = 1
    /// STDLIB-CORO-001: Closure that dispatches the body for CoroutineStart.LAZY.
    /// Set when `kk_kxmini_launch_lazy` returns; `startIfNeeded()` runs it once.
    private var lazyStartBody: (@Sendable () -> Void)?

    var defaultCancellationMessage: String {
        guard let debugName else { return defaultCancellationMessageFallback }
        return "\(debugName) was cancelled"
    }

    init(defaultCancellationMessage: String = "CancellationException") {
        self.defaultCancellationMessageFallback = defaultCancellationMessage
        RuntimeLiveHandles.register(self)
    }

    deinit {
        RuntimeLiveHandles.unregister(self)
    }

    static var current: RuntimeJobHandle? {
        get {
            let key = RuntimeJobHandleTaskKey.currentTaskKey
            return currentForTask(key)
        }
        set {
            let key = RuntimeJobHandleTaskKey.currentTaskKey
            installCurrent(newValue, forTask: key)
        }
    }

    private static let taskJobLock = NSLock()
    nonisolated(unsafe) private static var taskJobMap: [RuntimeTaskKey: RuntimeJobHandle] = [:]

    private static func installCurrent(_ job: RuntimeJobHandle?, forTask key: RuntimeTaskKey) {
        taskJobLock.lock()
        if let job {
            taskJobMap[key] = job
        } else {
            taskJobMap.removeValue(forKey: key)
        }
        taskJobLock.unlock()
    }

    private static func currentForTask(_ key: RuntimeTaskKey) -> RuntimeJobHandle? {
        taskJobLock.lock()
        defer { taskJobLock.unlock() }
        return taskJobMap[key]
    }

    func markStarted() {
        lock.lock()
        hasStartedExecuting = true
        if state == .new {
            state = .active
        }
        lock.unlock()
    }

    /// Publishes the active state as soon as launch returns, before the
    /// dispatch queue gets a chance to run the body.
    func markScheduled() {
        lock.lock()
        if state == .new {
            state = .active
        }
        lock.unlock()
    }

    /// STDLIB-CORO-001: Capture the deferred-start action for a LAZY job.
    func installLazyStartBody(_ body: @escaping @Sendable () -> Void) {
        lock.lock()
        if state == .new {
            lazyStartBody = body
        }
        lock.unlock()
    }

    /// STDLIB-CORO-001: Start a LAZY job by dispatching its body exactly once.
    @discardableResult
    func startIfNeeded() -> Bool {
        lock.lock()
        guard state == .new, let body = lazyStartBody else {
            lock.unlock()
            return false
        }
        lazyStartBody = nil
        state = .active
        lock.unlock()
        body()
        return true
    }

    func markBodyless() {
        lock.lock()
        hasStartedExecuting = false
        lock.unlock()
    }

    /// KUU-1352: kotlinx `JobSupport.stateString` mapping — the `{State}`
    /// component of `toString()`. Exceptional completion renders as
    /// `Cancelled` (a failed `Deferred` prints `{Cancelled}` on the JVM).
    func toStringStateName() -> String {
        lock.lock()
        let current = state
        lock.unlock()
        switch current {
        case .new: return "New"
        case .active: return "Active"
        case .completing: return "Completing"
        case .cancelling: return "Cancelling"
        case .cancelled, .failed: return "Cancelled"
        case .completed: return "Completed"
        }
    }

    func registerChild(_ childHandle: Int) {
        let childJob = runtimeJobHandle(from: childHandle) ?? runtimeAsyncTask(from: childHandle)?.completionJob
        childJob?.attachParent(self)
        lock.lock()
        if !childJobHandles.contains(childHandle) {
            childJobHandles.append(childHandle)
        }
        let shouldCancelImmediately = state.isCancelled || state.isCompleted
        lock.unlock()
        if shouldCancelImmediately {
            runtimeCancelChild(childHandle)
        }
    }

    private func attachParent(_ parent: RuntimeJobHandle) {
        lock.lock()
        parentJob = parent
        lock.unlock()
    }

    /// KUU-1386: `ChildHandle.dispose()` backing — drop the child registration
    /// and clear the child's recorded parent when it points back here.
    func detachChild(_ childHandle: Int) {
        let childJob = runtimeJobHandle(from: childHandle) ?? runtimeAsyncTask(from: childHandle)?.completionJob
        childJob?.clearParentIfMatches(self)
        lock.lock()
        childJobHandles.removeAll { $0 == childHandle }
        lock.unlock()
    }

    private func clearParentIfMatches(_ parent: RuntimeJobHandle) {
        lock.lock()
        if parentJob === parent {
            parentJob = nil
        }
        lock.unlock()
    }

    func parentSnapshot() -> RuntimeJobHandle? {
        lock.lock()
        defer { lock.unlock() }
        return state.isCompleted ? nil : parentJob
    }

    func childrenSnapshot() -> [Int] {
        lock.lock()
        let children = childJobHandles
        lock.unlock()
        return children.filter { handle in
            if let job = runtimeJobHandle(from: handle) {
                return !job.completedSnapshot()
            }
            if let task = runtimeAsyncTask(from: handle) {
                return !task.isCompletedSnapshot()
            }
            return false
        }
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

    /// CORO-004: Register a resumer invoked with the terminal value when the job
    /// completes (normally, exceptionally, or via cancellation). If the job is
    /// already complete, the resumer runs immediately on the calling thread.
    func addJoinResumer(_ resumer: @escaping @Sendable (Int) -> Void) {
        lock.lock()
        if state.isCompleted {
            let value = terminalValueLocked()
            lock.unlock()
            resumer(value)
            return
        }
        joinResumers.append(resumer)
        lock.unlock()
    }

    /// KUU-CORO-101: register a completion handler, returning a disposal id
    /// (0 if the handler already fired inline because the job was already
    /// terminal). Must be called with `lock` unlocked.
    func addCompletionHandler(
        onCancelling: Bool,
        invokeImmediately: Bool = true,
        handler: @escaping @Sendable (Int) -> Void
    ) -> Int {
        lock.lock()
        if state.isCompleted || (onCancelling && state == .cancelling) {
            let cause = completionCauseLocked()
            lock.unlock()
            if invokeImmediately {
                handler(cause)
            }
            return 0
        }
        let id = nextCompletionHandlerID
        nextCompletionHandlerID += 1
        completionHandlers.append(CompletionHandlerEntry(id: id, onCancelling: onCancelling, handler: handler))
        lock.unlock()
        return id
    }

    /// KUU-CORO-101: dispose a completion handler registered via
    /// `addCompletionHandler`. A no-op if it already fired or was disposed.
    func removeCompletionHandler(id: Int) {
        guard id != 0 else { return }
        lock.lock()
        completionHandlers.removeAll { $0.id == id }
        lock.unlock()
    }

    private func terminalValueLocked() -> Int {
        switch state {
        case .completed:
            return result
        case .failed:
            return failure
        case .cancelled:
            return cancelCause
        case .new, .active, .completing, .cancelling:
            return 0
        }
    }

    func completionSnapshot() -> (completed: Bool, value: Int, exception: Int) {
        lock.lock()
        defer { lock.unlock() }
        let cause = completionCauseLocked()
        return (state.isCompleted, result, cause == runtimeNullSentinelInt ? 0 : cause)
    }

    /// KUU-CORO-101: the value `invokeOnCompletion` handlers receive as
    /// `cause` -- unlike `terminalValueLocked()`, a *successful* completion
    /// reports Kotlin `null` (not the result), matching `Job.invokeOnCompletion`'s
    /// `(cause: Throwable?) -> Unit` contract. `runtimeNullSentinelInt`
    /// (`Int64.min`), not `0`, is the correct "null" representation for a
    /// value that crosses into a real Kotlin `(Throwable?) -> Unit` closure
    /// invocation -- see [[function-type-param-abi-split-convention]].
    private func completionCauseLocked() -> Int {
        switch state {
        case .completed, .new, .active, .completing:
            return runtimeNullSentinelInt
        case .failed:
            return failure
        case .cancelled, .cancelling:
            return cancelCause
        }
    }

    private func completeLocked(successState: RuntimeJobState, value: Int, failureValue: Int = 0) -> Bool {
        switch state {
        case .new, .active:
            state = .completing
            if successState == .completed {
                result = value
                failure = 0
                cancelCause = 0
                state = .completed
            } else if successState == .failed {
                failure = failureValue
                result = 0
                cancelCause = 0
                state = .failed
            }
            return true
        case .cancelling:
            // The coroutine body has finished executing (including catch/finally blocks)
            // after observing cancellation. Transition to fully cancelled so that
            // join() can return. The cancelCause is preserved from when cancel() was called.
            if successState == .failed, failureValue != 0, kk_is_cancellation_exception(failureValue) == 0 {
                failure = cancelCause != 0 && kk_is_cancellation_exception(cancelCause) == 0
                    ? cancelCause : failureValue
                state = .failed
            } else {
                state = .cancelled
            }
            return true
        case .completed, .cancelled, .failed:
            return false
        case .completing:
            return false
        }
    }

    func complete(with value: Int) -> Bool {
        lock.lock()
        let shouldSignal = completeLocked(successState: .completed, value: value)
        let resumers = shouldSignal ? joinResumers : []
        let handlers = shouldSignal ? completionHandlers : []
        if shouldSignal {
            joinResumers = []
            completionHandlers = []
        }
        let terminal = shouldSignal ? terminalValueLocked() : 0
        let cause = shouldSignal ? completionCauseLocked() : 0
        lock.unlock()
        if shouldSignal {
            completionSemaphore.signal()
            for resumer in resumers {
                resumer(terminal)
            }
            for entry in handlers {
                entry.handler(cause)
            }
        }
        return shouldSignal
    }

    func completeExceptionally(with exception: Int) -> Bool {
        lock.lock()
        let shouldSignal = completeLocked(successState: .failed, value: 0, failureValue: exception)
        let resumers = shouldSignal ? joinResumers : []
        let handlers = shouldSignal ? completionHandlers : []
        if shouldSignal {
            joinResumers = []
            completionHandlers = []
        }
        let terminal = shouldSignal ? terminalValueLocked() : 0
        let cause = shouldSignal ? completionCauseLocked() : 0
        let parent = shouldSignal && propagatesFailureToParent ? parentJob : nil
        lock.unlock()
        if shouldSignal {
            if exception != 0, kk_is_cancellation_exception(exception) == 0 {
                parent?.childFailed(with: exception)
            }
            completionSemaphore.signal()
            for resumer in resumers {
                resumer(terminal)
            }
            for entry in handlers {
                entry.handler(cause)
            }
        }
        return shouldSignal
    }

    /// Notify ancestors before waking awaiters, so caught await failures still
    /// leave ordinary parents and siblings cancelled. Supervisors stop the chain.
    func childFailed(with exception: Int) {
        guard !isSupervisorMarker else { return }
        lock.lock()
        let parent = propagatesFailureToParent ? parentJob : nil
        let observers = childFailureObservers
        lock.unlock()
        for observer in observers { observer(exception) }
        _ = cancel(cause: exception)
        parent?.childFailed(with: exception)
    }

    func addChildFailureObserver(_ observer: @escaping @Sendable (Int) -> Void) {
        lock.lock()
        childFailureObservers.append(observer)
        lock.unlock()
    }

    func cancel(cause: Int = 0) -> Bool {
        let causeMessage = cancellationMessage(for: cause)
        let usesDefaultMessage = causeMessage == nil
        return cancel(
            message: causeMessage ?? defaultCancellationMessage,
            cause: cause,
            usesDefaultMessage: usesDefaultMessage
        )
    }

    private func cancellationMessage(for cause: Int) -> String? {
        guard cause != 0, cause != runtimeNullSentinelInt,
              kk_is_cancellation_exception(cause) != 0,
              let pointer = UnsafeMutableRawPointer(bitPattern: cause),
              let cancellation = tryCast(pointer, to: RuntimeCancellationBox.self)
        else {
            return nil
        }
        return cancellation.message ?? "CancellationException"
    }

    @discardableResult
    func cancel(message: String, cause: Int = 0) -> Bool {
        cancel(message: message, cause: cause, usesDefaultMessage: false)
    }

    @discardableResult
    private func cancel(message: String, cause: Int, usesDefaultMessage: Bool) -> Bool {
        let resolvedCause = cause != 0 && cause != runtimeNullSentinelInt
            ? cause : runtimeAllocateCancellationException(message: message)
        // If the dispatch work item has not begun executing, cancel it now so
        // the body never runs. The state update below is the authoritative
        // completion signal if cancellation already lost the race.
        dispatchWorkItem?.cancel()
        var childrenToCancel: [Int] = []
        var stateToResume: RuntimeContinuationState?
        var shouldSignalCompletion = false
        var joinResumersToRun: [@Sendable (Int) -> Void] = []
        var terminalForJoin = 0
        var onCancellingHandlersToRun: [CompletionHandlerEntry] = []
        var allHandlersToRun: [CompletionHandlerEntry] = []
        lock.lock()
        switch state {
        case .completed, .cancelled, .failed:
            lock.unlock()
            return false
        case .cancelling:
            // Already cancelling, just update cause if not set
            if cancelCause == 0 {
                cancelCause = resolvedCause
            }
            if cancelMessage == "CancellationException" {
                cancelMessage = message
                usesDefaultCancellationMessage = usesDefaultMessage
            }
            lock.unlock()
            return false
        case .new, .active, .completing:
            cancelMessage = message
            usesDefaultCancellationMessage = usesDefaultMessage
            cancelCause = resolvedCause
            result = 0
            failure = 0
            // A job that has not started executing can become terminal
            // immediately. Once execution has begun, keep the intermediate
            // cancelling state so explicit completion mirrors lifecycle
            // semantics.
            if state == .new || (state == .active && !hasStartedExecuting) {
                state = .cancelled
                shouldSignalCompletion = true
                joinResumersToRun = joinResumers
                joinResumers = []
                terminalForJoin = terminalValueLocked()
                allHandlersToRun = completionHandlers
                completionHandlers = []
            } else {
                state = .cancelling
                stateToResume = continuationState
                // KUU-CORO-101: an `onCancelling` handler fires as soon as
                // cancellation begins, not when the job finally reaches a
                // terminal state (which may wait on `finally` blocks). The
                // remaining handlers stay registered for that later firing.
                onCancellingHandlersToRun = completionHandlers.filter { $0.onCancelling }
                completionHandlers.removeAll { $0.onCancelling }
            }
            childrenToCancel = childJobHandles
        }
        lock.unlock()

        stateToResume?.signalResume(isCancellation: true)
        for child in childrenToCancel {
            runtimeCancelChild(child)
        }
        for entry in onCancellingHandlersToRun {
            entry.handler(resolvedCause)
        }
        if shouldSignalCompletion {
            completionSemaphore.signal()
            for resumer in joinResumersToRun {
                resumer(terminalForJoin)
            }
            for entry in allHandlersToRun {
                entry.handler(terminalForJoin)
            }
        }
        return true
    }

    /// Blocking wait for job completion. Suspend-aware joining (which avoids blocking
    /// a GCD thread) is handled by `kk_job_join` via `addJoinResumer` (CORO-004); this
    /// method is the synchronous fallback for non-suspend contexts.
    func join() -> Int {
        // STDLIB-CORO-001: Start a LAZY job on demand before joining.
        startIfNeeded()
        // BUG-041: this (or a sibling launched on the same thread) may still be
        // sitting undispatched in RuntimePendingLaunchQueue -- flush before any
        // chance of blocking below, or a job that was never handed to GCD would
        // never signal completionSemaphore.
        RuntimePendingLaunchQueue.flush()
        lock.lock()
        if state.isCompleted {
            let value = terminalValueLocked()
            lock.unlock()
            return value
        }
        lock.unlock()
        if let loop = RuntimeEventLoop.current {
            // The caller is draining a runBlocking event loop, and this job's
            // body very likely sits in that same queue (`coroutineScope`'s wait
            // for its children reaches here). Parking the loop thread would
            // therefore deadlock: drain the queue until the job completes.
            addJoinResumer { _ in loop.wake() }
            loop.run(until: { self.completedSnapshot() })
        } else {
            completionSemaphore.wait()
            completionSemaphore.signal()
        }
        lock.lock()
        let value = terminalValueLocked()
        lock.unlock()
        return value
    }

    func awaitCompletion() -> Int {
        join()
    }

    func cancellationMessageSnapshot(forSuspensionPoint: Bool = false) -> String {
        lock.lock()
        let message = cancelMessage
        let cancellationCause = cancelCause
        let isCancelling = state == .cancelling
        let usesDefaultMessage = usesDefaultCancellationMessage
        lock.unlock()

        guard forSuspensionPoint, isCancelling, usesDefaultMessage,
              let debugName, kk_is_cancellation_exception(cancellationCause) == 0
        else {
            return message
        }
        return "\(debugName) is cancelling"
    }

    func cancellationCauseSnapshot() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return cancelCause
    }

    /// Thread-safe snapshot of the cancellation flag.
    func cancellationSnapshot() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return state.isCancelled
    }

    /// Thread-safe snapshot of the completion flag.
    func completedSnapshot() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return state.isCompleted
    }

    /// Thread-safe snapshot of the active state.
    func isActiveSnapshot() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return state.isActive
    }

    func isFailedSnapshot() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return state == .failed
    }
}

/// Concrete object behind an opaque job/task handle pointer: a launched
/// `RuntimeJobHandle` or an async `RuntimeAsyncTask`. Resolving once per call
/// keeps join/cancel/status ABI entry points from re-running the `as?` chain
/// for every operation they perform on the same handle.
enum RuntimeJobOrTask {
    case job(RuntimeJobHandle)
    case task(RuntimeAsyncTask)
    case other

    init(_ object: AnyObject) {
        if let wrapper = object as? RuntimeObjectBox {
            if let job = runtimeJobHandle(from: wrapper.coroutineJobHandle) {
                self = .job(job)
            } else if let job = runtimeBindJobSupportWrapperIfNeeded(wrapper) {
                self = .job(job)
            } else {
                self = .other
            }
        } else if let job = object as? RuntimeJobHandle {
            self = .job(job)
        } else if let task = object as? RuntimeAsyncTask {
            self = .task(task)
        } else {
            self = .other
        }
    }
}

/// KUU-1386: a JobSupport-subclass object that was never explicitly bound to
/// a runtime job lazily acquires one on first member contact, so calls like
/// `myJob.isActive`/`myJob.start()` behave like real JobSupport state instead
/// of silently no-op'ing (kotlinx gives every JobSupport a real state machine).
/// The `NonCancellable` singleton object is the exception: it is grafted onto
/// `runtimeNonCancellableJob`, so its member calls resolve to the singleton —
/// binding a fresh job to it would let `NonCancellable.cancel()` corrupt
/// shared state (kk_job_cancel already no-ops on the singleton).
private func runtimeBindJobSupportWrapperIfNeeded(_ wrapper: RuntimeObjectBox) -> RuntimeJobHandle? {
    if wrapper.coroutineJobHandle != 0 {
        return resolveLiveRuntimeHandle(wrapper.coroutineJobHandle, as: RuntimeJobHandle.self)
    }
    let wrapperRaw = Int(bitPattern: Unmanaged.passUnretained(wrapper).toOpaque())
    let nonCancellableID = runtimeStableNominalTypeID(fqName: "kotlinx.coroutines.NonCancellable")
    guard let sourceID = runtimeObjectTypeID(rawValue: wrapperRaw) else { return nil }
    if sourceID == nonCancellableID {
        return runtimeNonCancellableJob
    }
    guard runtimeIsAssignable(
        sourceTypeID: sourceID,
        targetTypeID: runtimeStableNominalTypeID(fqName: "kotlinx.coroutines.JobSupport")
    ) else { return nil }
    let job = runtimeStorage.withGCLock { _ -> RuntimeJobHandle? in
        if wrapper.coroutineJobHandle != 0 {
            return resolveLiveRuntimeHandle(wrapper.coroutineJobHandle, as: RuntimeJobHandle.self)
        }
        let job = RuntimeJobHandle()
        job.markStarted()
        job.markBodyless()
        let jobPtr = UnsafeMutableRawPointer(Unmanaged.passRetained(job).toOpaque())
        wrapper.coroutineJobHandle = Int(bitPattern: jobPtr)
        job.bindSourceWrapper(wrapper)
        job.nominalJobTypeID = sourceID
        return job
    }
    return job
}

/// CORO-003: Per-thread task key used to index into the task-scope map.
///
/// Each thread participating in a suspend-entry loop gets a unique sentinel
/// object stored in a pthread thread-local.  This is *not* the scope itself --
/// it is only a key that lets `RuntimeCoroutineScope.current` find which scope
/// is active on this thread.  The actual scope lives in the continuation
/// context and is propagated to child coroutines explicitly.
///
/// Migrated from `Thread.current.threadDictionary` to `pthread_key_t` for
/// lighter-weight access (single pointer lookup vs dictionary hash).
enum RuntimeCoroutineScopeTaskKey {
    private static let pthreadKey: pthread_key_t = makePthreadKey()

    /// Get-or-create a task key for the current thread.
    static var currentTaskKey: RuntimeTaskKey {
        if let existing: RuntimeTaskKeyBox = pthreadGetValue(pthreadKey) {
            return existing.key
        }
        let box = RuntimeTaskKeyBox(key: .makeUnique())
        pthreadSetValue(pthreadKey, box)
        return box.key
    }

    /// Reinstall a previously observed task key on this thread.
    ///
    /// Needed by `CoroutineStart.UNDISPATCHED`, which runs a child's body
    /// inline on the caller's thread: the child's suspend-entry loop installs
    /// its own fresh key and removes it on the way out, which would otherwise
    /// leave the *caller's* remaining statements with no key -- and therefore
    /// no ambient scope for any further `launch`/`async`.
    static func installKey(_ key: RuntimeTaskKey) {
        pthreadSetValue(pthreadKey, RuntimeTaskKeyBox(key: key))
    }

    /// Install a fresh task key for this thread and return it.
    /// Called at the top of each suspend-entry loop invocation.
    static func installFreshKey() -> RuntimeTaskKey {
        let box = RuntimeTaskKeyBox(key: .makeUnique())
        pthreadSetValue(pthreadKey, box)
        return box.key
    }

    /// The task key currently installed on this thread, or nil. Unlike
    /// `currentTaskKey`, this never mints a key — it reports what a nested
    /// suspend-entry loop found installed when it started, so the loop can
    /// hand the same key back on exit (KUU-964: a `coroutineScope`/`supervisorScope`
    /// block runs on its own entry loop; without restoring the caller's key,
    /// `RuntimeContinuationState.current`/`RuntimeCoroutineScope.current` stop
    /// resolving for the rest of the caller's burst, and `coroutineContext.job`
    /// throws in the enclosing scope).
    static var installedKey: RuntimeTaskKey? {
        let box: RuntimeTaskKeyBox? = pthreadGetValue(pthreadKey)
        return box?.key
    }

    /// Remove the task key for this thread.
    static func removeKey() {
        pthreadSetValue(pthreadKey, nil as RuntimeTaskKeyBox?)
    }

    /// Restore `key` — captured via `installedKey` before a nested suspend-entry
    /// loop minted its own — or remove the key entirely when there was none.
    static func restoreKey(_ key: RuntimeTaskKey?) {
        if let key {
            pthreadSetValue(pthreadKey, RuntimeTaskKeyBox(key: key))
        } else {
            removeKey()
        }
    }
}
