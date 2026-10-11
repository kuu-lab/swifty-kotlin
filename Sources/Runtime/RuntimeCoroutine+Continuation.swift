import Dispatch
import Foundation

private final class RuntimeCallbackContinuation: KKContinuation, @unchecked Sendable {
    let context: UnsafeMutableRawPointer?
    private let resumeWithRaw: Int

    init(contextRaw: Int, resumeWithRaw: Int) {
        self.context = UnsafeMutableRawPointer(bitPattern: contextRaw)
        self.resumeWithRaw = resumeWithRaw
    }

    func resumeWith(_ result: UnsafeMutableRawPointer?) {
        resumeWith(result, outThrown: nil)
    }

    func resumeWith(_ result: UnsafeMutableRawPointer?, outThrown: UnsafeMutablePointer<Int>?) {
        var thrown = 0
        _ = kk_function_invoke(resumeWithRaw, Int(bitPattern: result), &thrown)
        if let outThrown {
            outThrown.pointee = thrown
        } else if thrown != 0 {
            _ = kk_native_processUnhandledException(thrown, nil)
        }
    }
}

@_cdecl("kk_coroutine_suspended")
public func kk_coroutine_suspended() -> UnsafeMutableRawPointer {
    let ptr = UnsafeMutableRawPointer(Unmanaged.passUnretained(runtimeStorage.coroutineSuspendedBox).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
        state.borrowedObjectPointers.insert(UInt(bitPattern: ptr))
    }
    return ptr
}

@_cdecl("kk_coroutine_continuation_new")
public func kk_coroutine_continuation_new(_ functionID: Int) -> Int {
    let state = RuntimeContinuationState(functionID: Int64(functionID))
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(state).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

private final class RuntimeDirectSuspendCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var hasReturned = false
    private var outcome: (result: Int, thrown: Int)?

    /// Record completion and report whether the caller already returned.
    func record(result: Int, thrown: Int) -> Bool {
        lock.lock()
        outcome = (result, thrown)
        let shouldSignal = hasReturned
        lock.unlock()
        return shouldSignal
    }

    /// Mark the initial invocation as returned and return a completion that
    /// happened before that point, if any.
    func markReturned() -> (result: Int, thrown: Int)? {
        lock.lock()
        hasReturned = true
        let completed = outcome
        lock.unlock()
        return completed
    }
}

/// STDLIB-CORO-BUG-01: runtime support for a suspend function calling another
/// suspend function directly (not through launch/async/withContext). The
/// callee runs on its own fresh continuation (childContinuation) via the
/// standard entry loop; its completion is relayed into the caller's own
/// continuation (callerContinuationRaw) instead of being dropped, so the
/// caller's entry loop -- already about to suspend on this call -- gets woken
/// up with the real result. A synchronously completed child returns its result
/// directly; only a child that remains suspended schedules a caller resume.
@_cdecl("kk_coroutine_call_direct_suspend")
public func kk_coroutine_call_direct_suspend(
    _ entryPointRaw: Int,
    _ childContinuation: Int,
    _ callerContinuationRaw: Int
) -> Int {
    guard let callerState = runtimeContinuationState(from: callerContinuationRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_coroutine_call_direct_suspend received invalid caller continuation handle")
    }
    let callerTaskKey = RuntimeCoroutineScopeTaskKey.currentTaskKey
    let callerJobHandle = RuntimeJobHandle.current
    defer {
        RuntimeCoroutineScopeTaskKey.installKey(callerTaskKey)
        RuntimeJobHandle.current = callerJobHandle
    }
    let childState = runtimeContinuationState(from: childContinuation)
    if let childState {
        childState.scope = callerState.scope
        childState.jobHandle = callerState.jobHandle
        childState.builderContext = callerState.builderContext
        childState.flowCollectContext = callerState.flowCollectContext
        childState.resumesInline = callerState.resumesInline
        callerState.bindSuspendedCallChild(childState)
    }
    let completion = RuntimeDirectSuspendCompletion()
    _ = runSuspendEntryLoopWithContinuation(
        entryPointRaw: entryPointRaw,
        continuation: childContinuation,
        onCompletion: { result, thrown in
            if let childState {
                callerState.unbindSuspendedCallChild(childState)
            }
            // Always publish the outcome, including clearing the thrown slot on
            // success: the caller's state machine reads this slot at the resume
            // label, and a stale exception from a previously caught throw would
            // otherwise be re-observed (and re-thrown) at the next suspend point.
            callerState.thrownException = thrown
            if thrown == 0 {
                callerState.completion = Int64(result)
            }
            if completion.record(result: result, thrown: thrown) {
                callerState.signalResume()
            }
        }
    )
    let suspendedToken = Int(bitPattern: kk_coroutine_suspended())
    if let outcome = completion.markReturned() {
        if outcome.thrown != 0 {
            // The state machine reads the thrown exception after a resume.
            callerState.signalResume()
            return suspendedToken
        }
        return outcome.result
    }
    return suspendedToken
}

/// Source suspend wrappers relay to an active caller instead of nesting a
/// blocking event-loop drain. Ordinary callers retain the blocking bridge.
@_cdecl("kk_coroutine_call_suspend_wrapper")
public func kk_coroutine_call_suspend_wrapper(
    _ entryPointRaw: Int,
    _ continuation: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let caller = RuntimeContinuationState.current else {
        return kk_kxmini_run_blocking_with_cont(entryPointRaw, continuation, outThrown)
    }
    outThrown?.pointee = 0
    let callerRaw = Int(bitPattern: Unmanaged.passUnretained(caller).toOpaque())
    return kk_coroutine_call_direct_suspend(entryPointRaw, continuation, callerRaw)
}

@_cdecl("kk_create_coroutine_unintercepted")
public func kk_create_coroutine_unintercepted(_ entryPointRaw: Int, _ completionContinuation: Int) -> Int {
    let continuation = kk_coroutine_continuation_new(entryPointRaw)
    runtimeContinuationState(from: continuation)?.configureUninterceptedCoroutine(
        entryPointRaw: entryPointRaw,
        completionContinuation: completionContinuation
    )
    return continuation
}

/// Dynamic suspend function values keep their CPS entry point in the callable
/// box. Known symbols are still rewritten directly by coroutine lowering.
private func createCoroutineFromFunctionValue(_ functionRaw: Int, arguments: [Int], completion: Int) -> Int {
    guard let box = runtimeFunctionValueBox(from: functionRaw),
          box.suspendEntryPoint != 0,
          box.arity == arguments.count else {
        preconditionFailure("Coroutine builder requires a boxed suspend callable")
    }
    let continuation = kk_create_coroutine_unintercepted(box.suspendEntryPoint, completion)
    for (index, argument) in ([box.closureRaw] + arguments).enumerated() {
        _ = kk_coroutine_launcher_arg_set(continuation, Int64(index), Int64(argument))
    }
    return continuation
}

@_cdecl("kk_create_coroutine_unintercepted_no_receiver")
public func kk_create_coroutine_unintercepted_no_receiver(
    _ functionRaw: Int,
    _ functionContextRaw: Int,
    _ completionContinuation: Int
) -> Int {
    createCoroutineFromFunctionValue(functionRaw, arguments: [], completion: completionContinuation)
}

/// Receiver-less `startCoroutineUninterceptedOrReturn` over a boxed suspend
/// callable. Coroutine lowering rewrites calls whose function is a known
/// entry point; dynamic function values fall through to this entry, which
/// creates the coroutine from the callable box and starts it unintercepted.
@_cdecl("kk_start_coroutine_unintercepted_or_return_no_receiver")
public func kk_start_coroutine_unintercepted_or_return_no_receiver(
    _ functionRaw: Int,
    _ functionContextRaw: Int,
    _ completionContinuation: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let box = runtimeFunctionValueBox(from: functionRaw),
          box.suspendEntryPoint != 0,
          box.arity == 0 else {
        preconditionFailure("Coroutine builder requires a boxed suspend callable")
    }
    let continuation = createCoroutineFromFunctionValue(
        functionRaw, arguments: [], completion: completionContinuation
    )
    return startCoroutineUninterceptedOrReturn(
        entryPointRaw: box.suspendEntryPoint,
        continuation: continuation,
        completionContinuation: completionContinuation,
        outThrown: outThrown
    )
}

/// Receiver-bearing variant of the boxed suspend callable builder.
@_cdecl("kk_create_coroutine_unintercepted_with_receiver")
public func kk_create_coroutine_unintercepted_with_receiver(
    _ functionRaw: Int,
    _ functionContextRaw: Int,
    _ receiverRaw: Int,
    _ completionContinuation: Int
) -> Int {
    createCoroutineFromFunctionValue(functionRaw, arguments: [receiverRaw], completion: completionContinuation)
}

/// Receiver-bearing `startCoroutineUninterceptedOrReturn` over a boxed suspend
/// callable; see the receiver-less variant above.
@_cdecl("kk_start_coroutine_unintercepted_or_return_with_receiver")
public func kk_start_coroutine_unintercepted_or_return_with_receiver(
    _ functionRaw: Int,
    _ functionContextRaw: Int,
    _ receiverRaw: Int,
    _ completionContinuation: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let box = runtimeFunctionValueBox(from: functionRaw),
          box.suspendEntryPoint != 0,
          box.arity == 1 else {
        preconditionFailure("Coroutine builder requires a boxed suspend callable")
    }
    let continuation = createCoroutineFromFunctionValue(
        functionRaw, arguments: [receiverRaw], completion: completionContinuation
    )
    return startCoroutineUninterceptedOrReturn(
        entryPointRaw: box.suspendEntryPoint,
        continuation: continuation,
        completionContinuation: completionContinuation,
        outThrown: outThrown
    )
}

@_cdecl("kk_start_coroutine_unintercepted_or_return")
public func kk_start_coroutine_unintercepted_or_return(
    _ entryPointRaw: Int,
    _ continuation: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    startCoroutineUninterceptedOrReturn(
        entryPointRaw: entryPointRaw,
        continuation: continuation,
        completionContinuation: runtimeContinuationState(from: continuation)?.takeUninterceptedCoroutineStart()?.completionContinuation ?? 0,
        outThrown: outThrown
    )
}

private func startUninterceptedCoroutineFromResume(
    entryPointRaw: Int,
    continuation: Int,
    completionContinuation: Int,
    outThrown: UnsafeMutablePointer<Int>? = nil
) {
    var thrown = 0
    let result = startCoroutineUninterceptedOrReturn(
        entryPointRaw: entryPointRaw,
        continuation: continuation,
        completionContinuation: completionContinuation,
        outThrown: &thrown
    )
    if completionContinuation == 0 {
        return
    }
    if thrown != 0 {
        __kk_coroutine_continuation_resume_with(
            completionContinuation, runtimeResultFailure(thrown), outThrown
        )
        return
    }
    if result != Int(bitPattern: kk_coroutine_suspended()) {
        __kk_coroutine_continuation_resume_with(
            completionContinuation, runtimeResultSuccess(result), outThrown
        )
    }
}

private func continueUninterceptedCoroutineToCompletion(
    entryPointRaw: Int,
    continuation: Int,
    completionContinuation: Int
) {
    runtimeContinuationState(from: continuation)?.resetResumeState()
    startUninterceptedCoroutineFromResume(
        entryPointRaw: entryPointRaw,
        continuation: continuation,
        completionContinuation: completionContinuation
    )
}

private func startCoroutineUninterceptedOrReturn(
    entryPointRaw: Int,
    continuation: Int,
    completionContinuation: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let entryPoint = suspendEntryPoint(from: entryPointRaw) else {
        outThrown?.pointee = 0
        _ = kk_coroutine_state_exit(continuation, 0)
        return 0
    }
    guard let state = runtimeContinuationState(from: continuation) else {
        outThrown?.pointee = 0
        return 0
    }

    let outerTaskKey = RuntimeCoroutineScopeTaskKey.installedKey
    let outerJob = RuntimeJobHandle.current
    let taskKey = RuntimeCoroutineScopeTaskKey.installFreshKey()
    RuntimeCoroutineScope.installScope(state.scope, forTask: taskKey)
    RuntimeContinuationState.installState(state, forTask: taskKey)
    RuntimeJobHandle.current = state.jobHandle
    defer {
        RuntimeCoroutineScope.removeScope(forTask: taskKey)
        RuntimeContinuationState.removeCurrent(forTask: taskKey)
        RuntimeCoroutineScopeTaskKey.restoreKey(outerTaskKey)
        RuntimeJobHandle.current = outerJob
    }

    let suspendedToken = Int(bitPattern: kk_coroutine_suspended())
    var thrownValue = 0
    var result: Int
    repeat {
        thrownValue = 0
        state.consumeCancellableDelivery()
        result = entryPoint(continuation, &thrownValue)
        // Immediate child failures return the sentinel to reach the caller's catch label.
        // Deliver that pending exception inline instead of manufacturing a suspension.
    } while thrownValue == 0 && result == suspendedToken && state.consumePendingExceptionalResume()
    if thrownValue != 0 {
        outThrown?.pointee = thrownValue
        state.thrownException = thrownValue
        _ = kk_coroutine_state_exit(continuation, 0)
        return 0
    }

    if result != suspendedToken {
        outThrown?.pointee = 0
        return result
    }

    outThrown?.pointee = 0
    state.installResumeContinuation {
        continueUninterceptedCoroutineToCompletion(
            entryPointRaw: entryPointRaw,
            continuation: continuation,
            completionContinuation: completionContinuation
        )
    }
    return suspendedToken
}

@_cdecl("kk_coroutine_state_enter")
public func kk_coroutine_state_enter(_ continuation: Int, _ functionID: Int) -> Int {
    guard let state = runtimeContinuationState(from: continuation) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_coroutine_state_enter received invalid continuation handle")
    }
    let functionIDValue = Int64(functionID)
    if state.functionID != functionIDValue {
        state.functionID = functionIDValue
        state.label = 0
        state.completion = 0
        state.thrownException = 0
        state.spillSlots.removeAll(keepingCapacity: false)
    }
    return Int(state.label)
}

@_cdecl("kk_coroutine_state_set_label")
public func kk_coroutine_state_set_label(_ continuation: Int, _ label: Int) -> Int {
    guard let state = runtimeContinuationState(from: continuation) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_coroutine_state_set_label received invalid continuation handle")
    }
    state.label = Int64(label)
    return label
}

@_cdecl("kk_coroutine_state_exit")
public func kk_coroutine_state_exit(_ continuation: Int, _ value: Int) -> Int {
    runtimeContinuationState(from: continuation)?.releaseInterception(continuationRaw: continuation)
    _ = runtimeReleaseObject(continuation)
    return value
}

@_cdecl("kk_coroutine_state_set_spill")
public func kk_coroutine_state_set_spill(_ continuation: Int, _ slot: Int, _ value: Int) -> Int {
    guard let state = runtimeContinuationState(from: continuation) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_coroutine_state_set_spill received invalid continuation handle")
    }
    state.spillSlots[Int64(slot)] = Int64(value)
    return value
}

@_cdecl("kk_coroutine_state_get_spill")
public func kk_coroutine_state_get_spill(_ continuation: Int, _ slot: Int) -> Int {
    guard let state = runtimeContinuationState(from: continuation) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_coroutine_state_get_spill received invalid continuation handle")
    }
    return Int(state.spillSlots[Int64(slot)] ?? 0)
}

@_cdecl("kk_coroutine_state_set_completion")
public func kk_coroutine_state_set_completion(_ continuation: Int, _ value: Int) -> Int {
    guard let state = runtimeContinuationState(from: continuation) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_coroutine_state_set_completion received invalid continuation handle")
    }
    state.completion = Int64(value)
    return value
}

@_cdecl("kk_coroutine_state_get_completion")
public func kk_coroutine_state_get_completion(_ continuation: Int) -> Int {
    guard let state = runtimeContinuationState(from: continuation) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_coroutine_state_get_completion received invalid continuation handle")
    }
    return Int(state.completion)
}

@_cdecl("kk_coroutine_state_get_thrown_exception")
public func kk_coroutine_state_get_thrown_exception(_ continuation: Int) -> Int {
    guard let state = runtimeContinuationState(from: continuation) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_coroutine_state_get_thrown_exception received invalid continuation handle")
    }
    return state.thrownException
}

@_cdecl("kk_coroutine_continuation_context")
public func kk_coroutine_continuation_context(_ continuation: Int) -> Int {
    __kk_coroutine_continuation_context(continuation, nil)
}

@_cdecl("__kk_coroutine_continuation_context")
public func __kk_coroutine_continuation_context(
    _ continuation: Int,
    _ outThrown: UnsafeMutablePointer<Int>? = nil
) -> Int {
    outThrown?.pointee = 0
    // Continuation has one function slot (resumeWith), followed by context's getter.
    let sourceGetter = kk_itable_lookup_dynamic(
        continuation, Int(runtimeStableNominalTypeID(fqName: "kotlin.coroutines.Continuation")), 1
    )
    if sourceGetter != 0 {
        let getter = unsafeBitCast(sourceGetter, to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self)
        var thrown = 0
        let result = getter(continuation, &thrown)
        if let outThrown {
            outThrown.pointee = thrown
        } else if thrown != 0 {
            _ = kk_native_processUnhandledException(thrown, nil)
        }
        return result
    }
    guard let continuationPtr = UnsafeMutableRawPointer(bitPattern: continuation) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_coroutine_continuation_context received invalid continuation handle")
    }
    if let callbackContinuation = tryCast(continuationPtr, to: RuntimeCallbackContinuation.self) {
        return Int(bitPattern: callbackContinuation.context)
    }
    if isRegisteredRuntimeObjectPointer(continuation),
       let nativeContinuation = Unmanaged<AnyObject>.fromOpaque(continuationPtr).takeUnretainedValue() as? KKContinuation
    {
        return Int(bitPattern: nativeContinuation.context)
    }
    guard let state = runtimeContinuationState(from: continuation) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_coroutine_continuation_context received invalid continuation handle")
    }
    return state.generatedCoroutineContext(outThrown: outThrown)
        ?? runtimeRegisterObject(state.makeContinuationContext())
}

@_cdecl("kk_coroutine_current_context")
public func kk_coroutine_current_context() -> Int {
    // KUU-1387: the current continuation state's context is the canonical one
    // for its content. With no continuation state (boxed suspend bodies that
    // install only a scope), the installed scope's own context object is the
    // ambient context; a shared empty context is the last resort. All three
    // return a canonical object so repeated reads stay `===`-stable.
    let context = RuntimeContinuationState.current?.makeContinuationContext()
        ?? RuntimeCoroutineScope.current?.context
        ?? RuntimeCoroutineContext()
    return runtimeRegisterObject(runtimeCanonicalCoroutineContext(context))
}

@_cdecl("kk_coroutine_continuation_factory")
public func kk_coroutine_continuation_factory(_ contextRaw: Int, _ resumeWithRaw: Int) -> Int {
    runtimeRegisterObject(RuntimeCallbackContinuation(contextRaw: contextRaw, resumeWithRaw: resumeWithRaw))
}

@_cdecl("kk_coroutine_continuation_resume_with")
public func kk_coroutine_continuation_resume_with(_ continuation: Int, _ resultRaw: Int) {
    __kk_coroutine_continuation_resume_with(continuation, resultRaw, nil)
}

@_cdecl("__kk_coroutine_continuation_resume_with")
public func __kk_coroutine_continuation_resume_with(
    _ continuation: Int,
    _ resultRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>? = nil
) {
    outThrown?.pointee = 0
    let sourceResume = kk_itable_lookup_dynamic(
        continuation, Int(runtimeStableNominalTypeID(fqName: "kotlin.coroutines.Continuation")), 0
    )
    if sourceResume != 0 {
        let resume = unsafeBitCast(sourceResume, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Void).self)
        var thrown = 0
        resume(continuation, resultRaw, &thrown)
        if let outThrown {
            outThrown.pointee = thrown
        } else if thrown != 0 {
            _ = kk_native_processUnhandledException(thrown, nil)
        }
        return
    }
    guard let continuationPtr = UnsafeMutableRawPointer(bitPattern: continuation) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_coroutine_continuation_resume_with received invalid continuation handle")
    }
    if let callbackContinuation = tryCast(continuationPtr, to: RuntimeCallbackContinuation.self) {
        callbackContinuation.resumeWith(UnsafeMutableRawPointer(bitPattern: resultRaw), outThrown: outThrown)
        return
    }
    if isRegisteredRuntimeObjectPointer(continuation),
       let nativeContinuation = Unmanaged<AnyObject>.fromOpaque(continuationPtr).takeUnretainedValue() as? KKContinuation
    {
        nativeContinuation.resumeWith(UnsafeMutableRawPointer(bitPattern: resultRaw))
        return
    }
    guard let state = runtimeContinuationState(from: continuation) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_coroutine_continuation_resume_with received invalid continuation handle")
    }

    if let start = state.takeUninterceptedCoroutineStart() {
        if resultRaw != 0,
           let resultPtr = UnsafeMutableRawPointer(bitPattern: resultRaw),
           let resultBox = tryCast(resultPtr, to: RuntimeResultBox.self),
           !resultBox.isSuccess
        {
            state.releaseInterception(continuationRaw: continuation)
            if start.completionContinuation != 0 {
                __kk_coroutine_continuation_resume_with(
                    start.completionContinuation,
                    runtimeResultFailure(resultBox.exception),
                    outThrown
                )
            }
            _ = kk_coroutine_state_exit(continuation, 0)
            return
        }
        startUninterceptedCoroutineFromResume(
            entryPointRaw: start.entryPointRaw,
            continuation: continuation,
            completionContinuation: start.completionContinuation,
            outThrown: outThrown
        )
        return
    }

    if resultRaw != 0,
       let resultPtr = UnsafeMutableRawPointer(bitPattern: resultRaw),
       let resultBox = tryCast(resultPtr, to: RuntimeResultBox.self)
    {
        let ise: Int?
        if resultBox.isSuccess {
            ise = state.resume(with: resultBox.value)
        } else {
            ise = state.resume(withException: resultBox.exception)
        }
        if let ise {
            state.deliverDoubleResumeException(ise)
        }
        return
    }

    if let ise = state.resume(with: resultRaw) {
        state.deliverDoubleResumeException(ise)
    }
}

@_cdecl("kk_coroutine_continuation_resume")
public func kk_coroutine_continuation_resume(
    _ continuation: Int,
    _ value: Int
) {
    __kk_coroutine_continuation_resume_with(continuation, runtimeResultSuccess(value), nil)
}

@_cdecl("kk_coroutine_continuation_resume_with_exception")
public func kk_coroutine_continuation_resume_with_exception(
    _ continuation: Int,
    _ exception: Int
) {
    __kk_coroutine_continuation_resume_with(continuation, runtimeResultFailure(exception), nil)
}

@_cdecl("kk_kxmini_run_blocking")
public func kk_kxmini_run_blocking(
    _ entryPointRaw: Int,
    _ functionID: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    // Create a job handle for runBlocking so that cancellation is observable
    // via kk_coroutine_check_cancellation, which requires state.jobHandle to
    // be non-nil.  Without this, calling cancel() inside runBlocking would
    // silently succeed but subsequent suspension points (e.g. delay()) would
    // never observe the cancellation.
    let job = RuntimeJobHandle()
    job.debugName = "BlockingCoroutine"
    return runSuspendEntryLoop(
        entryPointRaw: entryPointRaw,
        functionID: functionID,
        jobHandle: job,
        outThrown: outThrown
    )
}

/// Starts a launched coroutine body without parking the thread that runs it.
///
/// Every fire-and-forget launcher (`launch`, `async`, `produce`,
/// `CoroutineScope.launch`) used to drive its body through the suspend-entry
/// loop's *synchronous* path, which parks the running thread on a completion
/// semaphore until the whole body finishes. That is fatal once the body runs on
/// a `runBlocking` event loop: the parked thread is the only one that
/// can run the body's own queued resumptions, so it would deadlock itself. The
/// async path instead returns as soon as the body suspends and reports the
/// outcome through `onFinished`, leaving the loop free to run the next task.
///
/// `scope`/`job` are the launching coroutine's, propagated so nested
/// `launch`/`async` inside the body discover their parent. The suspend-entry
/// loop installs its own task-local copies from the continuation immediately
/// afterwards and cleans them up when the body completes.
func runtimeStartLaunchedBody(
    entryPointRaw: Int,
    continuation: Int,
    scope: RuntimeCoroutineScope?,
    job: RuntimeJobHandle?,
    onFinished: @escaping @Sendable (_ result: Int, _ thrown: Int) -> Void
) {
    let previousScope = RuntimeCoroutineScope.current
    let previousJob = RuntimeJobHandle.current
    defer {
        RuntimeCoroutineScope.current = previousScope
        RuntimeJobHandle.current = previousJob
    }
    RuntimeCoroutineScope.current = scope
    RuntimeJobHandle.current = job
    _ = runSuspendEntryLoopWithContinuation(
        entryPointRaw: entryPointRaw,
        continuation: continuation,
        onCompletion: onFinished
    )
}

@_cdecl("kk_kxmini_launch")
public func kk_kxmini_launch(_ entryPointRaw: Int, _ functionID: Int) -> Int {
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

    let workItem = DispatchWorkItem {
        // Mark the body as started on the dispatch thread, then re-check
        // cancellation. A cancel() that wins before the work item executes
        // completes the scheduled job immediately; if cancellation happens
        // between markStarted() and the guard below, the body is skipped here.
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
            // Report the thrown exception so one escaping the launched body
            // (including CancellationException from cooperative cancellation)
            // completes the job exceptionally instead of being silently
            // discarded as a normal `0` result.
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
