import Dispatch
import Foundation

/// Stable nominal type ID of `kotlinx.coroutines.CoroutineScope`, used to tag
/// `RuntimeCoroutineScope` objects so runtime `is`/`as` checks against the
/// interface succeed on raw scope handles (KUU-1416).
private let runtimeCoroutineScopeInterfaceTypeID = runtimeStableNominalTypeID(
    fqName: "kotlinx.coroutines.CoroutineScope"
)

/// A coroutine scope that tracks child jobs and supports structured cancellation.
///
/// CORO-003: Scope is no longer stored in Thread Local Storage. Instead it is
/// carried inside `RuntimeContinuationState.scope` (the coroutine context),
/// so it survives suspend/resume across different GCD threads. A lightweight
/// per-task accessor (`RuntimeCoroutineScope.current`)
/// bridges the gap for the few call-sites that don't have a continuation handle.
final class RuntimeCoroutineScope: @unchecked Sendable {
    private let lock = NSLock()
    private var children: [Int] = [] // opaque handles (RuntimeJobHandle or RuntimeAsyncTask)
    private var firstChildFailure = 0
    private(set) var isCancelled = false
    /// Cancellation message stored when cancel(message:cause:) is called on this scope.
    private(set) var cancellationMessage: String = "CancellationException"
    /// Cancellation cause stored when cancel(message:cause:) is called on this scope.
    private(set) var cancellationCause: Int = 0
    let isSupervisor: Bool
    let context: RuntimeCoroutineContext
    /// The Job this scope installs into its block's coroutine context
    /// (KUU-964). `coroutineScope { }`/`supervisorScope { }` create a fresh
    /// child job at scope entry so `currentCoroutineContext().job` resolves
    /// inside the block; scopes built around an explicit context adopt the
    /// context's Job element instead.
    private(set) var job: RuntimeJobHandle?
    fileprivate var parent: RuntimeCoroutineScope?
    fileprivate var enclosingJob: RuntimeJobHandle?
    /// Optional debug name assigned via CoroutineName context element (STDLIB-CORO-077).
    var name: String?

    /// Handle of the `kotlinx.coroutines.test.TestCoroutineScheduler` lazily
    /// minted for this scope (KSP-1583); 0 while unrequested so plain scopes
    /// pay nothing.
    private var testSchedulerHandle = 0

    /// The scope's lazily minted `TestCoroutineScheduler` handle, backing
    /// `TestScope.testScheduler` when this scope masquerades as a TestScope.
    func schedulerForTest() -> Int {
        lock.lock()
        defer { lock.unlock() }
        if testSchedulerHandle == 0 {
            testSchedulerHandle = runtimeRegisterObject(RuntimeTestScheduler())
        }
        return testSchedulerHandle
    }

    /// Returns the test scheduler only when the scope already represents a
    /// test scope. Ordinary coroutine scopes keep using wall-clock delays.
    func testSchedulerIfPresent() -> RuntimeTestScheduler? {
        lock.lock()
        let handle = testSchedulerHandle
        let parentScope = parent
        lock.unlock()
        if handle != 0,
           let scheduler = resolveLiveRuntimeHandle(handle, as: RuntimeTestScheduler.self)
        {
            return scheduler
        }
        return parentScope?.testSchedulerIfPresent()
    }

    // CORO-003: Task-local scope registry (replaces TLS).
    // Maps an opaque task token (assigned by the suspend-entry loop on entry) to
    // the scope that is current for that execution context. This allows
    // `RuntimeCoroutineScope.current` to work from code that runs inside a
    // suspend-entry loop without an explicit continuation handle.
    private static let taskScopeLock = NSLock()
    // Protected by taskScopeLock — all accesses go through installScope/removeScope/scopeForTask.
    nonisolated(unsafe) private static var taskScopeMap: [RuntimeTaskKey: RuntimeCoroutineScope] = [:]

    /// Install scope for the given task key. Called at the top of the
    /// suspend-entry loop so that launched children can discover their parent scope.
    static func installScope(_ scope: RuntimeCoroutineScope?, forTask key: RuntimeTaskKey) {
        taskScopeLock.lock()
        if let scope {
            taskScopeMap[key] = scope
        } else {
            taskScopeMap.removeValue(forKey: key)
        }
        taskScopeLock.unlock()
    }

    /// Remove the task-scope mapping when a suspend-entry loop finishes.
    static func removeScope(forTask key: RuntimeTaskKey) {
        taskScopeLock.lock()
        taskScopeMap.removeValue(forKey: key)
        taskScopeLock.unlock()
    }

    /// Look up the scope installed for the current GCD dispatch work-item.
    /// Falls back to nil if the current thread is not inside a suspend-entry loop.
    static func scopeForTask(_ key: RuntimeTaskKey) -> RuntimeCoroutineScope? {
        taskScopeLock.lock()
        defer { taskScopeLock.unlock() }
        return taskScopeMap[key]
    }

    /// Convenience accessor used by launch/async when they don't have a
    /// continuation handle.  Uses the thread-level task key installed by the
    /// nearest enclosing suspend-entry loop.
    ///
    /// NOTE: This is *not* TLS for the scope itself -- the scope lives on the
    /// continuation.  The task key is only used to *find* which continuation's
    /// scope is active on this thread right now.
    static var current: RuntimeCoroutineScope? {
        get {
            let key = RuntimeCoroutineScopeTaskKey.currentTaskKey
            return scopeForTask(key)
        }
        set {
            let key = RuntimeCoroutineScopeTaskKey.currentTaskKey
            installScope(newValue, forTask: key)
        }
    }

    init(isSupervisor: Bool = false, context: RuntimeCoroutineContext = RuntimeCoroutineContext()) {
        self.isSupervisor = isSupervisor
        self.context = context
        self.name = context.name
        RuntimeLiveHandles.register(self)
        // The scope handle doubles as the Kotlin-visible `CoroutineScope`
        // value: `this` inside coroutine builder lambdas and the receiver of
        // implicit CoroutineScope calls are both this raw pointer. Tag it with
        // the interface's nominal type ID so `is`/`as`/`as?` checks against
        // CoroutineScope succeed. Member calls keep dispatching through the
        // external kk_coroutine_scope_* bridges, which already accept the raw
        // handle, so no vtable/itable registration is needed for them.
        runtimeRegisterObjectType(
            rawValue: Int(bitPattern: Unmanaged.passUnretained(self).toOpaque()),
            classID: runtimeCoroutineScopeInterfaceTypeID
        )
    }

    deinit {
        RuntimeLiveHandles.unregister(self)
    }

    /// KUU-964: create this scope's own Job — the element `coroutineContext.job`
    /// resolves to inside the scope's block — mark it started, and parent it to
    /// the job currently in force so a parent cancellation reaches this scope's
    /// children. The job is kept alive for the process lifetime (same bounded
    /// leak `kk_job_new` accepts) so a `CoroutineContext` handle that outlives
    /// the scope still resolves to a valid job object.
    @discardableResult
    func installJob(defaultCancellationMessage: String = "CancellationException") -> RuntimeJobHandle {
        let scopeJob = RuntimeJobHandle(defaultCancellationMessage: defaultCancellationMessage)
        // KUU-1352: kotlinx names these ScopeCoroutine / SupervisorCoroutine.
        scopeJob.debugName = isSupervisor ? "SupervisorCoroutine" : "ScopeCoroutine"
        scopeJob.propagatesFailureToParent = false
        scopeJob.isSupervisorMarker = isSupervisor
        scopeJob.markStarted()
        job = scopeJob
        installJobCancellationLink(scopeJob)
        let scopeJobRaw = runtimeRegisterObject(scopeJob)
        RuntimeJobHandle.current?.registerChild(scopeJobRaw)
        return scopeJob
    }

    /// Adopt `existing` (e.g. the Job element a `CoroutineScope(context)` was
    /// built around) as this scope's job so scope cancellation and a cancel
    /// reaching the job propagate both ways.
    func adoptJob(_ existing: RuntimeJobHandle) {
        job = existing
        installJobCancellationLink(existing)
    }

    /// When the scope's job starts cancelling (e.g. via its parent), tear down
    /// the scope — `cancel()` then cancels every registered child and re-enters
    /// `job.cancel()`, which is a no-op by then. The job side references the
    /// scope weakly: the job is registered for the process lifetime while the
    /// scope can be released at `kk_coroutine_scope_wait`.
    ///
    /// Completion handlers run on EVERY terminal transition — including the
    /// normal `complete()` `kk_coroutine_scope_wait` performs when the scope
    /// finishes — so only a job that is actually cancelling (or was cancelled
    /// before it started) may tear the scope down; a normal completion must
    /// not cancel the scope's children.
    private func installJobCancellationLink(_ scopeJob: RuntimeJobHandle) {
        scopeJob.addChildFailureObserver { [weak self] exception in
            self?.recordChildFailure(exception)
        }
        _ = scopeJob.addCompletionHandler(onCancelling: true) { [weak self, weak scopeJob] cause in
            guard scopeJob?.cancellationSnapshot() == true else { return }
            self?.recordChildFailure(cause)
            self?.cancel(cause: cause)
        }
    }

    func childFailureSnapshot() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return firstChildFailure
    }

    func recordBodyFailure(_ exception: Int) {
        recordChildFailure(exception)
    }

    private func recordChildFailure(_ exception: Int) {
        guard !isSupervisor, exception != 0, exception != runtimeNullSentinelInt,
              kk_is_cancellation_exception(exception) == 0 else { return }
        lock.lock()
        if firstChildFailure == 0 { firstChildFailure = exception }
        lock.unlock()
    }

    private func cancel(cause: Int) {
        cancel(message: "CancellationException", cause: cause)
    }

    func registerChild(_ handle: Int) {
        let childJob = runtimeJobHandle(from: handle) ?? runtimeAsyncTask(from: handle)?.completionJob
        if let job {
            job.registerChild(handle)
        } else {
            // ContextScope without an explicit Job still owns its children.
            _ = childJob?.addCompletionHandler(onCancelling: false) { [weak self] cause in
                guard let self, !self.isSupervisor, cause != 0, cause != runtimeNullSentinelInt,
                      kk_is_cancellation_exception(cause) == 0 else { return }
                self.recordChildFailure(cause)
                self.cancel(cause: cause)
            }
        }
        // Take an additional retain so the scope keeps the child alive
        // even if user code calls takeRetainedValue (e.g. kk_kxmini_async_await)
        if let ptr = UnsafeMutableRawPointer(bitPattern: handle) {
            _ = Unmanaged<AnyObject>.fromOpaque(ptr).retain()
        }
        lock.lock()
        children.append(handle)
        let cancelled = isCancelled
        lock.unlock()
        if cancelled {
            runtimeCancelChild(handle)
        }
    }

    func cancel() {
        lock.lock()
        if isCancelled {
            lock.unlock()
            return
        }
        isCancelled = true
        let currentChildren = children
        let scopeJob = job
        let message = cancellationMessage
        let cause = cancellationCause
        lock.unlock()
        scopeJob?.cancel(message: message, cause: cause)
        for child in currentChildren {
            runtimeCancelChild(child)
        }
    }

    /// Cancel with a specific message and cause so that a materialised
    /// CancellationException carries the correct values.
    func cancel(message: String, cause: Int) {
        lock.lock()
        if isCancelled {
            lock.unlock()
            return
        }
        cancellationMessage = message
        cancellationCause = cause
        isCancelled = true
        let currentChildren = children
        let scopeJob = job
        lock.unlock()
        scopeJob?.cancel(message: message, cause: cause)
        for child in currentChildren {
            runtimeCancelChild(child)
        }
    }

    func waitForChildren(releaseOriginalHandles: Bool = true) -> Int {
        var firstFailure = 0
        var cancelledRemainingChildren = false
        // A child can register more work while we join it. Drain successive
        // batches so those descendants also finish before the scope returns.
        while true {
            lock.lock()
            let currentChildren = children
            let recordedFailure = firstChildFailure
            lock.unlock()
            if recordedFailure != 0 { firstFailure = recordedFailure }
            if currentChildren.isEmpty {
                return firstFailure
            }
            for (index, child) in currentChildren.enumerated() {
                let childResult = runtimeJoinChild(child)
                let observedFailure = childFailureSnapshot()
                if observedFailure != 0 { firstFailure = observedFailure }
                // Cancelling one child Job is not a failure of its parent
                // scope. Parent-scope cancellation is tracked separately by
                // `isCancelled`; either way, a child's terminal
                // CancellationException must not escape from the scope join.
                let shouldIgnoreChildCancellation = runtimeCoroutineIsCancellationResult(childResult)
                if !isSupervisor, firstFailure == 0,
                   runtimeCoroutineIsThrowableResult(childResult),
                   !shouldIgnoreChildCancellation
                {
                    recordChildFailure(childResult)
                    firstFailure = childFailureSnapshot()
                    if !isSupervisor, !cancelledRemainingChildren {
                        cancelledRemainingChildren = true
                        cancel()
                        for remainingChild in currentChildren.dropFirst(index + 1) {
                            runtimeCancelChild(remainingChild)
                        }
                    }
                }
            }
            lock.lock()
            children.removeFirst(currentChildren.count)
            lock.unlock()
            for child in currentChildren {
                if let ptr = UnsafeMutableRawPointer(bitPattern: child) {
                    // Check the per-handle flag to see if user code already consumed the passRetained.
                    // This is scope-independent: the flag lives on the handle object itself,
                    // so it works correctly even with nested scopes or cross-thread joins.
                    let consumed: Bool
                    let obj = Unmanaged<AnyObject>.fromOpaque(ptr).takeUnretainedValue()
                    switch RuntimeJobOrTask(obj) {
                    case .job(let job):
                        consumed = job.consumedByUserCodeSnapshot()
                    case .task(let task):
                        consumed = task.consumedByUserCodeSnapshot()
                    case .other:
                        consumed = false
                    }
                    // Release the extra retain taken in registerChild
                    Unmanaged<AnyObject>.fromOpaque(ptr).release()
                    // Release the original passRetained only if user code hasn't already consumed it
                    // (via kk_job_join or kk_kxmini_async_await)
                    if !consumed, releaseOriginalHandles {
                        Unmanaged<AnyObject>.fromOpaque(ptr).release()
                        // Clean up from RuntimeStorage
                        runtimeStorage.withGCLock { state in
                            state.objectPointers.remove(UInt(bitPattern: ptr))
                        }
                    }
                }
            }
        }
    }
}

private func runtimeCoroutineIsThrowableResult(_ result: Int) -> Bool {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: result) else {
        return false
    }
    // Only attempt the dynamic cast if the pointer is a known runtime object.
    // Raw integer results (e.g. 3 from `async { 1 + 2 }`) are not valid
    // object pointers and would crash swift_retain inside tryCast.
    let isRegistered = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: pointer))
    }
    guard isRegistered else {
        return false
    }
    return tryCast(pointer, to: RuntimeThrowableBox.self) != nil
}

func runtimeCoroutineIsCancellationResult(_ result: Int) -> Bool {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: result) else {
        return false
    }
    let isRegistered = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: pointer))
    }
    guard isRegistered else {
        return false
    }
    return tryCast(pointer, to: RuntimeCancellationBox.self) != nil
}

// MARK: - Structured Concurrency C ABI (P5-89)

/// Enters `scope` as the ambient scope for the coroutine running right now.
///
/// Besides the task-scope map (`RuntimeCoroutineScope.current`), the scope is
/// stored on the running continuation. A `suspend` block invoked next runs on a
/// *fresh* child continuation whose scope is seeded from its caller's
/// continuation (see `kk_coroutine_call_direct_suspend`), so binding the scope
/// here is what lets children launched inside a Kotlin-level `coroutineScope { }`
/// block register with the freshly created scope rather than the outer one.
private func enterScopeOnCurrentContinuation(_ scope: RuntimeCoroutineScope?, job: RuntimeJobHandle?) {
    RuntimeCoroutineScope.current = scope
    if let state = RuntimeContinuationState.current {
        state.scope = scope
        state.jobHandle = job
        job?.continuationState = state
    }
    RuntimeJobHandle.current = job
}

/// Creates a new coroutine scope and installs it as the current scope in the
/// task-scope registry (CORO-003: no TLS for the scope itself).
@_cdecl("kk_coroutine_scope_new")
public func kk_coroutine_scope_new() -> Int {
    let scope = RuntimeCoroutineScope()
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(scope).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }

    // KUU-964: the scope's own Job — installed into the block's context so
    // `currentCoroutineContext().job` resolves there.
    scope.installJob(defaultCancellationMessage: "ScopeCoroutine was cancelled")

    // Push: save parent scope and set this as current via the task-scope map
    scope.parent = RuntimeCoroutineScope.current
    scope.enclosingJob = RuntimeContinuationState.current?.jobHandle ?? RuntimeJobHandle.current
    enterScopeOnCurrentContinuation(scope, job: scope.job)

    return Int(bitPattern: ptr)
}

@_cdecl("kk_supervisor_scope_new")
public func kk_supervisor_scope_new() -> Int {
    let scope = RuntimeCoroutineScope(isSupervisor: true)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(scope).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }

    // KUU-964: the scope's own SupervisorJob — installed into the block's
    // context so `currentCoroutineContext().job` resolves there. Children's
    // failures never complete this job (supervisor failure isolation).
    scope.installJob(defaultCancellationMessage: "SupervisorCoroutine was cancelled")

    // Push: save parent scope and set this as current via the task-scope map,
    // mirroring kk_coroutine_scope_new so the running continuation observes
    // the same ambient scope the task-scope map reports.
    scope.parent = RuntimeCoroutineScope.current
    scope.enclosingJob = RuntimeContinuationState.current?.jobHandle ?? RuntimeJobHandle.current
    enterScopeOnCurrentContinuation(scope, job: scope.job)

    return Int(bitPattern: ptr)
}

/// Cancels the given coroutine scope and all its children.
@_cdecl("kk_coroutine_scope_cancel")
public func kk_coroutine_scope_cancel(_ scopeHandle: Int) -> Int {
    guard let scope = runtimeCoroutineScope(from: scopeHandle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_coroutine_scope_cancel received invalid scope handle")
    }
    scope.cancel()
    return 0
}

/// Records a scoped builder's body failure before cancelling and joining its
/// children, preserving the first non-cancellation cause across cleanup.
@_cdecl("kk_coroutine_scope_fail")
public func kk_coroutine_scope_fail(_ scopeHandle: Int, _ exception: Int) -> Int {
    guard let scope = runtimeCoroutineScope(from: scopeHandle) else {
        runtimeStructuredPanic("kk_coroutine_scope_fail received an invalid scope handle")
    }
    scope.recordBodyFailure(exception)
    scope.cancel(message: "CancellationException", cause: exception)
    return 0
}

/// Waits for all children in the scope to complete, then pops/releases the scope.
@_cdecl("kk_coroutine_scope_wait")
public func kk_coroutine_scope_wait(_ scopeHandle: Int) -> Int {
    guard let scope = runtimeCoroutineScope(from: scopeHandle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_coroutine_scope_wait received invalid scope handle")
    }
    let firstFailure = scope.waitForChildren()

    // KUU-964: settle the scope's own Job as the scope tears down. A cancelled
    // scope leaves the job cancelled (the complete() below settles the
    // intermediate .cancelling state into .cancelled); every other outcome —
    // a supervisor observing a child failure included — completes the job
    // normally, matching kotlinx's scope-coroutine lifecycle.
    if let scopeJob = scope.job {
        if scope.isCancelled {
            _ = scopeJob.cancel(message: scope.cancellationMessage, cause: scope.cancellationCause)
        }
        _ = scopeJob.complete(with: 0)
    }

    // Pop: restore parent scope in the task-scope map (CORO-003) and on the
    // running continuation, mirroring enterScopeOnCurrentContinuation.
    enterScopeOnCurrentContinuation(scope.parent, job: scope.enclosingJob)

    // Release the scope
    _ = runtimeReleaseObject(scopeHandle)
    // The Kotlin ABI models this as `Throwable?`; absence of a failure must use
    // the shared null sentinel (see runtimeResultExceptionOrNull) rather than raw
    // 0, so a `!= null` check in bundled Kotlin resolves correctly.
    if firstFailure != 0 {
        return firstFailure
    }
    if scope.isCancelled {
        // KUU-964: the scope's job was cancelled while its body finished
        // normally — kotlinx surfaces the scope coroutine's own
        // JobCancellationException here ("<ClassName> was cancelled"), not a
        // silent normal return. Childrens' cancellation results are already
        // excluded from firstFailure, so a cancellation reaching this point
        // is the scope's own.
        let name = scope.isSupervisor ? "SupervisorCoroutine" : "ScopeCoroutine"
        return runtimeAllocateCancellationException(message: "\(name) was cancelled")
    }
    return runtimeNullSentinelInt
}

/// Returns 1 if the scope is active (not cancelled), 0 if cancelled.
/// This is the ABI backing for `scope.isActive` in Kotlin.
@_cdecl("__kk_coroutine_scope_is_runtime")
public func __kk_coroutine_scope_is_runtime(_ handle: Int) -> Int {
    runtimeCoroutineScope(from: handle) == nil ? 0 : 1
}

@_cdecl("kk_coroutine_scope_is_active")
public func kk_coroutine_scope_is_active(_ scopeHandle: Int) -> Int {
    guard let scope = runtimeCoroutineScope(from: scopeHandle) else {
        // Builder lambdas use a no-receiver ABI. Older lowering can still name
        // the CoroutineScope property bridge for a bare `isActive` read, but
        // provides no scope handle; in that shape the Kotlin meaning is the
        // currently running job's active state.
        return kk_coroutine_current_is_active()
    }
    return scope.isCancelled ? 0 : 1
}

/// Returns 1 if the scope has been cancelled, 0 otherwise.
/// This is the ABI backing for checking `scope.coroutineContext[Job]?.isCancelled`.
public func kk_coroutine_scope_is_cancelled(_ scopeHandle: Int) -> Int {
    guard let scope = runtimeCoroutineScope(from: scopeHandle) else {
        return 1 // invalid handle → treat as cancelled
    }
    return scope.isCancelled ? 1 : 0
}

/// Registers a child job/deferred handle with the given scope.
public func kk_coroutine_scope_register_child(_ scopeHandle: Int, _ childHandle: Int) -> Int {
    guard let scope = runtimeCoroutineScope(from: scopeHandle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_coroutine_scope_register_child received invalid scope handle")
    }
    scope.registerChild(childHandle)
    return childHandle
}

// MARK: - kotlinx.coroutines.CoroutineScope(context) / Job() / SupervisorJob() (STDLIB-CORO-090)
//
// Unlike `kk_coroutine_scope_new`/`kk_supervisor_scope_new` (used by the lexically-scoped
// `coroutineScope { }`/`supervisorScope { }` block constructs, which push the new scope as
// the ambient "current" scope and tear it down via `kk_coroutine_scope_wait` when the block
// exits), a `CoroutineScope(context)` value is typically stored in a Kotlin property and
// used across many unrelated later calls (`scope.launch { }`, `scope.cancel()`). It must
// NOT be pushed as ambient/current at construction time, and -- per the same reasoning as
// the NOTE on `kk_job_join` -- must NOT be released here, since a live Kotlin reference can
// keep calling members on it indefinitely.

/// Backing for the top-level `CoroutineScope(context: CoroutineContext): CoroutineScope`
/// factory function. Reads a `SupervisorJob()` element in `context` (if any) to decide
/// whether children launched into this scope get supervisor (sibling-failure-isolated)
/// semantics, matching `kotlinx.coroutines.ContextScope`.
@_cdecl("kk_coroutine_scope_new_with_context")
public func kk_coroutine_scope_new_with_context(_ contextRaw: Int) -> Int {
    let ctx = resolveToCoroutineContext(contextRaw)
    var isSupervisor = false
    if let job = runtimeJobHandle(from: ctx.jobHandleRaw) {
        isSupervisor = job.isSupervisorMarker
    }
    let scope = RuntimeCoroutineScope(isSupervisor: isSupervisor, context: ctx)
    if let job = runtimeJobHandle(from: ctx.jobHandleRaw) {
        // The scope's job is the context's Job element: scope.cancel() cancels
        // it (kotlinx's CoroutineScope.cancel contract), and a cancel reaching
        // it takes this scope's children down with it.
        scope.adoptJob(job)
    }
    return runtimeRegisterObject(scope)
}

/// `scopeSlotRaw` names the suspend-entry receiver launcher slot — 0 for
/// launcher-marked (receiver-first) literals, `params.count - 1` for
/// unmarked (captures-first) suspend values — and the receiver scope lands
/// there so `this` inside the block binds to a real RuntimeCoroutineScope,
/// the same convention `kk_test_run_blocking_with_cont` uses. A
/// launcher-marked literal with no receiver parameter (the bare
/// implicit-scope `launch {}`/`async {}` form, `this` bound through
/// `state.scope` below) passes `params.count` so this write lands in a
/// slot the launcher thunk never reads.
@_cdecl("kk_coroutine_scope_async_with_cont")
public func kk_coroutine_scope_async_with_cont(
    _ scopeHandle: Int, _ contextRaw: Int, _ start: Int,
    _ entryPointRaw: Int, _ continuation: Int, _ scopeSlotRaw: Int
) -> Int {
    guard let scope = runtimeCoroutineScope(from: scopeHandle),
          let state = runtimeContinuationState(from: continuation),
          scopeSlotRaw >= 0
    else { runtimeStructuredPanic("CoroutineScope.async received an invalid scope or continuation") }
    let context = scope.context.plus(resolveToCoroutineContext(contextRaw))
    // The block's coroutineContext gains the async task's Job (kotlinx's
    // DeferredCoroutine contract), so `this` and any nested builder observe a
    // child scope whose Job is the task's — not the receiver scope's.
    let childScope = RuntimeCoroutineScope(context: context)
    childScope.parent = scope
    let childHandle = runtimeRegisterObject(childScope)
    state.launcherArgs[Int64(scopeSlotRaw)] = Int64(childHandle)
    state.scope = childScope
    state.builderContext = context
    if context.dispatcher == 0 {
        state.eventLoop = RuntimeEventLoop.current
    }
    return runtimeScopeAsync(
        scope: scope, context: context, start: start,
        yieldsDeferredResult: true,
        prepare: { task, handle in
            context.jobHandleRaw = handle
            childScope.adoptJob(task.completionJob)
        }
    ) { task in
        state.jobHandle = task.completionJob
        task.completionJob.continuationState = state
        runtimeStartLaunchedBody(
            entryPointRaw: entryPointRaw, continuation: continuation,
            scope: childScope, job: task.completionJob, onFinished: runtimeAsyncTaskCompletion(task)
        )
    }
}

@_cdecl("kk_coroutine_scope_async")
public func kk_coroutine_scope_async(
    _ scopeHandle: Int, _ contextRaw: Int, _ start: Int,
    _ entryPointRaw: Int, _ closureRaw: Int
) -> Int {
    guard let scope = runtimeCoroutineScope(from: scopeHandle),
          entryPointRaw != 0
    else {
        runtimeStructuredPanic("CoroutineScope.async received an invalid scope or block")
    }
    let context = scope.context.plus(resolveToCoroutineContext(contextRaw))

    // The block is a `suspend CoroutineScope.() -> T` value whose thunk keeps
    // the ordinary captured-lambda layout `(cap0..capN, receiver, outThrown)`.
    // Expand the env slot into positional captures the same way
    // `__kk_produce_launch` does — boxed value → its env, 0 → none, packed
    // env object (kk_object_new(2+N, classID: 0), captures at slots 2..) → N
    // captures, anything else → a single raw capture — and pass the receiver
    // scope as the trailing receiver (the block's `this`).
    let captures: [Int]
    let resolvedEntryPointRaw: Int
    if let functionValue = runtimeFunctionValueBox(from: entryPointRaw) {
        resolvedEntryPointRaw = functionValue.fnPtr
        captures = [functionValue.closureRaw]
    } else if let object = runtimeCallableObjectPair(from: entryPointRaw) {
        resolvedEntryPointRaw = object.fnPtr
        captures = [object.closureRaw]
    } else if closureRaw == 0 {
        resolvedEntryPointRaw = entryPointRaw
        captures = []
    } else if let envBox = resolveRuntimeHandle(closureRaw, as: RuntimeObjectBox.self),
              envBox.classID == 0,
              envBox.elements.count > 2
    {
        resolvedEntryPointRaw = entryPointRaw
        captures = Array(envBox.elements.dropFirst(2))
    } else {
        resolvedEntryPointRaw = entryPointRaw
        captures = [closureRaw]
    }
    // Same DeferredCoroutine contract as the continuation path: the block runs
    // on a child scope whose context Job is this task's job.
    let childScope = RuntimeCoroutineScope(context: context)
    childScope.parent = scope
    let childHandle = runtimeRegisterObject(childScope)
    return runtimeScopeAsync(
        scope: scope, context: context, start: start,
        yieldsDeferredResult: true,
        prepare: { task, handle in
            context.jobHandleRaw = handle
            childScope.adoptJob(task.completionJob)
        }
    ) { task in
        RuntimeCoroutineScope.current = childScope
        var thrown = 0
        let result = runtimeInvokeSuspendLauncherThunk(
            entryPointRaw: resolvedEntryPointRaw,
            receiver: childHandle,
            captures: captures,
            outThrown: &thrown
        )
        runtimeAsyncTaskCompletion(task)(result, thrown)
    }
}

// Launch shares the task scheduling/Job ABI with async, but owns a child
// scope and reports uncaught failures instead of exposing a deferred result.
@_cdecl("__kk_coroutine_scope_launch_context")
public func __kk_coroutine_scope_launch_context(
    _ scopeHandle: Int, _ contextRaw: Int, _ start: Int,
    _ entryPointRaw: Int, _ closureRaw: Int
) -> Int {
    guard entryPointRaw != 0 else { runtimeStructuredPanic("launch received an invalid block") }
    let resolved = runtimeScopeReceiverBlock(entryPointRaw, closureRaw)
    return runtimeScopeLaunch(scopeHandle, contextRaw, start) { task, childScope, childHandle, finish in
        RuntimeCoroutineScope.current = childScope
        var thrown = 0
        let result = runtimeInvokeSuspendLauncherThunk(
            entryPointRaw: resolved.entry, receiver: childHandle,
            captures: resolved.captures, outThrown: &thrown
        )
        finish(result, thrown)
    }
}

@_cdecl("__kk_coroutine_scope_launch_context_with_cont")
public func __kk_coroutine_scope_launch_context_with_cont(
    _ scopeHandle: Int, _ contextRaw: Int, _ start: Int,
    _ entryPointRaw: Int, _ continuation: Int, _ scopeSlotRaw: Int
) -> Int {
    guard let state = runtimeContinuationState(from: continuation), scopeSlotRaw >= 0 else {
        runtimeStructuredPanic("launch received an invalid continuation")
    }
    return runtimeScopeLaunch(scopeHandle, contextRaw, start) { task, childScope, childHandle, finish in
        state.launcherArgs[Int64(scopeSlotRaw)] = Int64(childHandle)
        state.scope = childScope
        state.builderContext = childScope.context
        state.jobHandle = task.completionJob
        task.completionJob.continuationState = state
        if childScope.context.dispatcher == 0 { state.eventLoop = RuntimeEventLoop.current }
        runtimeStartLaunchedBody(
            entryPointRaw: entryPointRaw, continuation: continuation,
            scope: childScope, job: task.completionJob, onFinished: finish
        )
    }
}

private func runtimeScopeReceiverBlock(_ entry: Int, _ closure: Int) -> (entry: Int, captures: [Int]) {
    if let box = runtimeFunctionValueBox(from: entry) {
        return (box.fnPtr, [box.closureRaw])
    }
    if let object = runtimeCallableObjectPair(from: entry) {
        return (object.fnPtr, [object.closureRaw])
    }
    if closure == 0 { return (entry, []) }
    if let env = resolveRuntimeHandle(closure, as: RuntimeObjectBox.self),
       env.classID == 0, env.elements.count > 2 {
        return (entry, Array(env.elements.dropFirst(2)))
    }
    return (entry, [closure])
}

private func runtimeScopeLaunch(
    _ scopeHandle: Int, _ contextRaw: Int, _ start: Int,
    body: @escaping @Sendable (RuntimeAsyncTask, RuntimeCoroutineScope, Int,
                              @escaping @Sendable (Int, Int) -> Void) -> Void
) -> Int {
    guard let scope = runtimeCoroutineScope(from: scopeHandle) else {
        runtimeStructuredPanic("launch received an invalid scope")
    }
    let additionalContext = resolveToCoroutineContext(contextRaw)
    let context = scope.context.plus(additionalContext)
    let contextParent = runtimeJobHandle(from: context.jobHandleRaw)
        ?? runtimeAsyncTask(from: context.jobHandleRaw)?.completionJob ?? scope.job
    let parent = contextParent === runtimeNonCancellableJob ? nil : contextParent
    let childScope = RuntimeCoroutineScope(context: context)
    childScope.parent = scope
    let childHandle = runtimeRegisterObject(childScope)
    // Whether the child is additionally registered into `scope` for
    // waitForChildren tracking — a scope that observes the failure can absorb
    // it even when the declared parent (`parent`) is nil or a supervisor.
    let registerWithScope = additionalContext.jobHandleRaw == 0 || (parent != nil && parent === scope.job)
    let finish: @Sendable (RuntimeAsyncTask, Int, Int) -> Void = { task, _, thrown in
        let priorChildFailure = childScope.childFailureSnapshot()
        if thrown != 0 { childScope.cancel(message: "launch failed", cause: thrown) }
        let childFailure = childScope.waitForChildren()
        // A descendant failure can cancel the body before its completion.
        // Report the original failure rather than the resulting cancellation.
        let failure = priorChildFailure != 0 ? priorChildFailure
            : (childFailure != 0 && (thrown == 0 || runtimeCoroutineIsCancellationResult(thrown))
                ? childFailure : thrown)
        if failure != 0 && !runtimeCoroutineIsCancellationResult(failure) {
            if let parent, runtimeJobAbsorbsChildFailure(parent) {
                _ = parent.cancel(cause: failure)
            } else if !(registerWithScope && runtimeScopeAbsorbsChildFailure(scope)) {
                // KUU-1422: no parent absorbed the failure (unparented or
                // supervisor). kotlinx's handleCoroutineException: an explicit
                // context CoroutineExceptionHandler consumes it, otherwise the
                // failure gets the JVM-style uncaught report instead of the
                // quiet default-handler print that made it look handled.
                // Report before completing the task — completion wakes
                // joiners synchronously, and they must never resume past an
                // unflushed report.
                runtimeHandleUncaughtCoroutineException(context: context, exception: failure)
            }
            task.completeExceptionally(with: failure)
        } else if failure != 0 {
            task.cancel(cause: failure)
            task.complete(with: 0)
        } else {
            task.complete(with: 0)
        }
    }
    return runtimeScopeAsync(
        scope: scope, context: context, start: start,
        registerWithScope: registerWithScope,
        prepare: { task, handle in
            // The receiver's context contains the child Job, so nested builders
            // inherit the child's name/dispatcher and attach to the child.
            context.jobHandleRaw = handle
            childScope.adoptJob(task.completionJob)
            parent?.registerChild(handle)
        }
    ) { task in
        body(task, childScope, childHandle) { result, thrown in finish(task, result, thrown) }
    }
}

private func runtimeScopeAsync(
    scope: RuntimeCoroutineScope,
    context: RuntimeCoroutineContext,
    start: Int,
    yieldsDeferredResult: Bool = false,
    registerWithScope: Bool = true,
    prepare: ((RuntimeAsyncTask, Int) -> Void)? = nil,
    body: @escaping @Sendable (RuntimeAsyncTask) -> Void
) -> Int {
    // KUU-1352: the kotlinx coroutine class this builder mints —
    // (Lazy)DeferredCoroutine for `async`, (Lazy)StandaloneCoroutine for
    // `launch`; the LAZY start mode owns the `Lazy` prefix.
    let task = RuntimeAsyncTask(
        atomicStart: start == 2,
        debugName: yieldsDeferredResult
            ? (start == 1 ? "LazyDeferredCoroutine" : "DeferredCoroutine")
            : (start == 1 ? "LazyStandaloneCoroutine" : "StandaloneCoroutine")
    )
    task.isDeferredResult = yieldsDeferredResult
    // KUU-1352: a scheduled (non-LAZY) coroutine is Active from the moment the
    // builder returns — kotlinx has no `New` state for it.
    if start != 1 { task.markScheduledForLaunch() }
    let handle = Int(bitPattern: Unmanaged.passRetained(task).toOpaque())
    prepare?(task, handle)
    if registerWithScope { scope.registerChild(handle) }
    let work: @Sendable () -> Void = {
        guard task.markStarted() else { return }
        let savedKey = RuntimeCoroutineScopeTaskKey.currentTaskKey
        let savedJob = RuntimeJobHandle.current
        let savedDispatcher = RuntimeDispatcher.current
        let workKey = RuntimeCoroutineScopeTaskKey.installFreshKey()
        defer {
            RuntimeCoroutineScope.removeScope(forTask: workKey)
            RuntimeCoroutineScopeTaskKey.installKey(savedKey)
            RuntimeJobHandle.current = savedJob
            RuntimeDispatcher.current = savedDispatcher
        }
        if context.dispatcher != 0 {
            RuntimeDispatcher.current = runtimeResolveDispatcher(from: context.dispatcher)
        }
        RuntimeJobHandle.current = task.completionJob
        body(task)
    }
    let schedule: @Sendable () -> Void = {
        if context.dispatcher != 0 {
            runtimeResolveDispatcher(from: context.dispatcher).queue.async(execute: work)
        } else if let scheduler = scope.testSchedulerIfPresent() {
            scheduler.schedule(after: 0, action: work)
        } else {
            KxMiniRuntime.launch(work)
        }
    }
    switch start {
    case 1: task.installLazyStartBody(schedule)
    case 3: work()
    default: schedule()
    }
    return handle
}

/// Backing for `CoroutineScope.launch { block }`. Unlike `kk_kxmini_launch` (which
/// registers the new job with whatever scope happens to be ambient/"current" at the
/// call site), this launches into the EXPLICIT receiver `scope` passed in by the
/// caller. That is the whole point of a property-stored, unstructured
/// `CoroutineScope(...)`: `scope.cancel()` must cascade to jobs started this way no
/// matter which scope (if any) is ambient wherever `.launch` happens to be called from.
@_cdecl("kk_coroutine_scope_launch")
public func kk_coroutine_scope_launch(_ scopeHandle: Int, _ entryPointRaw: Int, _ functionID: Int) -> Int {
    guard let scope = runtimeCoroutineScope(from: scopeHandle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_coroutine_scope_launch received invalid scope handle")
    }
    let job = RuntimeJobHandle()
    job.debugName = "StandaloneCoroutine"
    let jobPtr = UnsafeMutableRawPointer(Unmanaged.passRetained(job).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: jobPtr))
    }
    job.markStarted()
    let continuation = kk_coroutine_continuation_new(functionID)
    if let state = runtimeContinuationState(from: continuation) {
        job.continuationState = state
        state.jobHandle = job
        // Propagate the explicit receiver scope (not whatever is ambient) to the
        // child continuation's context so nested launch/async inside the block
        // discover `scope`, matching kotlinx.coroutines' CoroutineScope.launch.
        state.scope = scope
    }
    scope.registerChild(Int(bitPattern: jobPtr))
    scope.job?.registerChild(Int(bitPattern: jobPtr))

    KxMiniRuntime.launch {
        // See the identical guard in kk_kxmini_launch: a cancel() that races in
        // between this function returning and the dispatched closure actually
        // running must skip the body entirely (CoroutineStart.DEFAULT semantics).
        if job.cancellationSnapshot() {
            _ = job.complete(with: 0)
            return
        }
        runtimeStartLaunchedBody(
            entryPointRaw: entryPointRaw,
            continuation: continuation,
            scope: scope,
            job: nil
        ) { result, thrown in
            if thrown != 0 {
                runtimeCompleteLaunchJobExceptionally(
                    job, with: thrown, parentJob: scope.job, parentScope: scope
                )
            } else {
                _ = job.complete(with: result)
            }
        }
    }
    return Int(bitPattern: jobPtr)
}

/// Variant of kk_coroutine_scope_launch that accepts a pre-built continuation carrying
/// the launched suspend lambda's captured outer variables (BUG-049). Mirrors
/// kk_coroutine_scope_launch except that the continuation (with its capture slots
/// already populated by the caller) is threaded through the launcher thunk instead of
/// being freshly allocated from a functionID.
@_cdecl("kk_coroutine_scope_launch_with_cont")
public func kk_coroutine_scope_launch_with_cont(_ scopeHandle: Int, _ entryPointRaw: Int, _ continuation: Int) -> Int {
    guard let scope = runtimeCoroutineScope(from: scopeHandle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_coroutine_scope_launch_with_cont received invalid scope handle")
    }
    let job = RuntimeJobHandle()
    job.debugName = "StandaloneCoroutine"
    let jobPtr = UnsafeMutableRawPointer(Unmanaged.passRetained(job).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: jobPtr))
    }
    job.markStarted()
    if let state = runtimeContinuationState(from: continuation) {
        job.continuationState = state
        state.jobHandle = job
        // Propagate the explicit receiver scope (not whatever is ambient) to the
        // child continuation's context so nested launch/async inside the block
        // discover `scope`, matching kk_coroutine_scope_launch above.
        state.scope = scope
    }
    scope.registerChild(Int(bitPattern: jobPtr))
    scope.job?.registerChild(Int(bitPattern: jobPtr))

    KxMiniRuntime.launch {
        if job.cancellationSnapshot() {
            _ = job.complete(with: 0)
            return
        }
        runtimeStartLaunchedBody(
            entryPointRaw: entryPointRaw,
            continuation: continuation,
            scope: scope,
            job: nil
        ) { result, thrown in
            if thrown != 0 {
                runtimeCompleteLaunchJobExceptionally(
                    job, with: thrown, parentJob: scope.job, parentScope: scope
                )
            } else {
                _ = job.complete(with: result)
            }
        }
    }
    return Int(bitPattern: jobPtr)
}
