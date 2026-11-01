import Dispatch
import Foundation

private final class RuntimeResumeContinuationBox: @unchecked Sendable {
    /// The optional thrown slot mirrors a Kotlin call's outThrown channel: when
    /// the resume continuation is invoked synchronously on the resumer's own
    /// stack (the `resumesInline` path), an exception escaping the resumed
    /// burst — e.g. a completion continuation whose `resumeWith` rethrows —
    /// must reach the resumer's caller exactly like a JVM `resume` call frame.
    /// Dispatched/queued invocations pass nil and keep the legacy
    /// processUnhandledException fallback.
    let closure: @Sendable (UnsafeMutablePointer<Int>?) -> Void

    init(_ closure: @escaping @Sendable (UnsafeMutablePointer<Int>?) -> Void) {
        self.closure = closure
    }

    func invoke(_ outThrown: UnsafeMutablePointer<Int>?) {
        closure(outThrown)
    }
}


/// Used by lazy sequence/iterator builders during the CORO-004 migration.
/// Supports non-blocking resume via a continuation closure (for suspend-point
/// wiring) with a `DispatchSemaphore` fallback for legacy synchronous callers.
final class RuntimeCoroutineSyncGate: @unchecked Sendable {
    private let lock = NSLock()
    private var resumeContinuation: RuntimeResumeContinuationBox?
    private var fallbackSemaphore: DispatchSemaphore?
    private var signalPending = false

    func signal() {
        lock.lock()
        if let cont = resumeContinuation {
            resumeContinuation = nil
            lock.unlock()
            DispatchQueue.global(qos: .userInitiated).async {
                cont.invoke(nil)
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
            resumeContinuation = RuntimeResumeContinuationBox { _ in continuation() }
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

private final class RuntimeCoroutineArgumentsSnapshot {
    let values: [Int64: Int64]
    let gcRootStorage = RuntimeCoroutineRootStorage()

    init(values: [Int64: Int64]) {
        self.values = values
    }
}

final class RuntimeContinuationState: @unchecked Sendable {
    var functionID: Int64
    var label: Int64
    private let gcValuesLock = NSLock()
    private let gcRootStorage = RuntimeCoroutineRootStorage()
    private var storedCompletion: Int64
    private var storedThrownException: Int = 0
    private var storedSpillSlots: [Int64: Int64]
    private var storedLauncherArgs: [Int64: Int64]

    var completion: Int64 {
        get {
            gcValuesLock.lock()
            defer { gcValuesLock.unlock() }
            return storedCompletion
        }
        set {
            gcValuesLock.lock()
            runtimeStorage.withGCLock { state in
                storedCompletion = newValue
                recordGCValuesLocked(state: &state)
            }
            gcValuesLock.unlock()
        }
    }
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
    var thrownException: Int {
        get {
            gcValuesLock.lock()
            defer { gcValuesLock.unlock() }
            return storedThrownException
        }
        set {
            gcValuesLock.lock()
            runtimeStorage.withGCLock { state in
                storedThrownException = newValue
                recordGCValuesLocked(state: &state)
            }
            gcValuesLock.unlock()
        }
    }
    /// The `runBlocking` event loop this coroutine is bound to, if any.
    ///
    /// Adopted from `RuntimeEventLoop.current` the first time the suspend-entry
    /// loop runs this continuation, and consulted by every resumption hop
    /// (`signalResume`, `installResumeContinuation`) so a resumption is queued
    /// on the loop -- in FIFO order -- instead of racing on the concurrent
    /// global pool. `nil` keeps the original global-pool behaviour, which is
    /// what dispatcher-bound bodies and direct runtime (test) calls get.
    var eventLoop: RuntimeEventLoop?
    /// Set only by the canonical context-aware runBlocking boundary and its
    /// structured descendants. nil preserves legacy invocation scheduling.
    var blockingScheduler: RuntimeBlockingScheduler?
    /// KUU-2687: dispatcher resolved from this coroutine's own context, used
    /// when neither a blocking scheduler nor an event loop owns its resumptions.
    /// A standalone `launch(dispatcher)`/`withContext(dispatcher)` continuation
    /// hops back through it (and through a limited view's permit gate) on every
    /// resume, matching kotlinx's intercepted-continuation dispatch.
    var resumeDispatcher: RuntimeDispatcher?
    // Public builders leave scheduling to the intercepted continuation itself.
    var resumesInline = false
    var builderContext: RuntimeCoroutineContext?
    private var uninterceptedEntryPointRaw: Int = 0
    private var uninterceptedCompletionContinuation: Int = 0
    /// Continuation whose context this state delegates to. Direct suspend calls
    /// use their caller as the completion continuation, while unintercepted
    /// coroutine builders set the same source explicitly.
    private var contextContinuationRaw: Int = 0
    /// KUU-2750: the suspend-entry point currently driving this continuation's
    /// state machine, recorded by runSuspendEntryLoopWithContinuation and
    /// startCoroutineUninterceptedOrReturn. The DeepRecursive trampoline needs
    /// it to resume a continuation parked at callRecursive when the parked
    /// frame is a nested suspend call rather than the coroutine root.
    var suspendDriveEntryPointRaw: Int = 0
    /// KUU-2750: the continuation this state reports completion to — the caller
    /// for direct suspend calls, the completion continuation for unintercepted
    /// coroutine values. Lets the DeepRecursive trampoline keep unwinding the
    /// frame chain after a nested callRecursive frame finishes.
    var suspendCallerContinuationRaw: Int {
        interceptionLock.lock()
        defer { interceptionLock.unlock() }
        return contextContinuationRaw
    }
    private var hasStartedUninterceptedCoroutine = false
    /// KUU-2689: kotlinx's MODE_CANCELLABLE start flag. Set only when the
    /// intercepted continuation is a native dispatch wrapper (upstream's
    /// `is DispatchedContinuation` gate) so the Job check at the first-resume
    /// boundary decides whether the block ever runs.
    private var cancellableCoroutineStart = false
    // Cancellation must wake the innermost call and let it unwind before its caller.
    private var suspendedCallChild: RuntimeContinuationState?
    private let interceptionLock = NSRecursiveLock()
    private var generatedContextRaw: Int?
    /// The exact continuation context inherited by a directly-called suspend
    /// function. This is kept separate from `generatedContextRaw`, which is
    /// owned by this state's completion continuation.
    private var inheritedContextRaw: Int?
    private var interceptedContinuationRaw: Int?
    private var continuationInterceptorRaw: Int = 0
    private var interceptionReleased = false
    /// KUU-3719: when this state was created for an interception-transparent
    /// call (a callee whose suspending calls are all in tail position — it
    /// owns no `ContinuationImpl` of its own on JVM), the nearest caller
    /// state whose interception this frame shares. `suspendCoroutine`'s
    /// `continuation.intercepted()` then reuses the ancestor's interception
    /// product instead of invoking the user's `ContinuationInterceptor` a
    /// second time for the same logical coroutine.
    private weak var interceptionAnchorState: RuntimeContinuationState?
    /// The interception product was derived from an ancestor's interception
    /// rather than produced by `interceptContinuation` on this state, so
    /// `releaseInterception` must not forward it to the interceptor's
    /// `releaseInterceptedContinuation`.
    private var interceptionDerived = false
    private let stateLock = NSLock()
    /// STDLIB-CORO-BUG-01: one-shot resume guard.
    /// Set to `true` atomically (under `stateLock`) by the first successful resume
    /// so that any subsequent resume call is rejected with an `IllegalStateException`.
    /// Reset by `resetResumeState()` when the coroutine advances to the next suspend point.
    private var hasResumed: Bool = false
    /// KUU-3833: `suspendCoroutineUninterceptedOrReturn` hands the coroutine's own
    /// continuation to its block. A resume delivered through it while the block is
    /// in flight is recorded here so `kk_coroutine_call_direct_suspend` keeps
    /// reporting the suspend call as suspended: on JVM the delivered result rides
    /// the completion channel (each caller's resumeWith), not the call's return
    /// value.
    private var orReturnBlockDepth = 0
    private var orReturnResumeDelivered = false
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
    /// KUU-2724: a suspend-point callee already completed exceptionally before
    /// the caller's state machine reached the suspend return -- e.g. a direct
    /// suspend call whose child finished thrown inside
    /// `kk_coroutine_call_direct_suspend`, or an await on an already-failed
    /// task. The suspend-entry loop consumes this marker and re-enters the
    /// machine inline so the failure lands on the catch label inside the same
    /// burst; an enqueued resume would let already-queued siblings observe and
    /// drain state the failure was meant to discard. `signalResume()` still
    /// runs alongside it, so drivers without the inline check keep the
    /// enqueued resume.
    private var inlineExceptionalDeliveryPending = false
    private var cancellationShieldDepth = 0
    private var didExit = false

    // CORO-003: Task-local continuation state registry (replaces TLS).
    // Maps an opaque task token (assigned by the suspend-entry loop on entry) to
    // the continuation state that is current for that execution context. This allows
    // `RuntimeContinuationState.current` to work from code that runs inside a
    // suspend-entry loop without an explicit continuation handle.

    /// Called at the top of the suspend-entry loop so that suspend function calls
    /// can discover the current state.
    static func installState(_ state: RuntimeContinuationState?, forTask key: RuntimeTaskKey) {
        taskStateLock.lock()
        if let state {
            taskStateMap[key] = state
        } else {
            taskStateMap.removeValue(forKey: key)
        }
        taskStateLock.unlock()
    }

    static func removeState(forTask key: RuntimeTaskKey) {
        taskStateLock.lock()
        taskStateMap.removeValue(forKey: key)
        taskStateLock.unlock()
    }

    static func stateForTask(_ key: RuntimeTaskKey) -> RuntimeContinuationState? {
        taskStateLock.lock()
        defer { taskStateLock.unlock() }
        return taskStateMap[key]
    }

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
        self.storedCompletion = completion
        self.storedSpillSlots = spillSlots
        self.storedLauncherArgs = launcherArgs
        self.delayTimers = delayTimers
        RuntimeLiveHandles.register(self)
        if completion != 0 || !spillSlots.isEmpty || !launcherArgs.isEmpty {
            runtimeStorage.withGCLock { state in recordGCValuesLocked(state: &state) }
        }
    }

    // gcValuesLock and gcLock are held, except during initialization before publication.
    private func recordGCValuesLocked(state: inout GCState) {
        let values = [Int(storedCompletion), storedThrownException]
            + storedSpillSlots.values.map(Int.init)
            + storedLauncherArgs.values.map(Int.init)
        runtimeRecordCoroutineHeapRootsLocked(values, storage: gcRootStorage, state: &state)
    }

    func setSpillSlot(_ index: Int64, value: Int64) {
        gcValuesLock.lock()
        runtimeStorage.withGCLock { state in
            storedSpillSlots[index] = value
            recordGCValuesLocked(state: &state)
        }
        gcValuesLock.unlock()
    }

    func clearSpillSlots() {
        gcValuesLock.lock()
        runtimeStorage.withGCLock { state in
            storedSpillSlots.removeAll(keepingCapacity: false)
            recordGCValuesLocked(state: &state)
        }
        gcValuesLock.unlock()
    }

    func setLauncherArg(_ index: Int64, value: Int64, onlyIfAbsent: Bool = false) {
        gcValuesLock.lock()
        if !onlyIfAbsent || storedLauncherArgs[index] == nil {
            runtimeStorage.withGCLock { state in
                storedLauncherArgs[index] = value
                recordGCValuesLocked(state: &state)
            }
        }
        gcValuesLock.unlock()
    }

    func replaceLauncherArgs(_ values: [Int64: Int64]) {
        gcValuesLock.lock()
        runtimeStorage.withGCLock { state in
            storedLauncherArgs = values
            recordGCValuesLocked(state: &state)
        }
        gcValuesLock.unlock()
    }

    func withRetainedLauncherArgs<Result>(
        _ body: ([Int64: Int64]) throws -> Result
    ) rethrows -> Result {
        gcValuesLock.lock()
        let snapshot = RuntimeCoroutineArgumentsSnapshot(values: storedLauncherArgs)
        runtimeStorage.withGCLock { state in
            runtimeRecordCoroutineHeapRootsLocked(
                snapshot.values.values.map(Int.init),
                storage: snapshot.gcRootStorage,
                state: &state
            )
        }
        gcValuesLock.unlock()
        return try withExtendedLifetime(snapshot) {
            try body(snapshot.values)
        }
    }

    func rootedCompletion() -> Int {
        let threadID = runtimeGCCurrentThreadID()
        gcValuesLock.lock()
        defer { gcValuesLock.unlock() }
        return runtimeStorage.withGCLock { state in
            let value = Int(storedCompletion)
            runtimeRecordShadowHandoffLocked(value, threadID: threadID, state: &state)
            return value
        }
    }

    func rootedSpillSlot(_ slot: Int64) -> Int {
        let threadID = runtimeGCCurrentThreadID()
        gcValuesLock.lock()
        defer { gcValuesLock.unlock() }
        return runtimeStorage.withGCLock { state in
            let value = Int(storedSpillSlots[slot] ?? 0)
            runtimeRecordShadowHandoffLocked(value, threadID: threadID, state: &state)
            return value
        }
    }

    func rootedLauncherArg(_ index: Int64) -> Int64 {
        let threadID = runtimeGCCurrentThreadID()
        gcValuesLock.lock()
        defer { gcValuesLock.unlock() }
        return runtimeStorage.withGCLock { state in
            let value = storedLauncherArgs[index] ?? 0
            runtimeRecordShadowHandoffLocked(Int(value), threadID: threadID, state: &state)
            return value
        }
    }

    func configureUninterceptedCoroutine(entryPointRaw: Int, completionContinuation: Int) {
        stateLock.lock()
        self.resumesInline = true
        self.uninterceptedEntryPointRaw = entryPointRaw
        self.uninterceptedCompletionContinuation = completionContinuation
        self.hasStartedUninterceptedCoroutine = false
        stateLock.unlock()

        interceptionLock.lock()
        contextContinuationRaw = completionContinuation
        generatedContextRaw = nil
        interceptionLock.unlock()
    }

    func inheritContinuationContext(from completionContinuation: Int) {
        interceptionLock.lock()
        contextContinuationRaw = completionContinuation
        generatedContextRaw = nil
        interceptionLock.unlock()
    }

    func markCancellableCoroutineStart() {
        stateLock.lock()
        cancellableCoroutineStart = true
        stateLock.unlock()
    }

    func takeUninterceptedCoroutineStart() -> (entryPointRaw: Int, completionContinuation: Int, cancellableStart: Bool)? {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard uninterceptedEntryPointRaw != 0, !hasStartedUninterceptedCoroutine else {
            return nil
        }
        hasStartedUninterceptedCoroutine = true
        return (
            entryPointRaw: uninterceptedEntryPointRaw,
            completionContinuation: uninterceptedCompletionContinuation,
            cancellableStart: cancellableCoroutineStart
        )
    }

    /// KUU-2689: the CancellationException a MODE_CANCELLABLE coroutine start
    /// delivers to its completion instead of running the block, or nil when
    /// the coroutine context's Job is absent or still active. This mirrors
    /// `DispatchedContinuation.resumeCancelled` / `DispatchedTask.run`'s
    /// `!job.isActive` check, evaluated at the first-resume boundary.
    func unstartedCoroutineCancellationException() -> Int? {
        guard let contextRaw = generatedCoroutineContext(outThrown: nil), contextRaw != 0 else {
            return nil
        }
        let jobRaw = kk_context_get_job(contextRaw)
        guard jobRaw != 0,
              let job = runtimeJobHandle(from: jobRaw) ?? runtimeAsyncTask(from: jobRaw)?.completionJob,
              !job.isActiveSnapshot()
        else {
            return nil
        }
        return kk_job_get_cancellation_exception(jobRaw)
    }

    func generatedCoroutineContext(outThrown: UnsafeMutablePointer<Int>?) -> Int? {
        interceptionLock.lock()
        defer { interceptionLock.unlock() }
        guard contextContinuationRaw != 0 else {
            return nil
        }
        if let generatedContextRaw {
            return generatedContextRaw
        }
        var thrown = 0
        let context = __kk_coroutine_continuation_context(contextContinuationRaw, &thrown)
        outThrown?.pointee = thrown
        if thrown == 0 {
            generatedContextRaw = context
        }
        return context
    }

    /// Return the original context object when no runtime elements have been
    /// added to this continuation. Kotlin's `coroutineContext` property returns
    /// the continuation's context object itself, so reconstructing an equal
    /// runtime context would break identity checks against EmptyCoroutineContext
    /// and user-provided context elements.
    func unmodifiedCoroutineContextRaw() -> Int? {
        guard scope == nil, jobHandle == nil, builderContext == nil, eventLoop == nil else {
            return nil
        }
        interceptionLock.lock()
        defer { interceptionLock.unlock() }
        return generatedContextRaw ?? inheritedContextRaw
    }

    func inheritCoroutineContext(from caller: RuntimeContinuationState) {
        guard let contextRaw = caller.unmodifiedCoroutineContextRaw() else { return }
        interceptionLock.lock()
        inheritedContextRaw = contextRaw
        interceptionLock.unlock()
    }

    func generatedCoroutineContextIfMatching(_ context: RuntimeCoroutineContext) -> Int? {
        guard let sourceContextRaw = generatedCoroutineContext(outThrown: nil),
              runtimeCoroutineContextsHaveSameContent(
                  resolveToCoroutineContext(sourceContextRaw), context
              )
        else {
            return nil
        }
        return sourceContextRaw
    }

    /// KUU-3719: mark this state as sharing the interception recorded on
    /// `anchor` (the caller continuation of an interception-transparent
    /// adapter call).
    func bindInterceptionAnchor(_ anchor: RuntimeContinuationState) {
        interceptionLock.lock()
        interceptionAnchorState = anchor
        interceptionLock.unlock()
    }

    /// The interception product cached on this state plus the interceptor
    /// that produced it. `intercepted` is 0 when this state was never
    /// intercepted; `released` reports a released interception, which behaves
    /// like a pass-through (the state resolves to itself).
    private func cachedInterception() -> (intercepted: Int, interceptor: Int, released: Bool) {
        interceptionLock.lock()
        defer { interceptionLock.unlock() }
        return (interceptedContinuationRaw ?? 0, continuationInterceptorRaw, interceptionReleased)
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
        // KUU-3719: this frame belongs to an interception-transparent call —
        // the callee owns no ContinuationImpl of its own on JVM, so its
        // suspendCoroutine's `intercepted()` resolves on the nearest ancestor
        // frame that does own a machine. Resolve the anchor's interception
        // recursively (an unintercepted anchor runs `interceptContinuation`
        // now — the same single interception JVM performs on the owning
        // machine), then derive this frame's product from it: a pass-through
        // or custom product resolves this frame to itself, and a dispatcher
        // interceptor yields an equivalent native dispatch wrapper on this
        // frame so `resume` still hops through the dispatcher.
        if let anchor = interceptionAnchorState {
            let (anchorIntercepted, anchorInterceptor, anchorReleased) = anchor.cachedInterception()
            if anchorReleased {
                interceptionDerived = true
                interceptedContinuationRaw = continuationRaw
                return continuationRaw
            }
            let anchorRaw = Int(bitPattern: Unmanaged.passUnretained(anchor).toOpaque())
            var product = anchorIntercepted
            var interceptor = anchorInterceptor
            if product == 0 {
                var thrown = 0
                product = anchor.intercepted(
                    continuationRaw: anchorRaw,
                    interceptorKey: interceptorKey,
                    outThrown: &thrown
                )
                if thrown != 0 {
                    outThrown?.pointee = thrown
                    return continuationRaw
                }
                interceptor = anchor.cachedInterception().interceptor
            }
            interceptionDerived = true
            // Propagate the interceptor identity so deeper transparent frames
            // can still recognise a dispatcher product and wrap themselves.
            continuationInterceptorRaw = interceptor
            if product == anchorRaw {
                interceptedContinuationRaw = continuationRaw
                return continuationRaw
            }
            if let dispatcher = runtimeInterceptorDispatcher(interceptor) {
                let contextPointer = UnsafeMutableRawPointer(
                    bitPattern: __kk_coroutine_continuation_context(continuationRaw)
                )
                let wrapped = KKInterceptedContinuation(
                    context: contextPointer,
                    continuation: RuntimeGeneratedContinuation(state: self, raw: continuationRaw),
                    dispatcher: dispatcher
                )
                let wrappedRaw = runtimeRegisterObject(wrapped)
                interceptedContinuationRaw = wrappedRaw
                return wrappedRaw
            }
            // A custom (source-level) interceptor product cannot be
            // retargeted at this frame. On JVM this frame's suspend points
            // bind the anchor machine, so `intercepted()` would return the
            // anchor's product; KSwiftK keeps a distinct child machine, so
            // invoke `interceptContinuation` on this frame's own continuation
            // — the equivalent per-machine interception — letting a
            // `ContinuationDispatcher` dispatch every resume hop (KUU-3783).
            interceptionDerived = false
            var frameThrown = 0
            let frameProduct = runtimeInterceptGeneratedContinuation(
                interceptor: interceptor,
                continuation: continuationRaw,
                outThrown: &frameThrown
            )
            outThrown?.pointee = frameThrown
            guard frameThrown == 0 else {
                return continuationRaw
            }
            interceptedContinuationRaw = frameProduct
            return frameProduct
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
        let derived = interceptionDerived
        interceptionLock.unlock()
        if derived {
            // The product was never handed to the interceptor, so it must not
            // go through `releaseInterceptedContinuation`; only drop the
            // runtime registration for a native dispatch wrapper.
            if intercepted != continuationRaw {
                runtimeReleaseObject(intercepted)
            }
            return
        }
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

    /// The installed closure takes an optional thrown slot, forwarded to it
    /// Convenience for resume continuations that ignore the resumer's thrown
    /// slot (dispatcher queues and pending signals always invoke with nil).
    func installResumeContinuation(
        _ continuation: @escaping @Sendable () -> Void
    ) {
        installResumeContinuation { _ in continuation() }
    }

    /// only when it is invoked synchronously on a resumer's stack (see
    /// `signalResume`). A pending signal consumed here means the resumer's
    /// `resume` call already returned, so every eager path passes nil —
    /// exceptions inside the continuation keep the processUnhandledException
    /// fallback instead of escaping into the suspending caller.
    func installResumeContinuation(
        _ continuation: @escaping @Sendable (UnsafeMutablePointer<Int>?) -> Void
    ) {
        let boxedContinuation = RuntimeResumeContinuationBox(continuation)
        stateLock.lock()
        if resumeSignalPending {
            resumeSignalPending = false
            let loop = eventLoop
            let scheduler = blockingScheduler
            let dispatcher = resumeDispatcher
            let inlineResume = resumesInline
            stateLock.unlock()
            if let scheduler {
                scheduler.enqueueResume { boxedContinuation.invoke(nil) }
                return
            }
            if let dispatcher {
                dispatcher.dispatchAsync { boxedContinuation.invoke(nil) }
                return
            }
            if inlineResume {
                boxedContinuation.invoke(nil)
                return
            }
            // On a runBlocking event loop this lands at the TAIL of the queue,
            // and that is precisely what makes `yield()` FIFO: `yield()` resumes
            // its own continuation synchronously during the burst (marking a
            // pending signal, since nothing is installed yet), the suspension
            // handler flushes the coroutines this burst launched, and only then
            // installs -- so the yielding coroutine queues up behind them.
            if let loop {
                loop.enqueue { boxedContinuation.invoke(nil) }
            } else {
                DispatchQueue.global().async {
                    boxedContinuation.invoke(nil)
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
        inlineExceptionalDeliveryPending = false
        hasResumed = false
        return true
    }

    /// Mark that the pending resume signal carries an already-known failure
    /// (see `inlineExceptionalDeliveryPending`). Callers still invoke
    /// `signalResume()` so continuation drivers without the inline check fall
    /// back to an ordinary enqueued resume.
    func markInlineExceptionalDelivery() {
        stateLock.lock()
        inlineExceptionalDeliveryPending = true
        stateLock.unlock()
    }

    /// The suspend-entry loop consumes the inline marker and re-enters the
    /// state machine so the failure reaches the catch label inside the same
    /// burst (KUU-2724). Clears the pending signal/one-shot guard the same way
    /// `consumePendingExceptionalResume` does.
    func consumeInlineExceptionalDelivery() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard inlineExceptionalDeliveryPending else {
            return false
        }
        inlineExceptionalDeliveryPending = false
        resumeSignalPending = false
        hasResumed = false
        return true
    }

    /// Generated resume labels receive an exception once. A surrounding catch
    /// may handle it and then suspend again without a child call clearing it.
    func takeThrownException() -> Int {
        let threadID = runtimeGCCurrentThreadID()
        stateLock.lock()
        defer { stateLock.unlock() }
        gcValuesLock.lock()
        defer { gcValuesLock.unlock() }
        return runtimeStorage.withGCLock { state in
            let thrown = storedThrownException
            runtimeRecordShadowHandoffLocked(thrown, threadID: threadID, state: &state)
            storedThrownException = 0
            recordGCValuesLocked(state: &state)
            return thrown
        }
    }

    func installCancellableDelivery(_ continuation: RuntimeCancellableContinuation) -> Bool {
        stateLock.lock()
        guard !didExit else {
            stateLock.unlock()
            return false
        }
        cancellableDelivery = continuation
        stateLock.unlock()
        return true
    }

    var isExited: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return didExit
    }

    func markExited() {
        stateLock.lock()
        didExit = true
        stateLock.unlock()
    }

    func consumeCancellableDelivery() {
        stateLock.lock()
        let delivery = cancellableDelivery
        cancellableDelivery = nil
        stateLock.unlock()
        guard let delivery else { return }
        defer { withExtendedLifetime(delivery) {} }
        let result = delivery.takeResultForDelivery()
        let access = runtimeResultAccessFromRaw(result)
        defer { withExtendedLifetime(access) {} }
        let isSuccess = access?.box.isSuccess == true
        let deliveredValue = isSuccess ? access!.box.value : runtimeNullSentinelInt
        let deliveredException = isSuccess ? 0 : (access?.box.exception ?? runtimeNullSentinelInt)
        stateLock.lock()
        completion = Int64(deliveredValue)
        thrownException = deliveredException
        stateLock.unlock()
    }

    func retireCancellableDeliveryOnExit() {
        stateLock.lock()
        let delivery = cancellableDelivery
        cancellableDelivery = nil
        stateLock.unlock()
        delivery?.delegateDidExit()
    }

    func beginOrReturnBlock() {
        stateLock.lock()
        orReturnBlockDepth += 1
        stateLock.unlock()
    }

    func endOrReturnBlock() {
        stateLock.lock()
        if orReturnBlockDepth > 0 {
            orReturnBlockDepth -= 1
        }
        stateLock.unlock()
    }

    /// True after this coroutine's completion was delivered through
    /// `suspendCoroutineUninterceptedOrReturn`'s block-scoped continuation —
    /// the suspend call that drove it must report suspended, not the value.
    var wasOrReturnResumed: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return orReturnResumeDelivered
    }

    /// Propagates the OrReturn provenance to the caller when a suspend call
    /// reports suspended for it, so multi-level suspend chains keep reporting
    /// suspended all the way to the driver's completion delivery.
    func markOrReturnDelivery() {
        stateLock.lock()
        orReturnResumeDelivered = true
        stateLock.unlock()
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

    /// Cancellation from a replaced Job must not resume a shielded withContext
    /// caller, but ordinary block completion still can.
    ///
    /// `outThrown` is the resumer's own thrown slot. It is forwarded to the
    /// installed continuation only on the synchronous `resumesInline` path,
    /// where the whole resume-to-completion drive is one call stack — matching
    /// the JVM, where an exception escaping `resume` (such as a completion
    /// continuation rethrowing inside `resumeWith`) propagates to the resumer's
    /// caller. Queued/dispatched invocations cannot reach that frame, so they
    /// keep the processUnhandledException fallback.
    func signalResume(isCancellation: Bool = false, outThrown: UnsafeMutablePointer<Int>? = nil) {
        stateLock.lock()
        if isCancellation, cancellationShieldDepth > 0 {
            stateLock.unlock()
            return
        }
        if let child = suspendedCallChild {
            stateLock.unlock()
            child.signalResume(isCancellation: isCancellation, outThrown: outThrown)
            return
        }
        if let cont = resumeContinuation {
            resumeContinuation = nil
            let loop = eventLoop
            let inlineResume = resumesInline
            let scheduler = blockingScheduler
            let dispatcher = resumeDispatcher
            stateLock.unlock()
            if let scheduler {
                scheduler.enqueueResume { cont.invoke(nil) }
                return
            }
            if let dispatcher {
                dispatcher.dispatchAsync { cont.invoke(nil) }
                return
            }
            // Queue the resumption on the coroutine's event loop when it has
            // one, so resumptions keep the loop's FIFO order instead of being
            // ordered by whichever global-pool thread happens to pick them up.
            if inlineResume {
                cont.invoke(outThrown)
            } else if let loop {
                loop.enqueue { cont.invoke(nil) }
            } else {
                DispatchQueue.global().async {
                    cont.invoke(nil)
                }
            }
            return
        }
        if let sem = fallbackSemaphore {
            stateLock.unlock()
            sem.signal()
            return
        }
        resumeSignalPending = true
        stateLock.unlock()
    }

    /// Returns `nil` on success. If the continuation has already been resumed
    /// (one-shot guard), returns a raw pointer to a `RuntimeIllegalStateExceptionBox`
    /// describing the double-resume violation (STDLIB-CORO-BUG-01).
    /// The flag is set BEFORE delivering the result to prevent re-entrant resume.
    /// `outThrown` is the resumer's own thrown slot: when the resume drives the
    /// coroutine synchronously to completion, an exception escaping the
    /// completion continuation's `resumeWith` lands there so the resumer's
    /// call site rethrows it like a JVM `resume` frame (KUU-3783).
    @discardableResult
    func resume(with value: Int, outThrown: UnsafeMutablePointer<Int>? = nil) -> Int? {
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
        if orReturnBlockDepth > 0 {
            orReturnResumeDelivered = true
        }
        stateLock.unlock()
        signalResume(outThrown: outThrown)
        return nil
    }

    /// Returns `nil` on success. If the continuation has already been resumed
    /// (one-shot guard), returns a raw pointer to a `RuntimeIllegalStateExceptionBox`
    /// describing the double-resume violation (STDLIB-CORO-BUG-01).
    /// The flag is set BEFORE delivering the result to prevent re-entrant resume.
    @discardableResult
    func resume(withException exception: Int, outThrown: UnsafeMutablePointer<Int>? = nil) -> Int? {
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
        if orReturnBlockDepth > 0 {
            orReturnResumeDelivered = true
        }
        stateLock.unlock()
        signalResume(outThrown: outThrown)
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
        inlineExceptionalDeliveryPending = false
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

    /// Job cancellation already forwards through this chain. A driver's
    /// supplemental handler must not wake the same child a second time after
    /// it has caught cancellation and entered another suspension.
    func containsSuspendedContinuation(_ target: RuntimeContinuationState) -> Bool {
        if self === target { return true }
        stateLock.lock()
        let child = suspendedCallChild
        stateLock.unlock()
        return child?.containsSuspendedContinuation(target) ?? false
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

enum RuntimeTaskAwaitOutcome: Equatable {
    case completed(result: Int, thrownException: Int)
    /// Registered a completion resumer; the caller must return `kk_coroutine_suspended()`.
    case suspended
}

final class RuntimeCoroutineResultStorage: @unchecked Sendable {
    private let lock = NSLock()
    private let gcRootStorage = RuntimeCoroutineRootStorage()
    private var result = 0
    private var thrown = 0

    func store(result: Int, thrown: Int) {
        lock.lock()
        runtimeStorage.withGCLock { state in
            self.result = result
            self.thrown = thrown
            runtimeRecordCoroutineHeapRootsLocked(
                [result, thrown], storage: gcRootStorage, state: &state
            )
        }
        lock.unlock()
    }

    func load() -> (result: Int, thrown: Int) {
        let threadID = runtimeGCCurrentThreadID()
        lock.lock()
        defer { lock.unlock() }
        return runtimeStorage.withGCLock { state in
            runtimeRecordShadowHandoffLocked(result, threadID: threadID, state: &state)
            runtimeRecordShadowHandoffLocked(thrown, threadID: threadID, state: &state)
            return (result, thrown)
        }
    }
}

private final class RuntimeTaskAwaitSnapshot: @unchecked Sendable {
    private let lock = NSLock()
    private let gcRootStorage = RuntimeCoroutineRootStorage()
    private var result: Int = 0
    private var thrownException: Int = 0

    func store(result: Int, thrownException: Int) {
        lock.lock()
        runtimeStorage.withGCLock { state in
            self.result = result
            self.thrownException = thrownException
            runtimeRecordCoroutineHeapRootsLocked(
                [result, thrownException], storage: gcRootStorage, state: &state
            )
        }
        lock.unlock()
    }

    func load() -> RuntimeTaskAwaitOutcome {
        let threadID = runtimeGCCurrentThreadID()
        lock.lock()
        let value = result
        let thrown = thrownException
        runtimeStorage.withGCLock { state in
            runtimeRecordShadowHandoffLocked(value, threadID: threadID, state: &state)
            runtimeRecordShadowHandoffLocked(thrown, threadID: threadID, state: &state)
        }
        lock.unlock()
        return .completed(result: value, thrownException: thrown)
    }
}

final class RuntimeAsyncTask: @unchecked Sendable {
    let completionJob = RuntimeJobHandle()
    private let atomicStart: Bool
    private let lock = NSLock()
    private let gcRootStorage = RuntimeCoroutineRootStorage()
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

    func isCompletedSnapshot() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return isCompleted
    }

    func isCancelledSnapshot() -> Bool {
        lock.lock()
        let taskIsCancelled = isCancelled
        lock.unlock()
        // A scope may cancel the task's completion job before the task itself
        // receives its final exceptional completion.
        return taskIsCancelled || completionJob.cancellationSnapshot()
    }

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

    func isFailedSnapshot() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return isCompleted && thrownException != 0
    }

    func completionSnapshot(handoff: RuntimeCompletionHandoff = .all) -> (completed: Bool, value: Int, exception: Int) {
        let threadID = runtimeGCCurrentThreadID()
        lock.lock()
        defer { lock.unlock() }
        runtimeStorage.withGCLock { state in
            runtimeRecordCompletionHandoffLocked(
                handoff, completed: isCompleted, value: result, exception: thrownException, threadID: threadID, state: &state
            )
        }
        return (isCompleted, result, thrownException)
    }

    // The task lock is held. GC scans the independent mirror without taking it.
    private func setTerminalValuesLocked(result: Int, thrownException: Int) {
        runtimeStorage.withGCLock { state in
            self.result = result
            self.thrownException = thrownException
            runtimeRecordCoroutineHeapRootsLocked(
                [result, thrownException], storage: gcRootStorage, state: &state
            )
        }
    }

    func complete(with result: Int) {
        finish(result: result, exception: 0)
    }

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
        let resolvedResult = isCancelled ? 0 : result
        let cancellationCause = thrownException
        let cancellationPin = isCancelled && cancellationCause != 0 && cancellationCause != runtimeNullSentinelInt
            ? RuntimeForeignCallbackPin(root: cancellationCause) : nil
        let resolvedException = !isCancelled || (failure != 0 && kk_is_cancellation_exception(failure) == 0)
            ? failure : thrownException
        setTerminalValuesLocked(result: resolvedResult, thrownException: resolvedException)
        isCompleted = true
        let snapshotResult = self.result
        let snapshotThrown = thrownException
        let snapshotCancelled = isCancelled
        let resumers = completionResumers
        completionResumers = []
        lazyStartBody = nil
        lock.unlock()
        if snapshotCancelled {
            // Cancellation may still be publishing the job state on another thread.
            _ = completionJob.cancel(cause: cancellationCause)
        }
        withExtendedLifetime(cancellationPin) {}
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
        let resolvedCause = cause != 0 && cause != runtimeNullSentinelInt
            ? cause
            : runtimeAllocateCancellationException(message: completionJob.defaultCancellationMessage)
        setTerminalValuesLocked(result: result, thrownException: resolvedCause)
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
            let threadID = runtimeGCCurrentThreadID()
            runtimeStorage.withGCLock { state in
                runtimeRecordShadowHandoffLocked(value, threadID: threadID, state: &state)
                runtimeRecordShadowHandoffLocked(thrown, threadID: threadID, state: &state)
            }
            lock.unlock()
            if thrown != 0, let callerState {
                // Already completed exceptionally: resume the caller's continuation
                // with the exception and report suspension so the state machine
                // throws after it returns. Marked inline (KUU-2724): the failure
                // is already known, so the burst loop delivers it to the catch
                // label without an event-loop turn.
                callerState.markInlineExceptionalDelivery()
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
            runtimeWaitDrainingEventLoop(gate)
        }
        return snapshot.load()
    }

    func awaitResult() -> Int {
        switch awaitResult(callerState: nil) {
        case .completed(let result, let thrown):
            return thrown != 0 ? thrown : result
        case .suspended:
            fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: blocking awaitResult cannot suspend")
        }
    }

}
