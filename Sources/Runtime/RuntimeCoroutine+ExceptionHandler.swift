import Dispatch
import Foundation

// MARK: - CoroutineExceptionHandler (STDLIB-CORO-072)

/// A heap-allocated box holding a Swift closure that acts as a CoroutineExceptionHandler.
/// The closure receives the raw CoroutineContext and throwable pointers and
/// handles them, mirroring `CoroutineExceptionHandler.handleException(context,
/// exception)`.
final class RuntimeExceptionHandlerBox: @unchecked Sendable {
    let handler: @Sendable (Int, Int) -> Void
    init(handler: @escaping @Sendable (Int, Int) -> Void) {
        self.handler = handler
    }
}

/// Create a CoroutineExceptionHandler that prints the exception message.
/// Returns an opaque handle to a RuntimeExceptionHandlerBox.
public func kk_exception_handler_new() -> Int {
    let box = RuntimeExceptionHandlerBox { _, throwableRaw in
        // Default handler: print the exception to stderr
        var message = "Unknown exception"
        if throwableRaw != 0, let ptr = UnsafeMutableRawPointer(bitPattern: throwableRaw) {
            if let throwable = tryCast(ptr, to: RuntimeThrowableBox.self) {
                message = throwable.message ?? "Throwable"
            } else if let cancellation = tryCast(ptr, to: RuntimeCancellationBox.self) {
                message = cancellation.message ?? "CancellationException"
            }
        }
        FileHandle.standardError.write(Data("CoroutineExceptionHandler: \(message)\n".utf8))
    }
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

/// kotlinx `handleCoroutineException` for a failed fire-and-forget `launch`
/// coroutine whose failure no parent absorbed (unparented job or supervisor
/// parent). A CoroutineExceptionHandler installed in the coroutine's context
/// consumes the failure. With no handler, mirror the JVM default path — the
/// thread's uncaughtException handler — which writes
/// `Exception in thread "<name>" <throwable.toString()>` plus stack frames to
/// stderr and lets the process continue (JVM exits 0 for supervisor/absent
/// parents; only exceptions propagating out of `main` exit non-zero, and that
/// case reaches the KSWIFTK-LINK-0003 panic instead of this helper).
///
/// KUU-1422: previously this fallback just printed `CoroutineExceptionHandler:
/// <message>`, which looked like routine handled output and swallowed the
/// exception type and stack — uncaught failures were easy to miss entirely.
func runtimeHandleUncaughtCoroutineException(
    context: RuntimeCoroutineContext?,
    exception exceptionRaw: Int
) {
    // A thrown CancellationException is cancellation, not a reportable failure
    // (kotlinx filters it before handleCoroutineException as well).
    guard exceptionRaw != 0, exceptionRaw != runtimeNullSentinelInt,
          !runtimeCoroutineIsCancellationResult(exceptionRaw)
    else { return }
    if let context, let handler = context.exceptionHandler {
        handler.handler(runtimeRegisterObject(context), exceptionRaw)
        return
    }
    let threadName: String
    if Thread.isMainThread {
        threadName = "main"
    } else if let name = Thread.current.name, !name.isEmpty {
        threadName = name
    } else {
        threadName = "coroutine"
    }
    var lines: [String] = []
    runtimeUncaughtThrowableLines(
        from: exceptionRaw, prefix: nil, into: &lines, depth: 0
    )
    guard let header = lines.first else {
        FileHandle.standardError.write(
            Data("Exception in thread \"\(threadName)\" kotlin.Throwable\n".utf8)
        )
        return
    }
    var text = "Exception in thread \"\(threadName)\" \(header)\n"
    for line in lines.dropFirst() {
        text += line
        text += "\n"
    }
    FileHandle.standardError.write(Data(text.utf8))
}

/// Append a throwable's header + saved native frames, then its `Suppressed:`
/// and `Caused by:` chains (same order as the Kotlin-side
/// `collectThrowableTraceLines` used by `Throwable.stackTraceToString`), to
/// `lines`. `depth` bounds recursion against corrupt cause cycles.
private func runtimeUncaughtThrowableLines(
    from throwableRaw: Int,
    prefix: String?,
    into lines: inout [String],
    depth: Int
) {
    guard depth < 16 else { return }
    var frames = runtimeThrowableRawStackFrameStrings(from: throwableRaw)
    if let prefix, !frames.isEmpty {
        frames[0] = prefix + frames[0]
    }
    lines.append(contentsOf: frames)
    guard let ptr = UnsafeMutableRawPointer(bitPattern: throwableRaw),
          let throwable = tryCast(ptr, to: RuntimeThrowableBox.self)
    else { return }
    for suppressed in throwable.suppressed {
        runtimeUncaughtThrowableLines(
            from: suppressed, prefix: "Suppressed: ", into: &lines, depth: depth + 1
        )
    }
    if throwable.cause != 0, throwable.cause != runtimeNullSentinelInt {
        runtimeUncaughtThrowableLines(
            from: throwable.cause, prefix: "Caused by: ", into: &lines, depth: depth + 1
        )
    }
}

/// Whether `job` absorbs a child's failure — kotlinx's `childCancelled`
/// returning true. Supervisor markers decline (the child reports instead).
/// Every other job absorbs iff `handlesException`: JobSupport's default is
/// true (coroutine bodies — runBlocking, launch, coroutineScope), while a
/// `JobImpl` computes it by walking ancestors until a job that handles, so a
/// chain bottoming out at a bare `Job()`/`NonCancellable` root does NOT
/// handle the failure and the launch reports it (matching the JVM's
/// `Exception in thread ...` for `CoroutineScope(Job()).launch { throw }`
/// and `GlobalScope.launch { throw }`, both of which report there).
///
/// The KSwiftK analogs of "a coroutine/body backs this job": a
/// scope-boundary job installed by a builder (`propagatesFailureToParent ==
/// false` — its scope surfaces failures through `waitForChildren`), or a job
/// bound to a suspend-entry-loop continuation (`continuationState != nil` —
/// the runBlocking driver or a launch/withContext body whose terminal state
/// is read out by the driving code).
func runtimeJobAbsorbsChildFailure(_ job: RuntimeJobHandle) -> Bool {
    guard !job.isSupervisorMarker else { return false }
    var current: RuntimeJobHandle? = job
    var depth = 0
    while let node = current, depth < 64 {
        if !node.propagatesFailureToParent || node.continuationState != nil {
            return true
        }
        current = node.parentSnapshot()
        depth += 1
    }
    return current != nil
}

/// Whether `scope` absorbs a registered child's failure. Only a jobful
/// scope can absorb (through `runtimeJobAbsorbsChildFailure`); a jobless
/// scope — a fresh handle minted for `GlobalScope.launch`, a
/// `CoroutineScope(context)` without a Job — has no Job parent for the
/// child, which makes the launch a root coroutine on the JVM as well.
func runtimeScopeAbsorbsChildFailure(_ scope: RuntimeCoroutineScope) -> Bool {
    guard let job = scope.job else { return false }
    return runtimeJobAbsorbsChildFailure(job)
}

/// Complete a fire-and-forget `launch` job exceptionally, then emit the
/// JVM-style uncaught report when no registered parent absorbed the failure.
/// `parentJob`/`parentScope` are the job and scope linkages the launch
/// registered into; a failure is absorbed when a non-supervisor parent exists
/// on either axis (it re-surfaces through that parent's wait instead).
func runtimeCompleteLaunchJobExceptionally(
    _ job: RuntimeJobHandle,
    with exception: Int,
    parentJob: RuntimeJobHandle?,
    parentScope: RuntimeCoroutineScope?
) {
    let absorbedByJob = parentJob.map(runtimeJobAbsorbsChildFailure) ?? false
    let absorbedByScope = parentScope.map(runtimeScopeAbsorbsChildFailure) ?? false
    if !absorbedByJob, !absorbedByScope {
        // Report BEFORE completing the job: completion wakes joiners
        // synchronously, and a joiner (or a scope's waitForChildren) may
        // resume and let the process exit before a post-completion report
        // is ever written.
        runtimeHandleUncaughtCoroutineException(context: parentScope?.context, exception: exception)
    }
    _ = job.completeExceptionally(with: exception)
}

/// Launch a coroutine with a CoroutineExceptionHandler.
/// If the coroutine throws an uncaught exception, the handler is invoked.
/// handlerRaw is an opaque RuntimeExceptionHandlerBox handle (or 0 for no handler).
public func kk_kxmini_launch_with_exception_handler(_ entryPointRaw: Int, _ functionID: Int, _ handlerRaw: Int) -> Int {
    let job = RuntimeJobHandle()
    job.debugName = "StandaloneCoroutine"
    let jobPtr = UnsafeMutableRawPointer(Unmanaged.passRetained(job).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: jobPtr))
    }
    let continuation = kk_coroutine_continuation_new(functionID)
    if let state = runtimeContinuationState(from: continuation) {
        job.continuationState = state
        state.jobHandle = job
    }

    let callerScope = RuntimeCoroutineScope.current
    if let callerScope {
        callerScope.registerChild(Int(bitPattern: jobPtr))
    }
    let callerJob = RuntimeJobHandle.current
    if let callerJob {
        callerJob.registerChild(Int(bitPattern: jobPtr))
    }
    if let contState = runtimeContinuationState(from: continuation) {
        contState.scope = callerScope
    }

    // Resolve the exception handler into a `let` so the completion closure
    // below, which is @Sendable, can capture it as a value.
    let exceptionHandler: RuntimeExceptionHandlerBox? = {
        guard handlerRaw != 0, let ptr = UnsafeMutableRawPointer(bitPattern: handlerRaw) else {
            return nil
        }
        let isObjPointer = runtimeStorage.withGCLock { state in
            state.objectPointers.contains(UInt(bitPattern: ptr))
        }
        guard isObjPointer else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(ptr).takeUnretainedValue() as? RuntimeExceptionHandlerBox
    }()

    let workItem = DispatchWorkItem {
        // See kk_kxmini_launch: mark the body as started on the dispatch thread
        // and re-check cancellation so a racing cancel() can skip the body.
        job.markStarted()
        if job.cancellationSnapshot() {
            _ = job.complete(with: 0)
            return
        }
        runtimeStartLaunchedBody(
            entryPointRaw: entryPointRaw,
            continuation: continuation,
            scope: callerScope,
            job: callerJob
        ) { result, thrownException in
            // The reported exception is authoritative; do not inspect the
            // object-pointer registry, where any non-zero boxed value (string,
            // integer box, ...) that happens to be registered would be
            // misidentified as an exception.
            if thrownException != 0 {
                // A CoroutineExceptionHandler consumes an uncaught exception for
                // this fire-and-forget launch path. Without a handler, preserve
                // the failure on the job instead of silently reporting normal
                // completion.
                if let handler = exceptionHandler {
                    // KUU-CORO-101: this fire-and-forget launch path has no
                    // CoroutineContext object handy to pass as the handler's
                    // first argument (unlike kk_exception_handler_invoke, which
                    // receives one from its caller) -- passing 0 here is an
                    // existing, unchanged limitation, not something this fix
                    // introduces.
                    handler.handler(0, thrownException)
                    _ = job.complete(with: 0)
                } else {
                    runtimeCompleteLaunchJobExceptionally(
                        job, with: thrownException, parentJob: callerJob, parentScope: callerScope
                    )
                }
                return
            }
            _ = job.complete(with: result)
        }
    }
    job.dispatchWorkItem = workItem
    job.markScheduled()
    RuntimePendingLaunchQueue.enqueue(job: job, workItem: workItem)
    return Int(bitPattern: jobPtr)
}

@_cdecl("kk_kxmini_async_await")
public func kk_kxmini_async_await(_ handle: Int, _ continuation: Int) -> Int {
    if let job = runtimeJobHandle(from: handle) {
        job.markConsumedByUserCode()
        job.startIfNeeded()
        if let callerState = runtimeContinuationState(from: continuation) {
            let snapshot = job.completionSnapshot()
            if snapshot.completed {
                if snapshot.exception != 0 {
                    callerState.thrownException = snapshot.exception
                    callerState.signalResume()
                    return Int(bitPattern: kk_coroutine_suspended())
                }
                return snapshot.value
            }
            job.addJoinResumer { _ in
                let completed = job.completionSnapshot()
                if completed.exception != 0 {
                    callerState.resume(withException: completed.exception)
                } else {
                    callerState.resume(with: completed.value)
                }
            }
            return Int(bitPattern: kk_coroutine_suspended())
        }
        return kk_job_join(handle, 0)
    }
    guard let handlePtr = UnsafeMutableRawPointer(bitPattern: handle),
          let task = runtimeAsyncTask(from: handle) else {
        return 0
    }
    // Mark on the handle object itself that user code is consuming the passRetained.
    // This is checked by scope's waitForChildren to avoid double-release.
    task.markConsumedByUserCode()

    // NOTE: unlike the (now-fixed) kk_job_join, this deliberately does NOT release the
    // handle's passRetained after await -- see the NOTE on kk_job_join above for why:
    // Kotlin code may still read the Deferred (e.g. `d.await(); println(d.isActive)`)
    // after this call, and releasing here would leave that reference dangling.

    // CORO-004: suspend-aware await via `awaitResult(callerState:)`.
    if continuation != 0, let callerState = runtimeContinuationState(from: continuation) {
        switch task.awaitResult(callerState: callerState, afterResume: {}) {
        case .suspended:
            return Int(bitPattern: kk_coroutine_suspended())
        case .completed(let result, let thrown):
            if thrown != 0 {
                // A task that already failed before `await()` runs never goes through
                // the completion resumer above, so publish the failure on the caller
                // state and hand control back to the state machine's resume label --
                // the same protocol `kk_coroutine_call_direct_suspend` uses. Returning
                // the (zero) result here instead would swallow the child exception.
                callerState.thrownException = thrown
                callerState.signalResume()
                return Int(bitPattern: kk_coroutine_suspended())
            }
            return result
        }
    }

    // Non-suspend context: block until complete without consuming the passRetained
    // (`takeUnretainedValue` reads the object without taking ownership of the retain).
    let task2 = Unmanaged<RuntimeAsyncTask>.fromOpaque(handlePtr).takeUnretainedValue()
    return task2.awaitResult()
}

@_cdecl("kk_kxmini_delay")
public func kk_kxmini_delay(_ milliseconds: Int, _ continuation: Int) -> Int {
    guard let state = runtimeContinuationState(from: continuation) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_kxmini_delay received invalid continuation handle")
    }
    state.scheduleDelay(milliseconds: milliseconds)
    return Int(bitPattern: kk_coroutine_suspended())
}
