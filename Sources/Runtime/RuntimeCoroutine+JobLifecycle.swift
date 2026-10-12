import Dispatch
import Foundation

/// Backing for the bare `kotlinx.coroutines.Job(): Job` factory (no parent argument --
/// the only shape currently registered in Sema).
@_cdecl("kk_job_new")
public func kk_job_new() -> Int {
    let job = RuntimeJobHandle()
    job.markStarted()
    // KUU-1386: factory jobs answer `is JobImpl` like kotlinx's Job() result.
    job.nominalJobTypeID = runtimeStableNominalTypeID(fqName: "kotlinx.coroutines.JobImpl")
    return runtimeRegisterObject(job)
}

@_cdecl("__kk_job_bind_wrapper")
public func __kk_job_bind_wrapper(_ wrapperRaw: Int, _ jobRaw: Int, _ parentRaw: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: wrapperRaw),
          let wrapper = tryCast(ptr, to: RuntimeObjectBox.self),
          let job = runtimeJobHandle(from: jobRaw)
    else { return jobRaw }
    job.markBodyless()
    wrapper.coroutineJobHandle = jobRaw
    job.bindSourceWrapper(wrapper)
    // KUU-1386: bare handle `is` checks recover the wrapper's nominal (e.g.
    // `coroutineContext.job is CompletableJob`/`is JobImpl`).
    job.nominalJobTypeID = runtimeObjectTypeID(rawValue: wrapperRaw) ?? 0
    if let parent = runtimeJobHandle(from: parentRaw) {
        parent.registerChild(jobRaw)
        if !parent.isSupervisorMarker {
            _ = job.addCompletionHandler(onCancelling: false) { cause in
                if cause != runtimeNullSentinelInt, job.isFailedSnapshot(),
                   !runtimeCoroutineIsCancellationResult(cause)
                {
                    _ = parent.cancel(cause: cause)
                }
            }
        }
    }
    return jobRaw
}

private func deferredCompletionSnapshot(_ handle: Int) -> (completed: Bool, value: Int, exception: Int) {
    if let job = runtimeJobHandle(from: handle) { return job.completionSnapshot() }
    if let task = runtimeAsyncTask(from: handle) { return task.completionSnapshot() }
    return (false, 0, 0)
}

@_cdecl("__kk_deferred_get_completed")
public func __kk_deferred_get_completed(_ handle: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let snapshot = deferredCompletionSnapshot(handle)
    guard snapshot.completed else {
        outThrown?.pointee = runtimeAllocateIllegalStateException(message: "This job has not completed yet")
        return 0
    }
    outThrown?.pointee = snapshot.exception
    return snapshot.exception == 0 ? snapshot.value : 0
}

@_cdecl("__kk_deferred_completion_exception")
public func __kk_deferred_completion_exception(_ handle: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let snapshot = deferredCompletionSnapshot(handle)
    guard snapshot.completed else {
        outThrown?.pointee = runtimeAllocateIllegalStateException(message: "This job has not completed yet")
        return runtimeNullSentinelInt
    }
    return snapshot.exception == 0 ? runtimeNullSentinelInt : snapshot.exception
}

/// Backing for `kotlinx.coroutines.SupervisorJob(): Job`. Identical to `kk_job_new` except
/// for the `isSupervisorMarker` flag that `kk_coroutine_scope_new_with_context` reads.
@_cdecl("kk_supervisor_job_new")
public func kk_supervisor_job_new() -> Int {
    let job = RuntimeJobHandle()
    job.isSupervisorMarker = true
    job.markStarted()
    // KUU-1386: SupervisorJob() results also answer `is JobImpl` (kotlinx
    // uses the same JobImpl shape; the supervisor flag drives behavior).
    job.nominalJobTypeID = runtimeStableNominalTypeID(fqName: "kotlinx.coroutines.JobImpl")
    return runtimeRegisterObject(job)
}

@_cdecl("kk_job_start")
public func kk_job_start(_ jobHandle: Int) -> Int {
    if let job = runtimeJobHandle(from: jobHandle) {
        return job.startIfNeeded() ? 1 : 0
    }
    if let task = runtimeAsyncTask(from: jobHandle) {
        return task.startIfNeeded() ? 1 : 0
    }
    return 0
}

/// Waits for completion, except for the always-active NonCancellable singleton.
@_cdecl("kk_job_join")
public func kk_job_join(
    _ jobHandle: Int,
    _ continuation: Int,
    _ outThrown: UnsafeMutablePointer<Int>? = nil
) -> Int {
    outThrown?.pointee = 0
    if runtimeJobHandle(from: jobHandle) === runtimeNonCancellableJob {
        outThrown?.pointee = runtimeAllocateUnsupportedOperationException(message: "This job is always active")
        return 0
    }
    return runtimeJoinJob(jobHandle, continuation)
}

private func runtimeJoinJob(_ jobHandle: Int, _ continuation: Int) -> Int {
    if let callerState = runtimeContinuationState(from: continuation) {
        var thrown = 0
        if kk_coroutine_check_cancellation(continuation, &thrown) != 0 {
            callerState.resume(withException: thrown)
            return Int(bitPattern: kk_coroutine_suspended())
        }
    }
    guard jobHandle != 0, let ptr = UnsafeMutableRawPointer(bitPattern: jobHandle) else {
        return 0
    }
    // Mark on the handle object itself that user code is consuming the passRetained.
    // This is checked by scope's waitForChildren to avoid double-release.
    let obj = Unmanaged<AnyObject>.fromOpaque(ptr).takeUnretainedValue()
    let handle = RuntimeJobOrTask(obj)
    switch handle {
    case .job(let job):
        job.markConsumedByUserCode()
    case .task(let task):
        task.markConsumedByUserCode()
    case .other:
        break
    }

    // CORO-004: suspend-aware join. Register a resumer and suspend when the job/task is
    // still running.
    //
    // NOTE: `join()`/`await()` must NOT release the handle's original passRetained here.
    // Kotlin code routinely keeps using a Job/Deferred reference after joining it (e.g.
    // `job.join(); println(job.isCancelled)`), so treating join as "the final use" and
    // releasing eagerly leaves that reference dangling -- a real, previously-reproducing
    // use-after-free crash in `kk_job_is_cancelled`/`kk_job_is_failed`/etc. once accessed
    // post-join. `markConsumedByUserCode()` above already tells `waitForChildren()` to
    // skip its own release for a joined handle, so simply not releasing here just leaves
    // the handle allocated for the life of the process (an intentional, bounded leak)
    // instead of freeing memory a still-live Kotlin variable can reach.
    let releaseHandle: @Sendable () -> Void = {}
    if continuation != 0, let callerState = runtimeContinuationState(from: continuation) {
        switch handle {
        case .job(let job):
            job.startIfNeeded()
            if !job.completedSnapshot() {
                job.addJoinResumer { value in
                    callerState.resume(with: value)
                    releaseHandle()
                }
                return Int(bitPattern: kk_coroutine_suspended())
            }
        case .task(let task):
            switch task.awaitResult(callerState: callerState, afterResume: releaseHandle, propagateFailure: false) {
            case .suspended:
                return Int(bitPattern: kk_coroutine_suspended())
            case .completed(let result, _):
                // Already complete: return synchronously (do not resume callerState).
                releaseHandle()
                return result
            }
        case .other:
            break
        }
    }

    let result: Int = switch handle {
    case .job(let job):
        job.join()
    case .task(let task):
        switch task.awaitResult(callerState: nil, propagateFailure: false) {
        case .completed:
            0
        case .suspended:
            fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: blocking join cannot suspend")
        }
    case .other:
        0
    }
    // See the NOTE above: do not release the original passRetained from launch here --
    // the Kotlin-level Job/Deferred variable may still be read after this synchronous join.
    return result
}

/// Await job completion using the same wait path as join().
@_cdecl("kk_job_await_completion")
public func kk_job_await_completion(
    _ jobHandle: Int,
    _ continuation: Int,
    _ outThrown: UnsafeMutablePointer<Int>? = nil
) -> Int {
    kk_job_join(jobHandle, continuation, outThrown)
}

// MARK: - Child Cancel/Join Helpers (P5-89)

/// Cancel a child handle (RuntimeJobHandle or RuntimeAsyncTask).
func runtimeCancelChild(_ handle: Int) {
    // Completed children can have been released by their scope while an
    // ancestor still holds the raw hierarchy entry. Resolve liveness first.
    if let job = runtimeJobHandle(from: handle) {
        _ = job.cancel()
    } else if let task = runtimeAsyncTask(from: handle) {
        task.cancel()
    }
}

/// Join a child handle (RuntimeJobHandle or RuntimeAsyncTask). Returns the result.
func runtimeJoinChild(_ handle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        return 0
    }
    let obj = Unmanaged<AnyObject>.fromOpaque(ptr).takeUnretainedValue()
    switch RuntimeJobOrTask(obj) {
    case .job(let job):
        return job.join()
    case .task(let task):
        return task.awaitResult()
    case .other:
        return 0
    }
}

// MARK: - Cancellation ABI (CORO-002 / spec.md J17)

/// Cancel a job handle from user code (e.g. `job.cancel()`).
@_cdecl("kk_job_cancel")
public func kk_job_cancel(_ jobHandle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: jobHandle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_job_cancel received invalid job handle")
    }
    let obj = Unmanaged<AnyObject>.fromOpaque(ptr).takeUnretainedValue()
    switch RuntimeJobOrTask(obj) {
    case .job(let job):
        // KSP-1568: `NonCancellable.cancel()` is a no-op upstream. Now that
        // `NonCancellable` conforms to `Job`, a Job-typed reference can reach
        // this entry point with the shared never-cancelled singleton —
        // cancelling it here would permanently corrupt every later
        // `withContext(NonCancellable)` / `isActive` check.
        if job !== runtimeNonCancellableJob {
            _ = job.cancel()
        }
    case .task(let task):
        task.cancel()
    case .other:
        break
    }
    return 0
}

/// Cancel a job with an explicit cause.
@_cdecl("kk_job_cancel_with_cause")
public func kk_job_cancel_with_cause(_ jobHandle: Int, _ cause: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: jobHandle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_job_cancel_with_cause received invalid job handle")
    }
    let obj = Unmanaged<AnyObject>.fromOpaque(ptr).takeUnretainedValue()
    switch RuntimeJobOrTask(obj) {
    case .job(let job):
        if job !== runtimeNonCancellableJob {
            _ = job.cancel(cause: cause)
        }
    case .task(let task):
        task.cancel(cause: cause)
    case .other:
        break
    }
    return 0
}

/// Cancel any `CoroutineContext`-like raw value by finding its Job and cancelling it.
/// The optional cause is accepted for API compatibility, but the current runtime
/// cancellation model is flag-based and does not preserve a custom cause.
@_cdecl("kk_context_cancel")
public func kk_context_cancel(_ contextRaw: Int, _ causeRaw: Int) -> Int {
    _ = causeRaw
    _ = kk_job_cancel(contextRaw)
    let context = resolveToCoroutineContext(contextRaw)
    if context.jobHandleRaw != 0 && context.jobHandleRaw != contextRaw {
        _ = kk_job_cancel(context.jobHandleRaw)
    }
    return 0
}

/// Convenience overload for `CoroutineContext.cancel()` calls that omit a cause.
@_cdecl("kk_context_cancel_no_cause")
public func kk_context_cancel_no_cause(_ contextRaw: Int) -> Int {
    kk_context_cancel(contextRaw, 0)
}

/// Mark a job as completed with a result. Returns 1 if the transition succeeded.
@_cdecl("kk_job_complete")
public func kk_job_complete(_ jobHandle: Int, _ value: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: jobHandle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_job_complete received invalid job handle")
    }
    let obj = Unmanaged<AnyObject>.fromOpaque(ptr).takeUnretainedValue()
    switch RuntimeJobOrTask(obj) {
    case .job(let job):
        return job.complete(with: value) ? 1 : 0
    case .task(let task):
        task.complete(with: value)
        return 1
    case .other:
        return 0
    }
}

@_cdecl("kk_job_complete_unit")
public func kk_job_complete_unit(_ jobHandle: Int) -> Int {
    kk_job_complete(jobHandle, 0)
}

/// Mark a job as failed with an exception cause. Returns 1 if the transition succeeded.
@_cdecl("kk_job_complete_exceptionally")
public func kk_job_complete_exceptionally(_ jobHandle: Int, _ exception: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: jobHandle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_job_complete_exceptionally received invalid job handle")
    }
    let obj = Unmanaged<AnyObject>.fromOpaque(ptr).takeUnretainedValue()
    switch RuntimeJobOrTask(obj) {
    case .job(let job):
        return job.completeExceptionally(with: exception) ? 1 : 0
    case .task(let task):
        task.completeExceptionally(with: exception)
        return 1
    case .other:
        return 0
    }
}

// MARK: - Job State Queries (STDLIB-CORO-070)

/// Returns 1 if the job is active (started but not yet completed and not cancelled).
/// A job is active when it has been launched and neither completed nor cancelled.
/// ABI backing for `job.isActive` in Kotlin.
@_cdecl("kk_job_is_active")
public func kk_job_is_active(_ jobHandle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: jobHandle) else {
        return 0
    }
    let obj = Unmanaged<AnyObject>.fromOpaque(ptr).takeUnretainedValue()
    switch RuntimeJobOrTask(obj) {
    case .job(let job):
        return job.isActiveSnapshot() ? 1 : 0
    case .task(let task):
        return task.isActiveSnapshot() ? 1 : 0
    case .other:
        return 0
    }
}

/// Zero-arg ABI backing for the bare `isActive` reference inside a coroutine
/// builder body (kotlinx.coroutines.isActive), which reads the currently
/// running job rather than an explicit receiver. No enclosing job (e.g. at
/// the outermost runBlocking root) is treated as active, matching the
/// not-yet-cancelled default.
@_cdecl("kk_coroutine_current_is_active")
public func kk_coroutine_current_is_active() -> Int {
    // Prefer the job attached to the active continuation. The separate
    // task-local job map can still contain the parent runBlocking job while a
    // launcher thunk is entering its child continuation.
    guard let job = RuntimeContinuationState.current?.jobHandle ?? RuntimeJobHandle.current else {
        return 1
    }
    return job.isActiveSnapshot() ? 1 : 0
}

/// Returns the raw handle for the CoroutineScope carried by the current
/// continuation. Coroutine builder lambdas keep a no-receiver ABI, so the
/// lowering of an implicit CoroutineScope extension call obtains its receiver
/// through this bridge instead.
@_cdecl("kk_coroutine_current_scope")
public func kk_coroutine_current_scope() -> Int {
    if let state = RuntimeContinuationState.current {
        if let scope = state.scope ?? RuntimeCoroutineScope.current {
            state.scope = scope
            return Int(bitPattern: UnsafeMutableRawPointer(Unmanaged.passUnretained(scope).toOpaque()))
        }

        // A top-level runBlocking body has a continuation but no inherited scope.
        // Materialize its CoroutineScope lazily when a builder lambda needs the
        // implicit receiver, then attach it to the continuation for suspensions
        // and child launchers that follow. The scope's job is the running job —
        // the same element `coroutineContext.job` resolves to here.
        let scope = RuntimeCoroutineScope()
        if let job = state.jobHandle {
            scope.adoptJob(job)
        }
        state.scope = scope
        RuntimeCoroutineScope.current = scope
        return Int(bitPattern: UnsafeMutableRawPointer(Unmanaged.passUnretained(scope).toOpaque()))
    }
    guard let scope = RuntimeCoroutineScope.current else {
        return 0
    }
    return Int(bitPattern: UnsafeMutableRawPointer(Unmanaged.passUnretained(scope).toOpaque()))
}

/// Returns 1 if the job has completed (either normally or by cancellation).
/// ABI backing for `job.isCompleted` in Kotlin.
@_cdecl("kk_job_is_completed")
public func kk_job_is_completed(_ jobHandle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: jobHandle) else {
        return 1 // invalid handle → treat as completed
    }
    let obj = Unmanaged<AnyObject>.fromOpaque(ptr).takeUnretainedValue()
    switch RuntimeJobOrTask(obj) {
    case .job(let job):
        return job.completedSnapshot() ? 1 : 0
    case .task(let task):
        return task.isCompletedSnapshot() ? 1 : 0
    case .other:
        return 1
    }
}

/// Returns 1 if the job has been cancelled.
/// ABI backing for `job.isCancelled` in Kotlin.
@_cdecl("kk_job_is_cancelled")
public func kk_job_is_cancelled(_ jobHandle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: jobHandle) else {
        return 1 // invalid handle → treat as cancelled
    }
    let obj = Unmanaged<AnyObject>.fromOpaque(ptr).takeUnretainedValue()
    switch RuntimeJobOrTask(obj) {
    case .job(let job):
        return job.cancellationSnapshot() || job.isFailedSnapshot() ? 1 : 0
    case .task(let task):
        return task.isCancelledSnapshot() || task.isFailedSnapshot() ? 1 : 0
    case .other:
        return 0
    }
}

/// Returns 1 if the job has failed with an exception.
/// ABI backing for `job.isFailed` in Kotlin (kswiftc extension).
public func kk_job_is_failed(_ jobHandle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: jobHandle) else {
        return 0 // invalid handle → treat as not failed
    }
    let obj = Unmanaged<AnyObject>.fromOpaque(ptr).takeUnretainedValue()
    switch RuntimeJobOrTask(obj) {
    case .job(let job):
        return job.isFailedSnapshot() ? 1 : 0
    case .task(let task):
        return task.isFailedSnapshot() ? 1 : 0
    case .other:
        return 0
    }
}

/// KUU-CORO-101: ABI backing for `Job.getCancellationException()`
/// (`__kk_job_get_cancellation_exception` in `Job.kt`, wrapped there into the
/// public `getCancellationException()` extension). Returns the
/// `CancellationException` this job was (or would be) cancelled with.
/// `RuntimeJobHandle` and task-backed launch/Deferred handles share the
/// same cancellation state through the task's completion Job.
@_cdecl("kk_job_get_cancellation_exception")
public func kk_job_get_cancellation_exception(_ jobHandle: Int) -> Int {
    guard let job = runtimeJobHandle(from: jobHandle)
        ?? runtimeAsyncTask(from: jobHandle)?.completionJob
    else {
        return runtimeAllocateCancellationException(message: "Job is still active")
    }
    let cause = job.cancellationCauseSnapshot()
    if cause != 0 {
        return cause
    }
    return runtimeAllocateCancellationException(message: "Job is still active")
}

/// KUU-CORO-101: ABI backing for `Job.invokeOnCompletion` (via
/// `__kk_job_invoke_on_completion` in `Job.kt`). `handler`'s Kotlin type
/// `(Throwable?) -> Unit` crosses this bundled `external fun` boundary as a
/// (fnPtr, closureRaw) pair (it may capture locals) -- see
/// [[function-type-param-abi-split-convention]]. Registers it and returns a
/// disposal id for `__kk_job_dispose_handle` (0 if the handler
/// already ran inline because the job was already terminal).
@_cdecl("__kk_job_invoke_on_completion")
public func __kk_job_invoke_on_completion(
    _ jobHandle: Int,
    _ onCancelling: Int,
    _ invokeImmediately: Int,
    _ handlerFnPtr: Int,
    _ handlerClosureRaw: Int
) -> Int {
    guard let job = runtimeJobHandle(from: jobHandle) ?? runtimeAsyncTask(from: jobHandle)?.completionJob else {
        return 0
    }
    let capturedFnPtr = handlerFnPtr
    let capturedClosureRaw = handlerClosureRaw
    return job.addCompletionHandler(
        onCancelling: onCancelling != 0,
        invokeImmediately: invokeImmediately != 0
    ) { cause in
        guard capturedFnPtr != 0 else { return }
        _ = runtimeInvokeCollectionLambda1MaybeWrapped(
            fnPtr: capturedFnPtr,
            closureRaw: capturedClosureRaw,
            value: cause,
            outThrown: nil
        )
    }
}

/// KUU-CORO-101: ABI backing for the `DisposableHandle` returned by
/// `Job.invokeOnCompletion` (via `__kk_job_dispose_handle`).
@_cdecl("__kk_job_dispose_handle")
public func __kk_job_dispose_handle(_ jobHandle: Int, _ handlerID: Int) {
    let job = runtimeJobHandle(from: jobHandle) ?? runtimeAsyncTask(from: jobHandle)?.completionJob
    job?.removeCompletionHandler(id: handlerID)
}

@_cdecl("__kk_job_children")
public func __kk_job_children(_ jobHandle: Int) -> Int {
    let job = runtimeJobHandle(from: jobHandle) ?? runtimeAsyncTask(from: jobHandle)?.completionJob
    let children = (job?.childrenSnapshot() ?? []).map { handle in
        runtimeJobHandle(from: handle)?.sourceIdentityHandle ?? handle
    }
    return runtimeRegisterObject(RuntimeListBox(elements: children))
}

@_cdecl("__kk_job_parent")
public func __kk_job_parent(_ jobHandle: Int) -> Int {
    let job = runtimeJobHandle(from: jobHandle) ?? runtimeAsyncTask(from: jobHandle)?.completionJob
    guard let parent = job?.parentSnapshot() else {
        return runtimeNullSentinelInt
    }
    return parent.sourceIdentityHandle
}

// MARK: - KUU-1386: Job-family `is`/`as` recovery and @InternalCoroutinesApi bridges

/// Runtime box behind `Job.attachChild`'s ChildHandle result: a parent job +
/// the raw child handle that `dispose()` un-registers.
final class RuntimeChildHandleBox: @unchecked Sendable {
    /// nil parent == kotlinx's NonDisposableHandle (attachChild /
    /// invokeOnCompletion on a completed job): `parent` reads null, dispose()
    /// is a no-op, and childCancelled reports false (nothing was cancelled).
    let parent: RuntimeJobHandle?
    let childHandle: Int
    init(parent: RuntimeJobHandle?, childHandle: Int) {
        self.parent = parent
        self.childHandle = childHandle
    }
}

private func runtimeChildHandleBox(from rawValue: Int) -> RuntimeChildHandleBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: rawValue) else { return nil }
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer, let box = tryCast(ptr, to: RuntimeChildHandleBox.self) else { return nil }
    return box
}

/// KUU-1386: coroutine job-family handles (async tasks, job handles, child
/// handles) are raw runtime objects with no `kk_object_new` nominal tag, so
/// `kk_op_is`/`kk_op_cast` map them to the kotlinx class they answer
/// `is`/`as`/`as?` checks as: `async` results claim DeferredCoroutine
/// (AbstractCoroutine + Deferred), launch/produce results claim
/// AbstractCoroutine (StandaloneCoroutine's shape), bound factory jobs claim
/// their wrapper's nominal (CompletableJobImpl/CompletableDeferredImpl resolve
/// through real declared ancestry), unbound `Job()`/`SupervisorJob()` handles
/// claim JobImpl, and any other job handle claims AbstractCoroutine — the same
/// answer kotlinx gives for its internal coroutine jobs.
func runtimeJobFamilyNominalTypeID(rawValue: Int) -> Int64? {
    guard UnsafeMutableRawPointer(bitPattern: rawValue) != nil else { return nil }
    if let task = resolveLiveRuntimeHandle(rawValue, as: RuntimeAsyncTask.self) {
        return runtimeStableNominalTypeID(
            fqName: task.isDeferredResult
                ? "kotlinx.coroutines.DeferredCoroutine"
                : "kotlinx.coroutines.AbstractCoroutine"
        )
    }
    if let job = resolveLiveRuntimeHandle(rawValue, as: RuntimeJobHandle.self) {
        if job === runtimeNonCancellableJob {
            return runtimeStableNominalTypeID(fqName: "kotlinx.coroutines.NonCancellable")
        }
        return job.nominalJobTypeID != 0
            ? job.nominalJobTypeID
            : runtimeStableNominalTypeID(fqName: "kotlinx.coroutines.AbstractCoroutine")
    }
    if runtimeChildHandleBox(from: rawValue) != nil {
        return runtimeStableNominalTypeID(fqName: "kotlinx.coroutines.ChildHandle")
    }
    return nil
}

/// KUU-1352: kotlinx `JobSupport.toString()` — `"<name>{<state>}@<hex>"`.
/// Resolves raw `RuntimeJobHandle`/`RuntimeAsyncTask` handles through the
/// liveness registry: job handles reached via `coroutineContext.job` and
/// `launch`/`async` results are not GC-registered object pointers, so the
/// generic renderers must consult this before their `isObjectPointer` gate.
/// Returns nil for values that are not live job-family handles so the
/// existing numeric fallback still applies.
func runtimeJobHandleDebugString(_ rawValue: Int) -> String? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: rawValue),
          let live = RuntimeLiveHandles.resolve(ptr)
    else { return nil }
    let job: RuntimeJobHandle
    if let task = live as? RuntimeAsyncTask {
        job = task.completionJob
    } else if let jobHandle = live as? RuntimeJobHandle {
        job = jobHandle
    } else {
        return nil
    }
    // kotlinx's `object NonCancellable : Job` overrides toString to a bare name.
    if job === runtimeNonCancellableJob {
        return "NonCancellable"
    }
    return runtimeJobDebugString(job)
}

/// KUU-1352: the wrapper half of `runtimeJobHandleDebugString` — a bound
/// `RuntimeObjectBox` (`Job()`, `SupervisorJob()`, `CompletableDeferred`, a
/// `JobSupport` subclass instance) renders through its job's debug string.
/// Callers must invoke this AFTER their `runtimeAnyToStringOverride` check so
/// a `toString()` explicitly declared on a JobSupport subclass still wins,
/// matching kotlinx dispatch.
func runtimeJobWrapperDebugString(_ rawValue: Int) -> String? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: rawValue) else { return nil }
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer,
          let box = tryCast(ptr, to: RuntimeObjectBox.self),
          case .job(let job) = RuntimeJobOrTask(box)
    else { return nil }
    if job === runtimeNonCancellableJob {
        return "NonCancellable"
    }
    return runtimeJobDebugString(job)
}

private func runtimeJobDebugString(_ job: RuntimeJobHandle) -> String {
    "\(runtimeJobToStringName(job)){\(job.toStringStateName())}@\(String(job.sourceIdentityHandle, radix: 16))"
}

/// KUU-1352: the `nameString()` half of kotlinx's `toDebugString()`. Bound
/// wrapper jobs take their wrapper class's simple name (kotlinx's
/// `classSimpleName`) — except `CompletableJobImpl`, the bundled `Job()`/
/// `SupervisorJob()` wrapper, which upstream renders as `JobImpl`/
/// `SupervisorJobImpl`. Raw handles minted by the launch/async/runBlocking/
/// produce launchers carry their kotlinx class name in `debugName`.
private func runtimeJobToStringName(_ job: RuntimeJobHandle) -> String {
    let nominalID = job.nominalJobTypeID
    if nominalID == runtimeStableNominalTypeID(fqName: "kotlinx.coroutines.CompletableJobImpl")
        || nominalID == runtimeStableNominalTypeID(fqName: "kotlinx.coroutines.JobImpl")
    {
        return job.isSupervisorMarker ? "SupervisorJobImpl" : "JobImpl"
    }
    if nominalID == runtimeStableNominalTypeID(fqName: "kotlinx.coroutines.CompletableDeferredImpl") {
        return "CompletableDeferredImpl"
    }
    if nominalID != 0, let name = runtimeNominalSimpleName(nominalID) {
        return name
    }
    return job.debugName ?? "JobImpl"
}

/// The metadata simple name for a stable nominal class ID, when the class's
/// `__kk_kclass_register_metadata` entry exists (user-defined JobSupport
/// subclasses render under their own name).
private func runtimeNominalSimpleName(_ nominalID: Int64) -> String? {
    let typeToken = Int(
        (nominalID & RuntimeTypeTokenEncoding.payloadMask) << RuntimeTypeTokenEncoding.payloadShift
            | RuntimeTypeTokenEncoding.nominalBase
    )
    return runtimeKClassMetadataRegistry.lookup(typeToken: typeToken)?.simpleName
}

/// Registers the job-family nominal hierarchy edges once (mirrors
/// `registerRangeTypeEdgesOnce`/`kk_non_cancellable_instance`): covers every
/// class the job-family recovery above can claim, plus the interfaces between
/// them and CoroutineContext.Element so `is` checks keep matching kotlinx.
func registerJobFamilyTypeEdgesOnce() {
    runtimeStorage.withMetadataLock { state in
        if state.jobFamilyTypeEdgesRegistered { return }
        func nominalID(_ fqName: String) -> Int64 { runtimeStableNominalTypeID(fqName: fqName) }
        let job = nominalID("kotlinx.coroutines.Job")
        let jobSupport = nominalID("kotlinx.coroutines.JobSupport")
        let abstractCoroutine = nominalID("kotlinx.coroutines.AbstractCoroutine")
        let deferredCoroutine = nominalID("kotlinx.coroutines.DeferredCoroutine")
        let jobImpl = nominalID("kotlinx.coroutines.JobImpl")
        let completableJob = nominalID("kotlinx.coroutines.CompletableJob")
        let deferred = nominalID("kotlinx.coroutines.Deferred")
        let completableDeferred = nominalID("kotlinx.coroutines.CompletableDeferred")
        let childJob = nominalID("kotlinx.coroutines.ChildJob")
        let parentJob = nominalID("kotlinx.coroutines.ParentJob")
        let completableJobImpl = nominalID("kotlinx.coroutines.CompletableJobImpl")
        let completableDeferredImpl = nominalID("kotlinx.coroutines.CompletableDeferredImpl")
        let childHandle = nominalID("kotlinx.coroutines.ChildHandle")
        let disposableHandle = nominalID("kotlinx.coroutines.DisposableHandle")
        let element = nominalID("kotlin.coroutines.CoroutineContext.Element")
        let context = nominalID("kotlin.coroutines.CoroutineContext")
        let continuation = nominalID("kotlin.coroutines.Continuation")
        let coroutineScope = nominalID("kotlinx.coroutines.CoroutineScope")
        for (child, parent) in [
            (abstractCoroutine, jobSupport), (abstractCoroutine, coroutineScope),
            (abstractCoroutine, continuation),
            (deferredCoroutine, abstractCoroutine), (deferredCoroutine, deferred),
            (jobImpl, jobSupport), (jobImpl, completableJob),
            (completableJobImpl, jobImpl), (completableDeferredImpl, jobSupport),
            (completableDeferredImpl, completableDeferred),
            (jobSupport, job), (jobSupport, childJob), (jobSupport, parentJob),
            (childJob, job), (parentJob, job),
            (completableJob, job), (deferred, job), (completableDeferred, deferred),
            (childHandle, disposableHandle),
            (job, element), (element, context),
        ] {
            state.typeParents[child, default: []].insert(parent)
        }
        state.jobFamilyTypeEdgesRegistered = true
    }
}

/// KUU-1386: `JobSupport.initParentJob` backing — attach a job to its parent
/// through the runtime so `job.parent`, children tracking and failure
/// propagation behave like kotlinx's JobImpl(parent). Idempotent: a job
/// already attached to that parent is left alone.
@_cdecl("__kk_job_attach_to_parent")
public func __kk_job_attach_to_parent(_ jobHandle: Int, _ parentHandle: Int) -> Int {
    guard let child = runtimeJobHandle(from: jobHandle)
        ?? runtimeAsyncTask(from: jobHandle)?.completionJob,
        let parent = runtimeJobHandle(from: parentHandle)
            ?? runtimeAsyncTask(from: parentHandle)?.completionJob
    else { return jobHandle }
    guard child.parentSnapshot() !== parent else { return jobHandle }
    // registerChild sets parentJob on the child, and RuntimeJobHandle already
    // propagates non-supervisor child failures upward through childFailed —
    // matching kotlinx's JobImpl(parent) propagation without a second path.
    parent.registerChild(Int(bitPattern: Unmanaged.passUnretained(child).toOpaque()))
    return jobHandle
}

/// KUU-1386: `Job.key` backing — returns the Job.Key singleton (`kk_job_key`)
/// so `job.key == Job` is true like kotlinx, while `ctx[job.key]` resolves the
/// stored job through the singleton-key rule in kk_context_get.
@_cdecl("kk_job_key_get")
public func kk_job_key_get(_ receiver: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: receiver) else {
        return runtimeNullSentinelInt
    }
    let object = Unmanaged<AnyObject>.fromOpaque(ptr).takeUnretainedValue()
    // Bound JobImpl/CompletableDeferred wrapper boxes unwrap through
    // RuntimeJobOrTask just like raw job/task handles.
    switch RuntimeJobOrTask(object) {
    case .job, .task:
        return kk_job_key()
    case .other:
        // Source Job implementers that never bound a runtime job — e.g.
        // `Job by Job()` delegation, where `super<Job>.key` lands here — still
        // answer the interface's `key` contract: `Job.key` is `Job.Key`.
        if let sourceID = runtimeObjectTypeID(rawValue: receiver),
           runtimeIsAssignable(
               sourceTypeID: sourceID,
               targetTypeID: runtimeStableNominalTypeID(fqName: "kotlinx.coroutines.Job")
           )
        {
            return kk_job_key()
        }
        return runtimeNullSentinelInt
    }
}

/// KUU-1386: kotlinx `ParentJob.getChildJobCancellationCause` — a Finishing
/// job's rootCause or a CompletedExceptionally cause (wrapped in a
/// CancellationException when the stored cause is not one), and a reported
/// error for a still-active (Incomplete) job or one that completed normally
/// without a cause.
private func runtimeChildJobCancellationCause(of job: RuntimeJobHandle) -> (cause: Int, error: Int) {
    let cause = job.cancellationCauseSnapshot()
    if cause != 0, cause != runtimeNullSentinelInt {
        if kk_is_cancellation_exception(cause) != 0 {
            return (cause, 0)
        }
        return (runtimeAllocateCancellationException(
            message: "Parent job is Cancelling", cause: cause), 0)
    }
    if !job.completedSnapshot() {
        return (0, runtimeAllocateIllegalStateException(
            message: "Cannot be cancelling child in this state"))
    }
    return (runtimeAllocateCancellationException(message: "Parent job is completed"), 0)
}

/// KUU-1386: `ParentJob.getChildJobCancellationCause()` backing — throwing
/// bridge (outThrown channel) matching kotlinx's IllegalStateException on an
/// active job.
@_cdecl("kk_job_get_child_cancellation_cause")
public func kk_job_get_child_cancellation_cause(
    _ jobHandle: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let job = runtimeJobHandle(from: jobHandle)
        ?? runtimeAsyncTask(from: jobHandle)?.completionJob else {
        outThrown?.pointee = runtimeAllocateIllegalStateException(
            message: "Cannot be cancelling child in this state")
        return 0
    }
    let (cause, error) = runtimeChildJobCancellationCause(of: job)
    if error != 0 {
        outThrown?.pointee = error
        return 0
    }
    return cause
}

/// KUU-1386: `ChildJob.parentCancelled(parentJob)` backing — kotlinx's
/// JobSupport implementation is `cancelImpl(parentJob)`, which resolves the
/// cancellation cause lazily through `ParentJob.getChildJobCancellationCause`
/// — an active parent therefore throws IllegalStateException before the child
/// is cancelled.
@_cdecl("kk_job_parent_cancelled")
public func kk_job_parent_cancelled(
    _ jobHandle: Int,
    _ parentHandle: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let parentJob = runtimeJobHandle(from: parentHandle)
        ?? runtimeAsyncTask(from: parentHandle)?.completionJob else {
        outThrown?.pointee = runtimeAllocateIllegalStateException(
            message: "Cannot be cancelling child in this state")
        return 0
    }
    let (cause, error) = runtimeChildJobCancellationCause(of: parentJob)
    if error != 0 {
        outThrown?.pointee = error
        return 0
    }
    guard let ptr = UnsafeMutableRawPointer(bitPattern: jobHandle) else { return 0 }
    let object = Unmanaged<AnyObject>.fromOpaque(ptr).takeUnretainedValue()
    switch RuntimeJobOrTask(object) {
    case .job(let job):
        if job !== runtimeNonCancellableJob {
            _ = job.cancel(message: "Parent job is cancelled", cause: cause)
        }
    case .task(let task):
        task.cancel(cause: cause)
    case .other:
        break
    }
    return 0
}

/// KUU-1386: kotlinx `JobImpl.handlesException` — a JobImpl never handles its
/// own failures; it reports true only when its `parentHandle` chain reaches a
/// job that does (a JobSupport whose own handlesException is true). Runtime
/// equivalent: walk `parentJob` — a real coroutine job (nominal 0, the
/// StandaloneCoroutine/AbstractCoroutine claim) is a handler, while
/// JobImpl-family factory jobs and bound wrappers (Job()/SupervisorJob()/
/// CompletableDeferred()) delegate upward.
private func runtimeJobHandlesException(_ job: RuntimeJobHandle) -> Bool {
    var cur = job.parentSnapshot()
    while let parent = cur {
        if parent.nominalJobTypeID == 0 { return true }
        cur = parent.parentSnapshot()
    }
    return false
}

/// KUU-1386: `JobSupport.childCancelled(cause)` backing — kotlinx semantics:
/// a CancellationException reports as already-handled without touching the
/// job; otherwise cancelImpl transitions the job to cancelling and synchronously
/// notifies its parent. The result is `handlesException`, so a root `Job()`
/// reports false even though it did cancel, while a job parented to a coroutine
/// reports true.
@_cdecl("kk_job_child_cancelled")
public func kk_job_child_cancelled(_ jobHandle: Int, _ cause: Int) -> Int {
    if cause != 0, cause != runtimeNullSentinelInt,
       kk_is_cancellation_exception(cause) != 0 {
        return 1
    }
    guard let ptr = UnsafeMutableRawPointer(bitPattern: jobHandle) else { return 0 }
    let object = Unmanaged<AnyObject>.fromOpaque(ptr).takeUnretainedValue()
    switch RuntimeJobOrTask(object) {
    case .job(let job):
        guard job !== runtimeNonCancellableJob else { return 0 }
        // `handlesException` is evaluated before the transition: a completed
        // job's parent handle reads as detached, so check the parent first.
        let parent = job.parentSnapshot()
        let handlesException = runtimeJobHandlesException(job)
        guard job.cancel(cause: cause) else { return 0 }
        parent?.childFailed(with: cause)
        return handlesException ? 1 : 0
    case .task(let task):
        let completionJob = task.completionJob
        let parent = completionJob.parentSnapshot()
        let handlesException = runtimeJobHandlesException(completionJob)
        task.cancel(cause: cause)
        parent?.childFailed(with: cause)
        return handlesException ? 1 : 0
    case .other:
        return 0
    }
}

/// KUU-1386: `Job.attachChild(child)` backing — register the child and hand
/// back a ChildHandle box whose `dispose()` removes that registration. On an
/// already-completed job kotlinx's invokeOnCompletion yields
/// NonDisposableHandle instead: a dead handle with `parent == null`.
@_cdecl("kk_job_attach_child")
public func kk_job_attach_child(_ jobHandle: Int, _ childHandle: Int) -> Int {
    guard let parent = runtimeJobHandle(from: jobHandle)
        ?? runtimeAsyncTask(from: jobHandle)?.completionJob
    else { return 0 }
    if parent.completedSnapshot() {
        return runtimeRegisterObject(
            RuntimeChildHandleBox(parent: nil, childHandle: childHandle))
    }
    parent.registerChild(childHandle)
    return runtimeRegisterObject(RuntimeChildHandleBox(parent: parent, childHandle: childHandle))
}

@_cdecl("kk_child_handle_parent")
public func kk_child_handle_parent(_ handleRaw: Int) -> Int {
    guard let box = runtimeChildHandleBox(from: handleRaw) else { return runtimeNullSentinelInt }
    return box.parent?.sourceIdentityHandle ?? runtimeNullSentinelInt
}

@_cdecl("kk_child_handle_dispose")
public func kk_child_handle_dispose(_ handleRaw: Int) -> Int {
    guard let box = runtimeChildHandleBox(from: handleRaw) else { return 0 }
    box.parent?.detachChild(box.childHandle)
    return 0
}

@_cdecl("kk_child_handle_child_cancelled")
public func kk_child_handle_child_cancelled(_ handleRaw: Int, _ cause: Int) -> Int {
    guard let box = runtimeChildHandleBox(from: handleRaw), let parent = box.parent else {
        return 0
    }
    // kotlinx's ChildHandle delegates to the parent's JobSupport.childCancelled.
    return kk_job_child_cancelled(
        Int(bitPattern: Unmanaged.passUnretained(parent).toOpaque()),
        cause
    )
}

/// Check if the coroutine associated with `continuation` has been cancelled.
/// If cancelled, allocates a CancellationException, writes it to `outThrown`,
/// and returns 1. Otherwise returns 0 with outThrown untouched.
@_cdecl("kk_coroutine_check_cancellation")
public func kk_coroutine_check_cancellation(_ continuation: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let state = runtimeContinuationState(from: continuation) else {
        return 0
    }
    if let job = state.jobHandle, job.cancellationSnapshot() {
        let cancellation = runtimeAllocateCancellationException(
            message: job.cancellationMessageSnapshot(forSuspensionPoint: true),
            cause: job.cancellationCauseSnapshot()
        )
        outThrown?.pointee = cancellation
        return 1
    }
    // Fallback: if there is no job handle but the scope has been cancelled
    // (e.g. via scope.cancel()), still observe the cancellation.  This
    // provides a safety net for execution contexts that lack a job handle.
    if state.jobHandle == nil, let scope = state.scope, scope.isCancelled {
        let cancellation = runtimeAllocateCancellationException(
            message: scope.cancellationMessage, cause: scope.cancellationCause)
        outThrown?.pointee = cancellation
        return 1
    }
    return 0
}

/// Directly cancel a continuation (sets isCancelled on its linked job handle).
public func kk_coroutine_cancel(_ continuation: Int) {
    guard let state = runtimeContinuationState(from: continuation),
          let job = state.jobHandle
    else {
        return
    }
    _ = job.cancel()
}

/// Cancel the currently running coroutine without requiring a continuation handle.
@_cdecl("kk_coroutine_cancel_current")
public func kk_coroutine_cancel_current(_ message: Int, _ causeRaw: Int) -> Int {
    let text = extractString(from: UnsafeMutableRawPointer(bitPattern: message)) ?? "CancellationException"
    let normalizedCause = (causeRaw == runtimeNullSentinelInt || causeRaw == 0) ? 0 : causeRaw
    guard let state = RuntimeContinuationState.current else {
        return 0
    }
    if let job = state.jobHandle {
        _ = job.cancel(message: text, cause: normalizedCause)
    } else if let scope = state.scope {
        scope.cancel(message: text, cause: normalizedCause)
    }
    return 0
}

/// Returns 1 if the given throwable raw pointer is a CancellationException, 0 otherwise.
@_cdecl("kk_is_cancellation_exception")
public func kk_is_cancellation_exception(_ throwableRaw: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: throwableRaw) else {
        return 0
    }
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return 0
    }
    let obj = Unmanaged<AnyObject>.fromOpaque(ptr).takeUnretainedValue()
    return obj is RuntimeCancellationBox ? 1 : 0
}

/// Throws a CancellationException if the ambient job/scope has been cancelled.
/// Lowering target for the bare (no-receiver) `kotlinx.coroutines.ensureActive()`.
/// Mirrors `kk_coroutine_check_cancellation`'s two checks (job, then scope fallback),
/// but reads the ambient current job/scope directly since this call carries no
/// continuation handle of its own.
@_cdecl("kk_ensure_active")
public func kk_ensure_active(_ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    if let job = RuntimeJobHandle.current, job.cancellationSnapshot() {
        outThrown?.pointee = runtimeAllocateCancellationException(
            message: job.cancellationMessageSnapshot(forSuspensionPoint: true),
            cause: job.cancellationCauseSnapshot()
        )
        return 0
    }
    if RuntimeJobHandle.current == nil, let scope = RuntimeCoroutineScope.current, scope.isCancelled {
        outThrown?.pointee = runtimeAllocateCancellationException(
            message: scope.cancellationMessage, cause: scope.cancellationCause
        )
        return 0
    }
    return 0
}

/// Singleton backing `kotlinx.coroutines.NonCancellable`. A `RuntimeJobHandle` that
/// is never cancelled. `withContext(NonCancellable)` instead creates its own
/// block Job, detached from the enclosing Job's cancellation.
let runtimeNonCancellableJob: RuntimeJobHandle = {
    let job = RuntimeJobHandle()
    job.markStarted()
    return job
}()

@_cdecl("kk_non_cancellable_instance")
public func kk_non_cancellable_instance() -> Int {
    // Unlike `runtimeRegisterObject` (which does `passRetained`, appropriate for a
    // freshly-created object), this must not take a new retain on every call: the
    // module-level `let` above already keeps `runtimeNonCancellableJob` alive for the
    // process lifetime, so repeatedly retaining it here would leak one reference per
    // `withContext(NonCancellable)` call. `passUnretained` registers the same pointer
    // (the `objectPointers` insert is idempotent) without incrementing the refcount.
    let ptr = UnsafeMutableRawPointer(Unmanaged.passUnretained(runtimeNonCancellableJob).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
        state.borrowedObjectPointers.insert(UInt(bitPattern: ptr))
    }
    let nonCancellableID = runtimeStableNominalTypeID(fqName: "kotlinx.coroutines.NonCancellable")
    let jobID = runtimeStableNominalTypeID(fqName: "kotlinx.coroutines.Job")
    let abstractElementID = runtimeStableNominalTypeID(fqName: "kotlin.coroutines.AbstractCoroutineContextElement")
    let elementID = runtimeStableNominalTypeID(fqName: "kotlin.coroutines.CoroutineContext.Element")
    let contextID = runtimeStableNominalTypeID(fqName: "kotlin.coroutines.CoroutineContext")
    runtimeStorage.withMetadataLock { state in
        state.objectTypeByPointer[UInt(bitPattern: ptr)] = nonCancellableID
        state.typeParents[nonCancellableID, default: []].formUnion([jobID, abstractElementID])
        state.typeParents[jobID, default: []].insert(elementID)
        state.typeParents[abstractElementID, default: []].insert(elementID)
        state.typeParents[elementID, default: []].insert(contextID)
    }
    return Int(bitPattern: ptr)
}

@_cdecl("kk_await_cancellation")
public func kk_await_cancellation(_ continuation: Int) -> Int {
    let parked = RuntimeCancellableContinuation(delegate: continuation)
    parked.initParent()
    var thrown = 0
    let result = parked.getResult(&thrown)
    if thrown != 0, let state = runtimeContinuationState(from: continuation) {
        // This ABI has no outThrown slot; deliver already-pending cancellation
        // through the same resume path as cancellation after suspension.
        _ = state.resume(withException: thrown)
        return Int(bitPattern: kk_coroutine_suspended())
    }
    return result
}
