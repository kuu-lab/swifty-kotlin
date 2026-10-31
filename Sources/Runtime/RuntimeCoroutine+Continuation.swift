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
        childState.inheritContinuationContext(from: callerContinuationRaw)
        childState.scope = callerState.scope
        childState.jobHandle = callerState.jobHandle
        childState.builderContext = callerState.builderContext
        childState.flowCollectContext = callerState.flowCollectContext
        childState.resumesInline = callerState.resumesInline
        childState.inheritCoroutineContext(from: callerState)
        if let scheduler = callerState.blockingScheduler {
            childState.blockingScheduler = scheduler
            childState.eventLoop = callerState.eventLoop
        }
        callerState.bindSuspendedCallChild(childState)
    }
    let completion = RuntimeDirectSuspendCompletion()
    _ = runSuspendEntryLoopWithContinuation(
        entryPointRaw: entryPointRaw,
        continuation: childContinuation,
        onCompletion: { result, thrown, resumeThrown in
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
                // Forward the resumer's thrown slot: when this signal drives the
                // caller synchronously to its own completion, an exception the
                // caller's completion continuation throws inside `resumeWith`
                // must propagate back to the original `resume` call site — the
                // single-call-stack behavior JVM `resume` exhibits (KUU-3783).
                callerState.signalResume(outThrown: resumeThrown)
            }
        }
    )
    let suspendedToken = Int(bitPattern: kk_coroutine_suspended())
    if let outcome = completion.markReturned() {
        if outcome.thrown != 0 {
            // The state machine reads the thrown exception after a resume.
            // The child already failed inside this call, so mark the delivery
            // inline: a suspend-entry loop then re-enters the machine within
            // this burst and the catch label runs before queued siblings can
            // drain state the failure was meant to discard (KUU-2724).
            callerState.markInlineExceptionalDelivery()
            callerState.signalResume()
            return suspendedToken
        }
        return outcome.result
    }
    return suspendedToken
}

/// KUU-3719: marks `childContinuation` as interception-transparent — emitted
/// before `kk_coroutine_call_direct_suspend` when the callee's suspending
/// calls are all in tail position. Such a callee owns no `ContinuationImpl`
/// of its own on JVM, so its suspend points bind the caller's continuation:
/// `suspendCoroutine`'s `intercepted()` on the child then reuses the caller's
/// interception instead of invoking the interceptor a second time.
@_cdecl("kk_coroutine_child_share_interception")
public func kk_coroutine_child_share_interception(
    _ childContinuation: Int,
    _ callerContinuationRaw: Int
) {
    guard let callerState = runtimeContinuationState(from: callerContinuationRaw),
          let childState = runtimeContinuationState(from: childContinuation)
    else {
        return
    }
    childState.bindInterceptionAnchor(callerState)
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

/// KUU-3884: generic `(continuation, outThrown)` entry point for a value
/// erased to `(P1..Pn, Continuation<R>) -> Any?` — JVM `Function{n+1}` —
/// invoked as `suspend (P1..Pn) -> R`. The coroutine builders spill the
/// function value itself into launcher slot 0 and the suspend arguments into
/// slots 1...n; the thunk appends the child continuation as the last
/// argument and reads the return like a suspend call: a non-suspended value
/// completes the coroutine, `COROUTINE_SUSPENDED` parks it until the erased
/// function resumes the continuation it received, and that resumed Result
/// then becomes the coroutine result. Two states, matching the label machine
/// JVM `createCoroutineFromSuspendFunction` synthesizes for a
/// non-`ContinuationImpl` receiver: label 0 invokes the erased function
/// exactly once, label 1 delivers the resumed value (or rethrows the resumed
/// exception) as the coroutine outcome.
private let runtimeErasedSuspendFunctionEntryPoint: KKSuspendEntryPoint = { continuationRaw, outThrown in
    let label = kk_coroutine_state_enter(continuationRaw, runtimeErasedSuspendFunctionEntryPointRaw)
    if label != 0 {
        let thrown = kk_coroutine_state_get_thrown_exception(continuationRaw)
        if thrown != 0 {
            outThrown?.pointee = thrown
            _ = kk_coroutine_state_exit(continuationRaw, 0)
            return 0
        }
        let result = kk_coroutine_state_get_completion(continuationRaw)
        outThrown?.pointee = 0
        return kk_coroutine_state_exit(continuationRaw, result)
    }
    _ = kk_coroutine_state_set_label(continuationRaw, 1)
    let functionRaw = Int(kk_coroutine_launcher_arg_get(continuationRaw, 0))
    let erasedArity: Int
    if let box = runtimeFunctionValueBox(from: functionRaw) {
        erasedArity = box.arity
    } else if let object = runtimeCallableObjectPair(from: functionRaw) {
        erasedArity = object.arity
    } else {
        erasedArity = 0
    }
    guard (1 ... 22).contains(erasedArity) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "Invalid erased suspend function value")
        _ = kk_coroutine_state_exit(continuationRaw, 0)
        return 0
    }
    var arguments: [Int] = []
    arguments.reserveCapacity(erasedArity)
    for index in 1 ..< erasedArity {
        arguments.append(Int(kk_coroutine_launcher_arg_get(continuationRaw, Int64(index))))
    }
    arguments.append(continuationRaw)
    var thrown = 0
    let result = runtimeInvokeErasedFunctionValue(
        functionRaw: functionRaw,
        arguments: arguments,
        outThrown: &thrown
    )
    if thrown != 0 {
        outThrown?.pointee = thrown
        _ = kk_coroutine_state_exit(continuationRaw, 0)
        return 0
    }
    if result != Int(bitPattern: kk_coroutine_suspended()) {
        outThrown?.pointee = 0
        return kk_coroutine_state_exit(continuationRaw, result)
    }
    outThrown?.pointee = 0
    return result
}

/// The erased-suspend thunk's address as a suspend entry point raw value.
/// Continuations driving the erased shape carry it as their `functionID`, so
/// `kk_coroutine_state_enter` sees a stable identity across resume hops.
let runtimeErasedSuspendFunctionEntryPointRaw = unsafeBitCast(
    runtimeErasedSuspendFunctionEntryPoint, to: Int.self
)

/// KUU-3884: whether a `suspend (P1..Pn) -> R` value is a plain erased
/// `Function{n+1}` — a `RuntimeFunctionValueBox` without a CPS entry point
/// whose arity is n+1 (`(P1..Pn, Continuation<R>) -> Any?`), or a nominal
/// `Function{n+1}` implementor. Such values take the generic erased-suspend
/// entry point above instead of a callable-box `suspendEntryPoint` or a
/// nominal `SuspendFunctionN` invoke launcher.
func runtimeErasedSuspendShape(functionRaw: Int, arity: Int) -> Bool {
    guard functionRaw != 0, (0 ... 21).contains(arity) else {
        return false
    }
    if let box = runtimeFunctionValueBox(from: functionRaw) {
        return box.suspendEntryPoint == 0 && box.arity == arity + 1
    }
    return runtimeCallableObjectPair(from: functionRaw, arity: arity + 1) != nil
}

/// The `(continuation, outThrown)` entry point for a dynamic suspend function
/// value: the callable box's suspend entry, or — for a nominal
/// `SuspendFunctionN` implementor (KUU-3802) — the invoke launcher thunk
/// codegen registered in the interface's reserved itable slot. The value's
/// leading launcher argument is also returned: the box's captured closure, or
/// the object itself as `invoke`'s receiver.
private func suspendCoroutineFunctionEntry(
    functionRaw: Int,
    arity: Int
) -> (entryPointRaw: Int, receiverRaw: Int)? {
    if let box = runtimeFunctionValueBox(from: functionRaw), box.suspendEntryPoint != 0 {
        guard box.arity == arity else {
            return nil
        }
        return (box.suspendEntryPoint, box.closureRaw)
    }
    let objectEntryRaw = runtimeSuspendInvokeEntryPoint(objectRaw: functionRaw, arity: arity)
    if objectEntryRaw != 0 {
        return (objectEntryRaw, functionRaw)
    }
    // KUU-3884: an erased `Function{n+1}` value (`(P1..Pn, Continuation<R>)
    // -> Any?`, the JVM shape) driven as `suspend (P1..Pn) -> R` goes through
    // the generic erased-suspend entry point. Launcher slot 0 spills the
    // value itself so the thunk resolves its invoke pair at call time.
    if runtimeErasedSuspendShape(functionRaw: functionRaw, arity: arity) {
        return (runtimeErasedSuspendFunctionEntryPointRaw, functionRaw)
    }
    return nil
}

/// Dynamic suspend function values keep their CPS entry point in the callable
/// box. Known symbols are still rewritten directly by coroutine lowering.
private func createCoroutineFromFunctionValue(_ functionRaw: Int, arguments: [Int], completion: Int) -> Int {
    guard let entry = suspendCoroutineFunctionEntry(functionRaw: functionRaw, arity: arguments.count) else {
        preconditionFailure("Coroutine builder requires a boxed suspend callable")
    }
    let continuation = kk_create_coroutine_unintercepted(entry.entryPointRaw, completion)
    for (index, argument) in ([entry.receiverRaw] + arguments).enumerated() {
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

/// Coroutine lowering rewrites calls whose function is a known entry point;
/// dynamic function values fall through to this entry.
@_cdecl("kk_start_coroutine_unintercepted_or_return_no_receiver")
public func kk_start_coroutine_unintercepted_or_return_no_receiver(
    _ functionRaw: Int,
    _ functionContextRaw: Int,
    _ completionContinuation: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let entry = suspendCoroutineFunctionEntry(functionRaw: functionRaw, arity: 0) else {
        preconditionFailure("Coroutine builder requires a boxed suspend callable")
    }
    let continuation = createCoroutineFromFunctionValue(
        functionRaw, arguments: [], completion: completionContinuation
    )
    return startCoroutineUninterceptedOrReturn(
        entryPointRaw: entry.entryPointRaw,
        continuation: continuation,
        completionContinuation: completionContinuation,
        outThrown: outThrown
    )
}

@_cdecl("kk_create_coroutine_unintercepted_with_receiver")
public func kk_create_coroutine_unintercepted_with_receiver(
    _ functionRaw: Int,
    _ functionContextRaw: Int,
    _ receiverRaw: Int,
    _ completionContinuation: Int
) -> Int {
    createCoroutineFromFunctionValue(functionRaw, arguments: [receiverRaw], completion: completionContinuation)
}

@_cdecl("kk_start_coroutine_unintercepted_or_return_with_receiver")
public func kk_start_coroutine_unintercepted_or_return_with_receiver(
    _ functionRaw: Int,
    _ functionContextRaw: Int,
    _ receiverRaw: Int,
    _ completionContinuation: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let entry = suspendCoroutineFunctionEntry(functionRaw: functionRaw, arity: 1) else {
        preconditionFailure("Coroutine builder requires a boxed suspend callable")
    }
    let continuation = createCoroutineFromFunctionValue(
        functionRaw, arguments: [receiverRaw], completion: completionContinuation
    )
    return startCoroutineUninterceptedOrReturn(
        entryPointRaw: entry.entryPointRaw,
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
    completionContinuation: Int,
    outThrown: UnsafeMutablePointer<Int>?
) {
    runtimeContinuationState(from: continuation)?.resetResumeState()
    startUninterceptedCoroutineFromResume(
        entryPointRaw: entryPointRaw,
        continuation: continuation,
        completionContinuation: completionContinuation,
        outThrown: outThrown
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
    state.suspendDriveEntryPointRaw = entryPointRaw

    let outerTaskKey = RuntimeCoroutineScopeTaskKey.installedKey
    let outerJob = RuntimeJobHandle.current
    let taskKey = RuntimeCoroutineScopeTaskKey.installFreshKey()
    RuntimeCoroutineScope.installScope(state.scope, forTask: taskKey)
    RuntimeContinuationState.installState(state, forTask: taskKey)
    RuntimeJobHandle.current = state.jobHandle
    defer {
        RuntimeCoroutineScope.removeScope(forTask: taskKey)
        RuntimeContinuationState.removeState(forTask: taskKey)
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
    state.installResumeContinuation { resumeThrown in
        continueUninterceptedCoroutineToCompletion(
            entryPointRaw: entryPointRaw,
            continuation: continuation,
            completionContinuation: completionContinuation,
            outThrown: resumeThrown
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
        state.clearSpillSlots()
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
    if let state = runtimeContinuationState(from: continuation) {
        state.markExited()
        RuntimeCoroutineDebugProbes.shared.remove(continuation: continuation)
        state.retireCancellableDeliveryOnExit()
        state.releaseInterception(continuationRaw: continuation)
    }
    _ = runtimeReleaseObject(continuation)
    return value
}

@_cdecl("kk_coroutine_state_set_spill")
public func kk_coroutine_state_set_spill(_ continuation: Int, _ slot: Int, _ value: Int) -> Int {
    guard let state = runtimeContinuationState(from: continuation) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_coroutine_state_set_spill received invalid continuation handle")
    }
    state.setSpillSlot(Int64(slot), value: Int64(value))
    return value
}

@_cdecl("kk_coroutine_state_get_spill")
public func kk_coroutine_state_get_spill(_ continuation: Int, _ slot: Int) -> Int {
    guard let state = runtimeContinuationState(from: continuation) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_coroutine_state_get_spill received invalid continuation handle")
    }
    return state.rootedSpillSlot(Int64(slot))
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
    return state.rootedCompletion()
}

@_cdecl("kk_coroutine_state_get_thrown_exception")
public func kk_coroutine_state_get_thrown_exception(_ continuation: Int) -> Int {
    guard let state = runtimeContinuationState(from: continuation) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_coroutine_state_get_thrown_exception received invalid continuation handle")
    }
    return state.takeThrownException()
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
    // KUU-1387: preserve the generated or inherited continuation context
    // object when the runtime has not added elements to it; otherwise expose
    // the canonical merged context. With no continuation state (boxed suspend
    // bodies that install only a scope), the installed scope's context is
    // ambient and a shared empty context is the last resort. Repeated reads
    // stay `===`-stable.
    if let state = RuntimeContinuationState.current {
        if let originalContext = state.unmodifiedCoroutineContextRaw() {
            return originalContext
        }
        let context = state.makeContinuationContext()
        if let sourceContext = state.generatedCoroutineContextIfMatching(context) {
            return sourceContext
        }
        return runtimeRegisterObject(runtimeCanonicalCoroutineContext(context))
    }
    let context = RuntimeCoroutineScope.current?.context ?? RuntimeCoroutineContext()
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
    let resultAccess = runtimeResultAccessFromRaw(resultRaw)
    defer { withExtendedLifetime(resultAccess) {} }
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
        if let access = resultAccess, !access.box.isSuccess
        {
            state.releaseInterception(continuationRaw: continuation)
            if start.completionContinuation != 0 {
                __kk_coroutine_continuation_resume_with(
                    start.completionContinuation,
                    runtimeResultFailure(access.box.exception),
                    outThrown
                )
            }
            _ = kk_coroutine_state_exit(continuation, 0)
            return
        }
        // KUU-2689: a MODE_CANCELLABLE start whose context Job is no longer
        // active at this resume boundary (inline or on the dispatcher queue)
        // completes the continuation with the job's CancellationException
        // without running the block.
        if start.cancellableStart,
           let cancellationException = state.unstartedCoroutineCancellationException()
        {
            state.releaseInterception(continuationRaw: continuation)
            if start.completionContinuation != 0 {
                __kk_coroutine_continuation_resume_with(
                    start.completionContinuation,
                    runtimeResultFailure(cancellationException),
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

    if let access = resultAccess {
        let resultBox = access.box
        let ise: Int?
        if resultBox.isSuccess {
            ise = state.resume(with: resultBox.value, outThrown: outThrown)
        } else {
            ise = state.resume(withException: resultBox.exception, outThrown: outThrown)
        }
        if let ise {
            state.deliverDoubleResumeException(ise)
        }
        return
    }

    if let ise = state.resume(with: resultRaw, outThrown: outThrown) {
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
        onCompletion: { result, thrown, _ in onFinished(result, thrown) }
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
