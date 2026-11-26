import Dispatch
import Foundation

@_cdecl("kk_job_new")
public func kk_job_new() -> Int {
    let job = RuntimeJobHandle()
    job.markStarted()
    job.nominalJobTypeID = runtimeStableNominalTypeID(fqName: "kotlinx.coroutines.JobImpl")
    return runtimeRegisterObject(job)
}

@_cdecl("__kk_job_bind_wrapper")
public func __kk_job_bind_wrapper(_ wrapperRaw: Int, _ jobRaw: Int, _ parentRaw: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: wrapperRaw),
          let wrapper = tryCast(ptr, to: RuntimeObjectBox.self),
          let job = runtimeJobHandle(from: jobRaw)
    else { return jobRaw }
    let sourceID = runtimeObjectTypeID(rawValue: wrapperRaw) ?? 0
    let (boundRaw, boundJob) = wrapper.withCoroutineJobHandle { current -> (Int, RuntimeJobHandle) in
        if current != 0, let existing = resolveLiveRuntimeHandle(current, as: RuntimeJobHandle.self) {
            return (current, existing)
        }
        job.markBodyless()
        job.bindSourceWrapper(wrapper)
        job.nominalJobTypeID = sourceID
        current = jobRaw
        return (jobRaw, job)
    }
    if let parent = runtimeJobHandle(from: parentRaw) {
        parent.registerChild(boundRaw)
        if !parent.isSupervisorMarker {
            _ = boundJob.addCompletionHandler(onCancelling: false) { cause in
                if cause != runtimeNullSentinelInt, boundJob.isFailedSnapshot(),
                   !runtimeCoroutineIsCancellationResult(cause)
                {
                    _ = parent.cancel(cause: cause)
                }
            }
        }
    }
    return boundRaw
}

private func deferredCompletionSnapshot(_ handle: Int, handoff: RuntimeCompletionHandoff) -> (completed: Bool, value: Int, exception: Int) {
    if let job = runtimeJobHandle(from: handle) { return job.completionSnapshot(handoff: handoff) }
    if let task = runtimeAsyncTask(from: handle) { return task.completionSnapshot(handoff: handoff) }
    return (false, 0, 0)
}

@_cdecl("__kk_deferred_get_completed")
public func __kk_deferred_get_completed(_ handle: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    return runtimeThrowingBridge(outThrown) {
        return runtimeThrowingBridge(outThrown) {
            let snapshot = deferredCompletionSnapshot(handle, handoff: .valueOrExceptionWhenCompleted)
            guard snapshot.completed else {
                outThrown?.pointee = runtimeAllocateIllegalStateException(message: "This job has not completed yet")
                return 0
            }
            outThrown?.pointee = snapshot.exception
            return snapshot.exception == 0 ? snapshot.value : 0
        }
    }
}

@_cdecl("__kk_deferred_completion_exception")
public func __kk_deferred_completion_exception(_ handle: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    return runtimeThrowingBridge(outThrown) {
        return runtimeThrowingBridge(outThrown) {
            let snapshot = deferredCompletionSnapshot(handle, handoff: .exceptionWhenCompleted)
            guard snapshot.completed else {
                outThrown?.pointee = runtimeAllocateIllegalStateException(message: "This job has not completed yet")
                return runtimeNullSentinelInt
            }
            return snapshot.exception == 0 ? runtimeNullSentinelInt : snapshot.exception
        }
    }
}

@_cdecl("kk_supervisor_job_new")
public func kk_supervisor_job_new() -> Int {
    let job = RuntimeJobHandle()
    job.isSupervisorMarker = true
    job.markStarted()
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

@_cdecl("kk_job_join")
public func kk_job_join(
    _ jobHandle: Int,
    _ continuation: Int,
    _ outThrown: UnsafeMutablePointer<Int>? = nil
) -> Int {
    return runtimeThrowingBridge(outThrown) {
        return runtimeThrowingBridge(outThrown) {
            if runtimeJobHandle(from: jobHandle) === runtimeNonCancellableJob {
                outThrown?.pointee = runtimeAllocateUnsupportedOperationException(message: "This job is always active")
                return 0
            }
            return runtimeJoinJob(jobHandle, continuation)
        }
    }
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
    return result
}

@_cdecl("kk_job_await_completion")
public func kk_job_await_completion(
    _ jobHandle: Int,
    _ continuation: Int,
    _ outThrown: UnsafeMutablePointer<Int>? = nil
) -> Int {
    kk_job_join(jobHandle, continuation, outThrown)
}


func runtimeCancelChild(_ handle: Int, cause: Int = 0) {
    // Completed children can have been released by their scope while an
    // ancestor still holds the raw hierarchy entry. Resolve liveness first.
    if let job = runtimeJobHandle(from: handle) {
        _ = job.cancel(cause: cause)
    } else if let task = runtimeAsyncTask(from: handle) {
        task.cancel(cause: cause)
    }
}

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

@_cdecl("kk_context_cancel_no_cause")
public func kk_context_cancel_no_cause(_ contextRaw: Int) -> Int {
    kk_context_cancel(contextRaw, 0)
}

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

@_cdecl("kk_coroutine_current_scope")
public func kk_coroutine_current_scope() -> Int {
    if let state = RuntimeContinuationState.current {
        if let scope = state.scope ?? RuntimeCoroutineScope.current {
            state.scope = scope
            return Int(bitPattern: UnsafeMutableRawPointer(Unmanaged.passUnretained(scope).toOpaque()))
        }

        let scope = RuntimeCoroutineScope(context: state.makeContinuationContext())
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

@_cdecl("kk_job_is_completed")
public func kk_job_is_completed(_ jobHandle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: jobHandle) else {
        return 1
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

@_cdecl("kk_job_is_cancelled")
public func kk_job_is_cancelled(_ jobHandle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: jobHandle) else {
        return 1
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

public func kk_job_is_failed(_ jobHandle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: jobHandle) else {
        return 0
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

@_cdecl("kk_job_get_cancellation_exception")
public func kk_job_get_cancellation_exception(_ jobHandle: Int) -> Int {
    guard let job = runtimeJobHandle(from: jobHandle)
        ?? runtimeAsyncTask(from: jobHandle)?.completionJob
    else {
        return runtimeAllocateCancellationException(message: "Job is still active")
    }
    return runtimeJobCancellationException(job)
}

func runtimeCancellationExceptionPreservingCause(
    message: String, cause: Int, cancellationJob: RuntimeJobHandle? = nil
) -> Int {
    let normalized = cause == runtimeNullSentinelInt ? 0 : cause
    if normalized != 0, kk_is_cancellation_exception(normalized) != 0 { return normalized }
    return runtimeAllocateCancellationException(
        message: message, cause: normalized, cancellationJob: cancellationJob)
}

func runtimeJobCancellationException(_ job: RuntimeJobHandle) -> Int {
    // The existing nonthrowing getter ABI cannot report the upstream active
    // Job IllegalStateException. Keep its fallback until that ABI is revised.
    if !job.cancellationSnapshot(), !job.isFailedSnapshot() {
        return runtimeAllocateCancellationException(message: "Job is still active")
    }
    let snapshot = job.cancellationExceptionSnapshot()
    return runtimeCancellationExceptionPreservingCause(
        message: snapshot.message, cause: snapshot.cause, cancellationJob: job)
}

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

func runtimeJobDebugString(_ job: RuntimeJobHandle) -> String {
    "\(runtimeJobToStringName(job)){\(job.toStringStateName())}@\(String(job.sourceIdentityHandle, radix: 16))"
}

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

private func runtimeNominalSimpleName(_ nominalID: Int64) -> String? {
    let typeToken = Int(
        (nominalID & RuntimeTypeTokenEncoding.payloadMask) << RuntimeTypeTokenEncoding.payloadShift
            | RuntimeTypeTokenEncoding.nominalBase
    )
    return runtimeKClassMetadataRegistry.lookup(typeToken: typeToken)?.simpleName
}

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

@_cdecl("__kk_job_attach_to_parent")
public func __kk_job_attach_to_parent(_ jobHandle: Int, _ parentHandle: Int) -> Int {
    guard let child = runtimeJobHandle(from: jobHandle)
        ?? runtimeAsyncTask(from: jobHandle)?.completionJob,
        let parent = runtimeJobHandle(from: parentHandle)
            ?? runtimeAsyncTask(from: parentHandle)?.completionJob
    else { return jobHandle }
    guard child.parentSnapshot() !== parent else { return jobHandle }
    parent.registerChild(Int(bitPattern: Unmanaged.passUnretained(child).toOpaque()))
    return jobHandle
}

@_cdecl("kk_job_key_get")
public func kk_job_key_get(_ receiver: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: receiver) else {
        return runtimeNullSentinelInt
    }
    let object = Unmanaged<AnyObject>.fromOpaque(ptr).takeUnretainedValue()
    switch RuntimeJobOrTask(object) {
    case .job, .task:
        return kk_job_key()
    case .other:
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

@_cdecl("kk_job_get_child_cancellation_cause")
public func kk_job_get_child_cancellation_cause(
    _ jobHandle: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    return runtimeThrowingBridge(outThrown) {
        return runtimeThrowingBridge(outThrown) {
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
    }
}

@_cdecl("kk_job_parent_cancelled")
public func kk_job_parent_cancelled(
    _ jobHandle: Int,
    _ parentHandle: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    return runtimeThrowingBridge(outThrown) {
        return runtimeThrowingBridge(outThrown) {
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
    }
}

private func runtimeJobHandlesException(_ job: RuntimeJobHandle) -> Bool {
    var cur = job.parentSnapshot()
    while let parent = cur {
        if parent.nominalJobTypeID == 0 { return true }
        cur = parent.parentSnapshot()
    }
    return false
}

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
    return kk_job_child_cancelled(
        Int(bitPattern: Unmanaged.passUnretained(parent).toOpaque()),
        cause
    )
}

@_cdecl("kk_coroutine_check_cancellation")
public func kk_coroutine_check_cancellation(_ continuation: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let state = runtimeContinuationState(from: continuation) else {
        return 0
    }
    if let job = state.jobHandle, job.cancellationSnapshot() || job.isFailedSnapshot() {
        let cancellation = runtimeJobCancellationException(job)
        outThrown?.pointee = cancellation
        return 1
    }
    if state.jobHandle == nil, let scope = state.scope, scope.isCancelled {
        let cancellation = runtimeCancellationExceptionPreservingCause(
            message: scope.cancellationMessage, cause: scope.cancellationCause)
        outThrown?.pointee = cancellation
        return 1
    }
    return 0
}

public func kk_coroutine_cancel(_ continuation: Int) {
    guard let state = runtimeContinuationState(from: continuation),
          let job = state.jobHandle
    else {
        return
    }
    _ = job.cancel()
}

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
    if tryCast(ptr, to: RuntimeCancellationBox.self) != nil { return 1 }
    guard let object = tryCast(ptr, to: RuntimeObjectBox.self) else { return 0 }
    return runtimeIsAssignable(
        sourceTypeID: object.classID,
        targetTypeID: runtimeStableNominalTypeID(fqName: "kotlin.coroutines.cancellation.CancellationException")
    ) ? 1 : 0
}

@_cdecl("kk_ensure_active")
public func kk_ensure_active(_ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    if let job = RuntimeJobHandle.current, job.cancellationSnapshot() || job.isFailedSnapshot() {
        outThrown?.pointee = runtimeJobCancellationException(job)
        return 0
    }
    if RuntimeJobHandle.current == nil, let scope = RuntimeCoroutineScope.current, scope.isCancelled {
        outThrown?.pointee = runtimeCancellationExceptionPreservingCause(
            message: scope.cancellationMessage, cause: scope.cancellationCause
        )
        return 0
    }
    return 0
}

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
        _ = state.resume(withException: thrown)
        return Int(bitPattern: kk_coroutine_suspended())
    }
    return result
}
