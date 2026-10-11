import Dispatch
import Foundation

// MARK: - STDLIB-CORO-001: CoroutineStart.LAZY launch

/// Launch a coroutine without starting it immediately (CoroutineStart.LAZY).
/// The body is dispatched the first time `join()` or `startIfNeeded()` is called.
@_cdecl("kk_kxmini_launch_lazy")
public func kk_kxmini_launch_lazy(_ entryPointRaw: Int, _ functionID: Int) -> Int {
    let job = RuntimeJobHandle()
    job.debugName = "LazyStandaloneCoroutine"
    let jobPtr = UnsafeMutableRawPointer(Unmanaged.passRetained(job).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: jobPtr))
    }
    let continuation = kk_coroutine_continuation_new(functionID)
    if let state = runtimeContinuationState(from: continuation) {
        job.continuationState = state
        state.jobHandle = job
    }

    // CORO-003: Capture caller's scope from context (not TLS) and register child
    let callerScope = RuntimeCoroutineScope.current
    if let callerScope {
        callerScope.registerChild(Int(bitPattern: jobPtr))
    }
    let callerJob = RuntimeJobHandle.current
    if let callerJob {
        callerJob.registerChild(Int(bitPattern: jobPtr))
    }
    // Propagate caller's scope to child continuation context
    if let contState = runtimeContinuationState(from: continuation) {
        contState.scope = callerScope
    }

    job.installLazyStartBody { [entryPointRaw, continuation, callerScope, callerJob] in
        let workItem = DispatchWorkItem {
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
            ) { result, thrown in
                if thrown != 0 {
                    runtimeCompleteLaunchJobExceptionally(
                        job, with: thrown, parentJob: callerJob, parentScope: callerScope
                    )
                } else {
                    _ = job.complete(with: result)
                }
            }
        }
        job.dispatchWorkItem = workItem
        job.markScheduled()
        RuntimePendingLaunchQueue.enqueue(job: job, workItem: workItem)
    }
    return Int(bitPattern: jobPtr)
}

/// Variant of kk_kxmini_launch_lazy that accepts a pre-built continuation
/// (for lambda arguments that capture outer variables).
@_cdecl("kk_kxmini_launch_lazy_with_cont")
public func kk_kxmini_launch_lazy_with_cont(_ entryPointRaw: Int, _ continuation: Int) -> Int {
    let job = RuntimeJobHandle()
    job.debugName = "LazyStandaloneCoroutine"
    let jobPtr = UnsafeMutableRawPointer(Unmanaged.passRetained(job).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: jobPtr))
    }
    if let state = runtimeContinuationState(from: continuation) {
        job.continuationState = state
        state.jobHandle = job
    }

    // CORO-003: Capture caller's scope from context (not TLS) and register child
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

    job.installLazyStartBody { [entryPointRaw, continuation, callerScope, callerJob] in
        let workItem = DispatchWorkItem {
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
            ) { result, thrown in
                if thrown != 0 {
                    runtimeCompleteLaunchJobExceptionally(
                        job, with: thrown, parentJob: callerJob, parentScope: callerScope
                    )
                } else {
                    _ = job.complete(with: result)
                }
            }
        }
        job.dispatchWorkItem = workItem
        job.markScheduled()
        RuntimePendingLaunchQueue.enqueue(job: job, workItem: workItem)
    }
    return Int(bitPattern: jobPtr)
}

// MARK: - CoroutineStart.UNDISPATCHED launch

/// Launch a coroutine that begins executing immediately on the calling thread
/// and runs there until its first suspension point (`CoroutineStart.UNDISPATCHED`).
///
/// Unlike `kk_kxmini_launch`, nothing is queued before the body runs: the
/// statements that follow `launch(start = CoroutineStart.UNDISPATCHED) { }`
/// observe whatever the body did before suspending. Everything after that first
/// suspension is ordinary queued work on the inherited event loop.
@_cdecl("kk_kxmini_launch_undispatched")
public func kk_kxmini_launch_undispatched(_ entryPointRaw: Int, _ functionID: Int) -> Int {
    runtimeLaunchUndispatched(
        entryPointRaw: entryPointRaw,
        continuation: kk_coroutine_continuation_new(functionID)
    )
}

/// Variant of `kk_kxmini_launch_undispatched` that accepts a pre-built
/// continuation carrying the launched lambda's captured outer variables.
@_cdecl("kk_kxmini_launch_undispatched_with_cont")
public func kk_kxmini_launch_undispatched_with_cont(_ entryPointRaw: Int, _ continuation: Int) -> Int {
    runtimeLaunchUndispatched(entryPointRaw: entryPointRaw, continuation: continuation)
}

private func runtimeLaunchUndispatched(entryPointRaw: Int, continuation: Int) -> Int {
    let job = RuntimeJobHandle()
    job.debugName = "StandaloneCoroutine"
    let jobPtr = UnsafeMutableRawPointer(Unmanaged.passRetained(job).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: jobPtr))
    }
    if let state = runtimeContinuationState(from: continuation) {
        job.continuationState = state
        state.jobHandle = job
    }

    // Same parent bookkeeping as kk_kxmini_launch.
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
        // Inherit the caller's event loop explicitly. The body starts inline on
        // this thread, but every resumption after its first suspension has to be
        // queued on the loop like any other child's, or this coroutine would
        // drop back to racing on the global pool.
        contState.eventLoop = RuntimeEventLoop.current
    }

    job.markScheduled()
    job.markStarted()
    if job.cancellationSnapshot() {
        _ = job.complete(with: 0)
        return Int(bitPattern: jobPtr)
    }

    // The nested suspend-entry loop installs its own task-local keys and
    // removes them on the way out, so snapshot the caller's coroutine identity
    // and put it back afterwards. Without this the statements following the
    // launch would run with no ambient scope or job, and a later `launch` there
    // would detach from its parent instead of becoming its child.
    let savedTaskKey = RuntimeCoroutineScopeTaskKey.currentTaskKey
    let savedJob = RuntimeJobHandle.current
    runtimeStartLaunchedBody(
        entryPointRaw: entryPointRaw,
        continuation: continuation,
        scope: callerScope,
        job: callerJob
    ) { result, thrown in
        if thrown != 0 {
            runtimeCompleteLaunchJobExceptionally(
                job, with: thrown, parentJob: callerJob, parentScope: callerScope
            )
        } else {
            _ = job.complete(with: result)
        }
    }
    RuntimeCoroutineScopeTaskKey.installKey(savedTaskKey)
    RuntimeJobHandle.current = savedJob
    return Int(bitPattern: jobPtr)
}

@_cdecl("kk_kxmini_async")
public func kk_kxmini_async(_ entryPointRaw: Int, _ functionID: Int) -> Int {
    runtimeAsyncScheduled(entryPointRaw: entryPointRaw, continuation: kk_coroutine_continuation_new(functionID))
}

@_cdecl("kk_coroutine_launcher_arg_set")
public func kk_coroutine_launcher_arg_set(_ continuation: Int, _ index: Int64, _ value: Int64) -> Int64 {
    guard let state = runtimeContinuationState(from: continuation) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_coroutine_launcher_arg_set received invalid continuation handle")
    }
    state.launcherArgs[index] = value
    return value
}

@_cdecl("kk_coroutine_launcher_arg_get")
public func kk_coroutine_launcher_arg_get(_ continuation: Int, _ index: Int64) -> Int64 {
    guard let state = runtimeContinuationState(from: continuation) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_coroutine_launcher_arg_get received invalid continuation handle")
    }
    return state.launcherArgs[index] ?? 0
}

@_cdecl("kk_kxmini_run_blocking_with_cont")
public func kk_kxmini_run_blocking_with_cont(
    _ entryPointRaw: Int,
    _ continuation: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    // When this drives a `suspend () -> R` value invoked inside an active
    // coroutine (see kk_suspend_function_invoke_0), the body runs on a fresh
    // continuation. Seed it with the ambient scope so `launch`/`async` inside the
    // invoked block register with the enclosing structured-concurrency scope
    // (e.g. a Kotlin-level `coroutineScope { }`) rather than detaching.
    // A scope override owns its job context; a suspend-value invocation in the
    // current scope shares the caller's job. A genuine top-level `runBlocking`
    // has no ambient scope, so this is a no-op there.
    let contState = runtimeContinuationState(from: continuation)
    if let contState, contState.scope == nil {
        contState.scope = RuntimeCoroutineScope.current
        if contState.jobHandle == nil,
           RuntimeContinuationState.current == nil
           || RuntimeContinuationState.current?.scope === contState.scope
        {
            contState.jobHandle = RuntimeJobHandle.current
        }
    }
    if let contState, contState.jobHandle == nil {
        // KUU-964: a scoped block runs inside its scope's own Job — the
        // SupervisorJob a `supervisorScope { }` installed, or the child Job a
        // `coroutineScope { }` installed — so `currentCoroutineContext().job`
        // resolves inside the block (kotlinx's contract) and children launched
        // here parent to the scope's job, preserving failure isolation. Only
        // when the scope carries no Job and matches the caller's scope does
        // the invoked value keep the caller's job.
        contState.jobHandle = contState.scope?.job
        if contState.jobHandle == nil,
           RuntimeContinuationState.current?.scope === contState.scope
        {
            contState.jobHandle = RuntimeContinuationState.current?.jobHandle
        }
    }
    if let contState {
        // A non-capturing flow emitter enters through the direct C callback and
        // creates this continuation before the nested suspend loop installs its
        // task-local state. Preserve the collector context from the flow stack
        // as a fallback so delayed emissions remain attached to the same collect.
        contState.flowCollectContext = RuntimeContinuationState.current?.flowCollectContext
            ?? runtimeFlowCurrentCollectContext()
    }
    // Forward `outThrown` so an exception thrown by the blocking body reaches the
    // caller. Callers (e.g. the `runBlocking`/suspend-value thunks) branch on this
    // slot to rethrow; dropping it silently swallowed the exception.
    let ownedJob = contState?.jobHandle == nil ? RuntimeJobHandle() : nil
    ownedJob?.debugName = "BlockingCoroutine"
    if let ownedJob {
        ownedJob.markStarted()
        ownedJob.continuationState = contState
        contState?.jobHandle = ownedJob
    }
    return withExtendedLifetime(ownedJob) {
        runtimeRunBlockingOnEventLoop(
            entryPointRaw: entryPointRaw,
            continuation: continuation,
            outThrown: outThrown
        )
    }
}

@_cdecl("kk_suspend_coroutine")
public func kk_suspend_coroutine(_ fnPtr: Int, _ closureRaw: Int, _ continuation: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    var thrown = 0
    _ = runtimeInvokeCollectionLambda1(
        fnPtr: fnPtr,
        closureRaw: closureRaw,
        value: continuation,
        outThrown: &thrown
    )
    if thrown != 0 {
        outThrown?.pointee = thrown
        return 0
    }
    return Int(bitPattern: kk_coroutine_suspended())
}

@_cdecl("kk_kxmini_launch_with_cont")
public func kk_kxmini_launch_with_cont(_ entryPointRaw: Int, _ continuation: Int) -> Int {
    let job = RuntimeJobHandle()
    job.debugName = "StandaloneCoroutine"
    let jobPtr = UnsafeMutableRawPointer(Unmanaged.passRetained(job).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: jobPtr))
    }

    // Link job to continuation state
    if let contState = runtimeContinuationState(from: continuation) {
        job.continuationState = contState
        contState.jobHandle = job
    }

    // CORO-003: Capture caller's scope from context and register child
    let callerScope = RuntimeCoroutineScope.current
    if let callerScope {
        callerScope.registerChild(Int(bitPattern: jobPtr))
    }
    let callerJob = RuntimeJobHandle.current
    if let callerJob {
        callerJob.registerChild(Int(bitPattern: jobPtr))
    }
    // Propagate caller's scope to child continuation context
    if let contState = runtimeContinuationState(from: continuation) {
        contState.scope = callerScope
    }

    let workItem = DispatchWorkItem {
        // See kk_kxmini_launch: mark the body as started on the dispatch thread
        // and re-check cancellation so a racing cancel() can skip the body.
        job.markStarted()
        if job.cancellationSnapshot() {
            _ = job.complete(with: 0)
            return
        }
        // See kk_kxmini_launch: report the thrown exception so one escaping the
        // body completes the job exceptionally instead of being discarded as a
        // normal result.
        runtimeStartLaunchedBody(
            entryPointRaw: entryPointRaw,
            continuation: continuation,
            scope: callerScope,
            job: callerJob
        ) { result, thrown in
            if thrown != 0 {
                runtimeCompleteLaunchJobExceptionally(
                    job, with: thrown, parentJob: callerJob, parentScope: callerScope
                )
            } else {
                _ = job.complete(with: result)
            }
        }
    }
    job.dispatchWorkItem = workItem
    job.markScheduled()
    RuntimePendingLaunchQueue.enqueue(job: job, workItem: workItem)
    return Int(bitPattern: jobPtr)
}

@_cdecl("kk_kxmini_async_with_cont")
public func kk_kxmini_async_with_cont(_ entryPointRaw: Int, _ continuation: Int) -> Int {
    runtimeAsyncScheduled(entryPointRaw: entryPointRaw, continuation: continuation)
}

@_cdecl("kk_kxmini_async_atomic")
public func kk_kxmini_async_atomic(_ entryPointRaw: Int, _ functionID: Int) -> Int {
    runtimeAsyncScheduled(
        entryPointRaw: entryPointRaw, continuation: kk_coroutine_continuation_new(functionID), atomicStart: true
    )
}

@_cdecl("kk_kxmini_async_atomic_with_cont")
public func kk_kxmini_async_atomic_with_cont(_ entryPointRaw: Int, _ continuation: Int) -> Int {
    runtimeAsyncScheduled(entryPointRaw: entryPointRaw, continuation: continuation, atomicStart: true)
}

private func runtimeAsyncScheduled(entryPointRaw: Int, continuation: Int, atomicStart: Bool = false) -> Int {
    let task = RuntimeAsyncTask(atomicStart: atomicStart, debugName: "DeferredCoroutine")
    task.isDeferredResult = true
    task.markScheduledForLaunch()
    let taskPtr = UnsafeMutableRawPointer(Unmanaged.passRetained(task).toOpaque())

    let callerScope = runtimeRegisterAsyncChild(taskPtr: taskPtr, continuation: continuation)
    KxMiniRuntime.launch {
        guard task.markStarted() else { return }
        runtimeStartLaunchedBody(
            entryPointRaw: entryPointRaw,
            continuation: continuation,
            scope: callerScope,
            job: task.completionJob,
            onFinished: runtimeAsyncTaskCompletion(task)
        )
    }
    return Int(bitPattern: taskPtr)
}

// MARK: - STDLIB-CORO-001: CoroutineStart.LAZY / UNDISPATCHED async

/// Registers a freshly created `async` task with the caller's scope and seeds
/// the block's continuation with that scope, so the child's suspend-entry loop
/// discovers its parent (CORO-003).
private func runtimeRegisterAsyncChild(
    taskPtr: UnsafeMutableRawPointer,
    continuation: Int
) -> RuntimeCoroutineScope? {
    let callerScope = RuntimeCoroutineScope.current
    if let callerScope {
        callerScope.registerChild(Int(bitPattern: taskPtr))
    }
    RuntimeJobHandle.current?.registerChild(Int(bitPattern: taskPtr))
    if let contState = runtimeContinuationState(from: continuation) {
        contState.scope = callerScope
        let job = runtimeAsyncTask(from: Int(bitPattern: taskPtr))?.completionJob
        contState.jobHandle = job
        job?.continuationState = contState
    }
    return callerScope
}

/// The completion handler every `async` entry point installs.
///
/// STDLIB-CORO-BUG-05: the thrown exception is reported alongside the result,
/// so `await()` re-throws instead of silently resuming with 0 (the synchronous
/// path forces the result to 0 on a throw and would otherwise drop it).
func runtimeAsyncTaskCompletion(
    _ task: RuntimeAsyncTask
) -> @Sendable (_ result: Int, _ thrown: Int) -> Void {
    { result, thrown in
        if thrown != 0 {
            task.completeExceptionally(with: thrown)
        } else {
            task.complete(with: result)
        }
    }
}

/// `async(start = CoroutineStart.LAZY)`: create the `Deferred` without
/// scheduling its body. The body is dispatched the first time something demands
/// the result -- `await()`, or the enclosing scope joining its children -- via
/// `RuntimeAsyncTask.startIfNeeded()`.
@_cdecl("kk_kxmini_async_lazy")
public func kk_kxmini_async_lazy(_ entryPointRaw: Int, _ functionID: Int) -> Int {
    runtimeAsyncLazy(
        entryPointRaw: entryPointRaw,
        continuation: kk_coroutine_continuation_new(functionID)
    )
}

/// Variant of `kk_kxmini_async_lazy` that accepts a pre-built continuation
/// carrying the block's captured outer variables.
@_cdecl("kk_kxmini_async_lazy_with_cont")
public func kk_kxmini_async_lazy_with_cont(_ entryPointRaw: Int, _ continuation: Int) -> Int {
    runtimeAsyncLazy(entryPointRaw: entryPointRaw, continuation: continuation)
}

private func runtimeAsyncLazy(entryPointRaw: Int, continuation: Int) -> Int {
    let task = RuntimeAsyncTask(debugName: "LazyDeferredCoroutine")
    task.isDeferredResult = true
    let taskPtr = UnsafeMutableRawPointer(Unmanaged.passRetained(task).toOpaque())
    let callerScope = runtimeRegisterAsyncChild(taskPtr: taskPtr, continuation: continuation)

    task.installLazyStartBody { [entryPointRaw, continuation, callerScope] in
        // Dispatched exactly as an eager `async` would be: onto the enclosing
        // runBlocking event loop when there is one, the global pool otherwise
        // (see KxMiniRuntime.launch). Only the *timing* differs from DEFAULT.
        KxMiniRuntime.launch {
            guard task.markStarted() else { return }
            runtimeStartLaunchedBody(
                entryPointRaw: entryPointRaw,
                continuation: continuation,
                scope: callerScope,
                job: task.completionJob,
                onFinished: runtimeAsyncTaskCompletion(task)
            )
        }
    }
    return Int(bitPattern: taskPtr)
}

/// `async(start = CoroutineStart.UNDISPATCHED)`: the body begins executing
/// immediately on the calling thread and runs there until its first suspension
/// point, so the statements following the `async` observe whatever it did
/// before suspending. Everything after that suspension is ordinary queued work
/// on the inherited event loop.
@_cdecl("kk_kxmini_async_undispatched")
public func kk_kxmini_async_undispatched(_ entryPointRaw: Int, _ functionID: Int) -> Int {
    runtimeAsyncUndispatched(
        entryPointRaw: entryPointRaw,
        continuation: kk_coroutine_continuation_new(functionID)
    )
}

/// Variant of `kk_kxmini_async_undispatched` that accepts a pre-built
/// continuation carrying the block's captured outer variables.
@_cdecl("kk_kxmini_async_undispatched_with_cont")
public func kk_kxmini_async_undispatched_with_cont(_ entryPointRaw: Int, _ continuation: Int) -> Int {
    runtimeAsyncUndispatched(entryPointRaw: entryPointRaw, continuation: continuation)
}

private func runtimeAsyncUndispatched(entryPointRaw: Int, continuation: Int) -> Int {
    let task = RuntimeAsyncTask(debugName: "DeferredCoroutine")
    task.isDeferredResult = true
    task.markScheduledForLaunch()
    let taskPtr = UnsafeMutableRawPointer(Unmanaged.passRetained(task).toOpaque())
    let callerScope = runtimeRegisterAsyncChild(taskPtr: taskPtr, continuation: continuation)
    if let contState = runtimeContinuationState(from: continuation) {
        // Inherit the caller's event loop explicitly. The body starts inline on
        // this thread, but every resumption after its first suspension has to be
        // queued on the loop like any other child's, or this coroutine would
        // drop back to racing on the global pool. Same as runtimeLaunchUndispatched.
        contState.eventLoop = RuntimeEventLoop.current
    }

    if !task.markStarted() {
        return Int(bitPattern: taskPtr)
    }

    // The nested suspend-entry loop installs its own task-local keys and removes
    // them on the way out, so snapshot the caller's coroutine identity and put it
    // back afterwards. Without this the statements following the `async` would run
    // with no ambient scope, and a later `launch`/`async` there would detach from
    // its parent. Same as runtimeLaunchUndispatched.
    let savedTaskKey = RuntimeCoroutineScopeTaskKey.currentTaskKey
    let savedJob = RuntimeJobHandle.current
    runtimeStartLaunchedBody(
        entryPointRaw: entryPointRaw,
        continuation: continuation,
        scope: callerScope,
        job: task.completionJob,
        onFinished: runtimeAsyncTaskCompletion(task)
    )
    RuntimeCoroutineScopeTaskKey.installKey(savedTaskKey)
    RuntimeJobHandle.current = savedJob
    return Int(bitPattern: taskPtr)
}

@_cdecl("kk_produce")
public func kk_produce(_ entryPointRaw: Int, _ capture0: Int) -> Int {
    let continuation = kk_coroutine_continuation_new(entryPointRaw)
    if let contState = runtimeContinuationState(from: continuation) {
        contState.launcherArgs[1] = Int64(capture0)
    }
    return kk_kxmini_produce_with_cont(entryPointRaw, continuation)
}

/// KUU-1439: mint the CoroutineScope facet a channel-backed ProducerScope
/// resolves to. `produce`/`channelFlow`/`callbackFlow` hand the raw channel
/// handle to the producer block as `this`, so `CoroutineScope` member calls
/// (`launch`/`async`/`cancel`/`isActive`) reach the `kk_coroutine_scope_*`
/// bridges carrying a channel handle. Binding the minted scope on the channel
/// lets `runtimeCoroutineScope(from:)` resolve it. The scope adopts the
/// producer job so the child context's Job is the producer's own and a
/// producer cancellation cascades into children launched on it.
private func runtimeBindProducerScope(
    channelHandle: Int,
    job: RuntimeJobHandle,
    context: RuntimeCoroutineContext
) {
    guard let channel = runtimeChannelHandleObject(from: channelHandle) else { return }
    let producerScopeTypeID = runtimeStableNominalTypeID(
        fqName: "kotlinx.coroutines.channels.ProducerScope"
    )
    runtimeRegisterObjectType(rawValue: channelHandle, classID: producerScopeTypeID)
    runtimeRegisterTypeEdge(
        childTypeID: producerScopeTypeID,
        parentTypeID: runtimeStableNominalTypeID(fqName: "kotlinx.coroutines.CoroutineScope")
    )
    runtimeRegisterTypeEdge(
        childTypeID: producerScopeTypeID,
        parentTypeID: runtimeStableNominalTypeID(
            fqName: "kotlinx.coroutines.channels.SendChannel"
        )
    )
    let scope = RuntimeCoroutineScope(context: context)
    scope.adoptJob(job)
    channel.bindProducerScope(scope)
}

/// Producer coroutine context for launchers without a continuation state:
/// the caller scope's dispatcher/name/handler/extras with the producer Job in
/// the Job slot — the same shape `makeContinuationContext()` yields.
private func runtimeProducerContext(
    job: RuntimeJobHandle,
    inherited: RuntimeCoroutineContext?
) -> RuntimeCoroutineContext {
    let extras = runtimeMergedContextExtras(
        inherited: inherited?.extras ?? [],
        override: [],
        jobPresent: true,
        namePresent: inherited?.name != nil,
        dispatcherPresent: (inherited?.dispatcher ?? 0) != 0
            || (inherited?.dispatcherHandleRaw ?? 0) != 0,
        handlerPresent: inherited?.exceptionHandler != nil
    )
    // Same event-loop fallback as makeContinuationContext: a producer launched
    // on a runBlocking-bound coroutine exposes the loop as its interceptor.
    var dispatcherHandleRaw = inherited?.dispatcherHandleRaw ?? 0
    if (inherited?.dispatcher ?? 0) == 0, dispatcherHandleRaw == 0,
       !extras.contains(where: {
           $0.key == kk_continuation_interceptor_key()
               || $0.key == kk_coroutine_dispatcher_key()
       }),
       let elementRaw = RuntimeEventLoop.current?.elementHandle()
    {
        dispatcherHandleRaw = elementRaw
    }
    return RuntimeCoroutineContext(
        dispatcher: inherited?.dispatcher ?? 0,
        name: inherited?.name,
        exceptionHandler: inherited?.exceptionHandler,
        jobHandleRaw: job.identityHandle,
        nameHandleRaw: inherited?.nameHandleRaw ?? 0,
        dispatcherHandleRaw: dispatcherHandleRaw,
        extras: extras
    )
}

/// Launch a producer on a channel with the requested buffering policy.
/// `channelFlow` and `callbackFlow` use the Kotlin buffered default, while
/// `produce` retains its rendezvous behavior through the public wrapper below.
func runtimeKxMiniProduceWithCont(
    _ entryPointRaw: Int,
    _ continuation: Int,
    channelCapacity: Int
) -> Int {
    let channelHandle = kk_channel_create(channelCapacity)
    let job = RuntimeJobHandle()
    job.producerChannel = channelHandle
    job.debugName = "ProducerCoroutine"
    let jobPtr = UnsafeMutableRawPointer(Unmanaged.passRetained(job).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: jobPtr))
    }
    // KUU-1450: publish the job as started up front like the
    // `__kk_produce_launch*` launchers do — `isActive` reads `.active`, and a
    // producer left `.new` answers false for `isActive`/`coroutineContext.job
    // .isActive` inside its own running body.
    job.markStarted()

    if let contState = runtimeContinuationState(from: continuation) {
        job.continuationState = contState
        contState.jobHandle = job
        contState.launcherArgs[0] = Int64(channelHandle)
        contState.eventLoop = RuntimeEventLoop.current
    }

    let callerScope = RuntimeCoroutineScope.current
    if let callerScope {
        callerScope.registerChild(Int(bitPattern: jobPtr))
    }
    if let contState = runtimeContinuationState(from: continuation) {
        contState.scope = callerScope
        // The ProducerScope receiver is the raw channel handle; mint its
        // CoroutineScope facet so the kk_coroutine_scope_* bridges resolve it.
        runtimeBindProducerScope(
            channelHandle: channelHandle, job: job,
            context: contState.makeContinuationContext()
        )
    }

    KxMiniRuntime.launch {
        // Same cancel-before-start guard as `__kk_produce_launch*`: a cancel()
        // racing ahead of the dispatched body already moved the job to
        // cancelling/cancelled, so skip the body and settle the channel.
        if job.cancellationSnapshot() {
            _ = kk_channel_close(channelHandle)
            _ = job.complete(with: 0)
            return
        }
        runtimeStartLaunchedBody(
            entryPointRaw: entryPointRaw,
            continuation: continuation,
            scope: callerScope,
            job: nil
        ) { result, _ in
            _ = kk_channel_close(channelHandle)
            _ = job.complete(with: result)
        }
    }
    return channelHandle
}

@_cdecl("kk_kxmini_produce_with_cont")
public func kk_kxmini_produce_with_cont(_ entryPointRaw: Int, _ continuation: Int) -> Int {
    runtimeKxMiniProduceWithCont(entryPointRaw, continuation, channelCapacity: 0)
}

// MARK: - Dispatcher-aware launch (STDLIB-CORO-072)

/// Launch a coroutine on a specific dispatcher (fire-and-forget).
/// dispatcherRaw is a dispatcher tag (kk_dispatcher_default/io/main).
/// Returns an opaque job handle (RuntimeJobHandle*).
@_cdecl("kk_kxmini_launch_with_dispatcher")
public func kk_kxmini_launch_with_dispatcher(_ entryPointRaw: Int, _ functionID: Int, _ dispatcherRaw: Int) -> Int {
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

    let dispatcher = runtimeResolveDispatcher(from: dispatcherRaw)
    let workItem = DispatchWorkItem {
        // See kk_kxmini_launch: mark the body as started on the dispatch thread
        // and re-check cancellation so a racing cancel() can skip the body.
        job.markStarted()
        if job.cancellationSnapshot() {
            _ = job.complete(with: 0)
            return
        }
        let savedDispatcher = RuntimeDispatcher.current
        RuntimeDispatcher.current = dispatcher
        defer { RuntimeDispatcher.current = savedDispatcher }
        RuntimeCoroutineScope.current = callerScope
        RuntimeJobHandle.current = callerJob
        // See kk_kxmini_launch: forward outThrown so an exception escaping the body
        // completes the job exceptionally instead of being discarded as a normal result.
        var thrown = 0
        let result = runSuspendEntryLoopWithContinuation(
            entryPointRaw: entryPointRaw,
            continuation: continuation,
            outThrown: &thrown
        )
        RuntimeCoroutineScope.current = nil
        RuntimeJobHandle.current = nil
        if thrown != 0 {
            runtimeCompleteLaunchJobExceptionally(
                job, with: thrown, parentJob: callerJob, parentScope: callerScope
            )
        } else {
            _ = job.complete(with: result)
        }
    }
    job.dispatchWorkItem = workItem
    job.markScheduled()
    dispatcher.queue.async(execute: workItem)
    return Int(bitPattern: jobPtr)
}

/// Variant of kk_kxmini_launch_with_dispatcher that accepts a pre-built continuation.
@_cdecl("kk_kxmini_launch_with_dispatcher_and_cont")
public func kk_kxmini_launch_with_dispatcher_and_cont(_ entryPointRaw: Int, _ continuation: Int, _ dispatcherRaw: Int) -> Int {
    let job = RuntimeJobHandle()
    job.debugName = "StandaloneCoroutine"
    let jobPtr = UnsafeMutableRawPointer(Unmanaged.passRetained(job).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: jobPtr))
    }

    if let contState = runtimeContinuationState(from: continuation) {
        job.continuationState = contState
        contState.jobHandle = job
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

    let dispatcher = runtimeResolveDispatcher(from: dispatcherRaw)
    let workItem = DispatchWorkItem {
        // See kk_kxmini_launch: mark the body as started on the dispatch thread
        // and re-check cancellation so a racing cancel() can skip the body.
        job.markStarted()
        if job.cancellationSnapshot() {
            _ = job.complete(with: 0)
            return
        }
        let savedDispatcher = RuntimeDispatcher.current
        RuntimeDispatcher.current = dispatcher
        defer { RuntimeDispatcher.current = savedDispatcher }
        RuntimeCoroutineScope.current = callerScope
        RuntimeJobHandle.current = callerJob
        // See kk_kxmini_launch: forward outThrown so an exception escaping the body
        // completes the job exceptionally instead of being discarded as a normal result.
        var thrown = 0
        let result = runSuspendEntryLoopWithContinuation(
            entryPointRaw: entryPointRaw,
            continuation: continuation,
            outThrown: &thrown
        )
        RuntimeCoroutineScope.current = nil
        RuntimeJobHandle.current = nil
        if thrown != 0 {
            runtimeCompleteLaunchJobExceptionally(
                job, with: thrown, parentJob: callerJob, parentScope: callerScope
            )
        } else {
            _ = job.complete(with: result)
        }
    }
    job.dispatchWorkItem = workItem
    job.markScheduled()
    dispatcher.queue.async(execute: workItem)
    return Int(bitPattern: jobPtr)
}

/// KSP-1573: backing for the bundled `CoroutineScope.produce`/`actor`
/// builders — `__kk_produce_launch(channel, blockFnPtr, blockEnvRaw)`.
///
/// Two block shapes reach this boundary:
///  - A suspend *literal* is rewritten by CoroutineLoweringPass into a
///    launcher-thunk + continuation pair and reaches
///    `__kk_produce_launch_with_cont` instead — the same convention the
///    synthetic `kk_kxmini_produce_with_cont` launcher used.
///  - A suspend function *value* (a block stored in a variable or received
///    from another call) crosses as the (fnPtr, env) pair suspend function
///    values use at the ABI boundary. A value's invoke thunk keeps the
///    ordinary captured-lambda layout `(cap0..capN, receiver, outThrown)` —
///    only literals marked via coroutineLauncherLambdaExprIDs lower
///    receiver-first — so env expands to the leading slots and the channel
///    handle passes as the trailing receiver (the scope `this`).
///
/// Both shapes register the child job on the ambient scope
/// (`RuntimeCoroutineScope.current` — the same scope the synthetic
/// kk_produce launcher used) and close the channel when the block finishes.
/// Returns the channel handle.
@_cdecl("__kk_produce_launch")
public func __kk_produce_launch(_ channelHandle: Int, _ entryPointRaw: Int, _ envRaw: Int) -> Int {
    guard entryPointRaw != 0 else {
        return channelHandle
    }
    let job = RuntimeJobHandle()
    job.producerChannel = channelHandle
    // KUU-1352: shared with `actor` (bundled actor lowers to the same entry),
    // so actor jobs also print ProducerCoroutine rather than upstream's
    // ActorCoroutine — the ABI carries no discriminator.
    job.debugName = "ProducerCoroutine"
    let jobPtr = UnsafeMutableRawPointer(Unmanaged.passRetained(job).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: jobPtr))
    }
    job.markStarted()
    let callerScope = RuntimeCoroutineScope.current
    callerScope?.registerChild(Int(bitPattern: jobPtr))
    runtimeBindProducerScope(
        channelHandle: channelHandle, job: job,
        context: runtimeProducerContext(job: job, inherited: callerScope?.context)
    )

    // Expand the env slot into the thunk's positional captures: 0 → none, a
    // packed env object (kk_object_new(2+N, classID: 0), captures at slots
    // 2..) → N captures, anything else → a single raw capture.
    let captures: [Int]
    let resolvedEntryPointRaw: Int
    if let functionValue = runtimeFunctionValueBox(from: entryPointRaw) {
        resolvedEntryPointRaw = functionValue.fnPtr
        captures = [functionValue.closureRaw]
    } else if envRaw == 0 {
        resolvedEntryPointRaw = entryPointRaw
        captures = []
    } else if let envBox = resolveRuntimeHandle(envRaw, as: RuntimeObjectBox.self),
              envBox.classID == 0,
              envBox.elements.count > 2
    {
        resolvedEntryPointRaw = entryPointRaw
        captures = Array(envBox.elements.dropFirst(2))
    } else {
        resolvedEntryPointRaw = entryPointRaw
        captures = [envRaw]
    }

    KxMiniRuntime.launch {
        if job.cancellationSnapshot() {
            _ = kk_channel_close(channelHandle)
            _ = job.complete(with: 0)
            return
        }
        let outerTaskKey = RuntimeCoroutineScopeTaskKey.installedKey
        let taskKey = RuntimeCoroutineScopeTaskKey.installFreshKey()
        defer {
            RuntimeCoroutineScope.removeScope(forTask: taskKey)
            RuntimeContinuationState.removeState(forTask: taskKey)
            RuntimeJobHandle.current = nil
            RuntimeCoroutineScopeTaskKey.restoreKey(outerTaskKey)
        }
        RuntimeCoroutineScope.current = callerScope
        RuntimeJobHandle.current = job
        var thrown = 0
        let result = runtimeInvokeSuspendLauncherThunk(
            entryPointRaw: resolvedEntryPointRaw,
            receiver: channelHandle,
            captures: captures,
            outThrown: &thrown
        )
        _ = kk_channel_close(channelHandle)
        if thrown != 0 {
            _ = job.completeExceptionally(with: thrown)
        } else {
            _ = job.complete(with: result)
        }
    }
    return channelHandle
}

/// Invokes a suspend launcher thunk `(cap0..capN, receiver, outThrown)` —
/// the ordinary captured-lambda layout, captures first and the receiver
/// (the block's `this`) trailing — whose captures arrive at the ABI
/// boundary packed in env.
func runtimeInvokeSuspendLauncherThunk(
    entryPointRaw: Int,
    receiver: Int,
    captures: [Int],
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    switch captures.count {
    case 0:
        let invoke = unsafeBitCast(entryPointRaw, to: KKFunctionEntryPoint1.self)
        return invoke(receiver, outThrown)
    case 1:
        let invoke = unsafeBitCast(entryPointRaw, to: KKFunctionEntryPoint2.self)
        return invoke(captures[0], receiver, outThrown)
    case 2:
        let invoke = unsafeBitCast(entryPointRaw, to: KKFunctionEntryPoint3.self)
        return invoke(captures[0], captures[1], receiver, outThrown)
    case 3:
        let invoke = unsafeBitCast(entryPointRaw, to: KKFunctionEntryPoint4.self)
        return invoke(captures[0], captures[1], captures[2], receiver, outThrown)
    case 4:
        let invoke = unsafeBitCast(entryPointRaw, to: KKFunctionEntryPoint5.self)
        return invoke(captures[0], captures[1], captures[2], captures[3], receiver, outThrown)
    default:
        runtimeStructuredPanic("__kk_produce_launch: suspend block captures exceed launcher thunk arity")
        return 0
    }
}

/// KSP-1573: launcher-rewrite counterpart of `__kk_produce_launch` —
/// `(channel, launcherThunk, continuation)`, the same convention
/// `kk_kxmini_produce_with_cont` uses except the channel arrives
/// pre-created: the bundled `Channel(capacity, onBufferOverflow)` factory
/// applies the capacity/overflow semantics in Kotlin before the launch.
@_cdecl("__kk_produce_launch_with_cont")
public func __kk_produce_launch_with_cont(_ channelHandle: Int, _ entryPointRaw: Int, _ continuation: Int) -> Int {
    guard let contState = runtimeContinuationState(from: continuation) else {
        return channelHandle
    }
    let job = RuntimeJobHandle()
    job.producerChannel = channelHandle
    job.debugName = "ProducerCoroutine"
    let jobPtr = UnsafeMutableRawPointer(Unmanaged.passRetained(job).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: jobPtr))
    }
    job.markStarted()
    job.continuationState = contState
    contState.jobHandle = job
    // Legacy launchers leave slot zero for the receiver; closure-first
    // adapters seed both the closure and receiver at the call site.
    if contState.launcherArgs[0] == nil {
        contState.launcherArgs[0] = Int64(channelHandle)
    }
    let callerScope = RuntimeCoroutineScope.current
    callerScope?.registerChild(Int(bitPattern: jobPtr))
    contState.scope = callerScope
    contState.eventLoop = RuntimeEventLoop.current
    runtimeBindProducerScope(
        channelHandle: channelHandle, job: job,
        context: contState.makeContinuationContext()
    )

    KxMiniRuntime.launch {
        if job.cancellationSnapshot() {
            _ = kk_channel_close(channelHandle)
            _ = job.complete(with: 0)
            return
        }
        runtimeStartLaunchedBody(
            entryPointRaw: entryPointRaw,
            continuation: continuation,
            scope: callerScope,
            job: nil
        ) { result, thrown in
            _ = kk_channel_close(channelHandle)
            if thrown != 0 {
                _ = job.completeExceptionally(with: thrown)
            } else {
                _ = job.complete(with: result)
            }
        }
    }
    return channelHandle
}
