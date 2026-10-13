import Dispatch
import Foundation

// MARK: - Coroutine yield()

/// Cooperatively yields the current coroutine, allowing other coroutines to run.
/// This is the lowering target for `kotlinx.coroutines.yield()`.
@_cdecl("kk_coroutine_yield")
public func kk_coroutine_yield(_ continuation: Int) -> Int {
    guard let state = runtimeContinuationState(from: continuation) else {
        return 0
    }
    if state.isBoundToEventLoop {
        // Resume synchronously here. No continuation is installed
        // mid-burst, so this only records a pending resume signal; the
        // suspension handler in runSuspendEntryLoopWithContinuation first
        // flushes the coroutines this burst launched and then installs, which
        // queues this coroutine at the TAIL behind them. That is exactly
        // kotlinx.coroutines' `yield()`: re-dispatch to the end of the event
        // loop's queue, giving every already-queued coroutine a turn first.
        _ = state.resume(with: 0)
    } else {
        // Unbound (dispatcher-bound body, or a direct runtime call from a
        // test): there is no queue to append to, so fall back to the original
        // short-delay re-dispatch onto the global pool, which at least lets
        // other dispatched coroutines get a turn.
        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(1)) { [weak state] in
            _ = state?.resume(with: 0)
        }
    }
    return Int(bitPattern: kk_coroutine_suspended())
}

// MARK: - withTimeout / withTimeoutOrNull

/// Runs a timeout block on a deadline, preserving its result or failure unless
/// this deadline expires first.
///
/// BUG-190: the block runs on its own *child* continuation seeded from the caller,
/// never on the caller's continuation. When the deadline expires the block's entry
/// loop is abandoned while still suspended (e.g. inside `delay()`); sharing the
/// caller's continuation state meant that loop's pending timer later fired a
/// `signalResume()` on the caller, spuriously resuming the caller's *next* suspend
/// point (e.g. `job.join()`) a second time. Two concurrent resumptions of the same
/// body then let one of them signal the completion gate early, so `runBlocking`
/// returned -- and the process exited -- while statements after the join were still
/// running or had not run at all.
private func runTimeoutBlock(
    timeoutMillis: Int,
    entryPointRaw: Int,
    continuation: Int
) -> (timedOut: Bool, result: Int, thrown: Int) {
    let scopeHandle = kk_coroutine_scope_new()
    let scope = Unmanaged<RuntimeCoroutineScope>.fromOpaque(
        UnsafeMutableRawPointer(bitPattern: scopeHandle)!
    ).takeUnretainedValue()

    let blockContinuation = kk_coroutine_continuation_new(entryPointRaw)
    let blockJob = RuntimeJobHandle()
    blockJob.debugName = "TimeoutCoroutine"
    if let blockState = runtimeContinuationState(from: blockContinuation) {
        blockState.launcherArgs = runtimeContinuationState(from: continuation)?.launcherArgs ?? [:]
        blockState.scope = scope
        blockState.jobHandle = blockJob
        blockJob.continuationState = blockState
    }
    blockJob.markStarted()

    final class ResultBox: @unchecked Sendable {
        var value = 0
        var thrown = 0
    }
    let resultBox = ResultBox()
    let deadline = DispatchTime.now() + .milliseconds(timeoutMillis)

    let workItem = DispatchWorkItem {
        resultBox.value = runSuspendEntryLoopWithContinuation(
            entryPointRaw: entryPointRaw,
            continuation: blockContinuation,
            outThrown: &resultBox.thrown
        )
        if resultBox.thrown != 0 {
            scope.cancel()
        }
    }
    // The block itself runs off-loop (on the global pool) so its suspensions
    // never depend on the caller's queue. The caller, though, may be draining a
    // runBlocking event loop; parking it with `workItem.wait` would stall every
    // sibling coroutine -- and any queued work the block waits for -- for the
    // whole timeout, so drain against the work item's completion instead.
    let timedOut: Bool
    if let loop = RuntimeEventLoop.current {
        let finished = RuntimeCompletionFlag()
        workItem.notify(queue: DispatchQueue.global()) {
            finished.set()
            loop.wake()
        }
        DispatchQueue.global().async(execute: workItem)
        timedOut = !loop.run(
            until: { finished.isSet },
            deadline: Date().addingTimeInterval(Double(timeoutMillis) / 1000.0)
        )
    } else {
        DispatchQueue.global().async(execute: workItem)
        timedOut = workItem.wait(timeout: deadline) == .timedOut
    }
    if timedOut {
        workItem.cancel()
        // Cancel the block's own job so an abandoned, still-suspended body observes
        // cancellation cooperatively and unwinds instead of running to completion.
        blockJob.cancel(message: "TimeoutCancellationException")
        scope.cancel()
        _ = kk_coroutine_scope_wait(scopeHandle)
        return (true, 0, 0)
    }
    let childFailure = kk_coroutine_scope_wait(scopeHandle)
    let childThrown = childFailure == runtimeNullSentinelInt ? 0 : childFailure
    let thrown = resultBox.thrown != 0 ? resultBox.thrown : childThrown
    return (false, thrown == 0 ? resultBox.value : 0, thrown)
}

/// Runs the given block with a timeout. If the block does not complete within
/// `timeoutMillis`, a `TimeoutCancellationException` is reported through the
/// `outThrown` ABI channel so enclosing Kotlin `try`/`catch` can observe it.
/// Used as the lowering target for `withTimeout(timeMillis) { }`.
///
/// This used to `runtimeStructuredPanic` on expiry, which made the timeout an
/// uncatchable trap: `catch (e: TimeoutCancellationException)` (and even
/// `catch (e: CancellationException)`) could not be expressed. Only the *caller's*
/// job is left untouched here -- the expired block's own job is already cancelled
/// by `runTimeoutBlock` -- so `runBlocking` keeps running statements after the
/// catch, matching kotlinx.coroutines.
@_cdecl("kk_with_timeout")
public func kk_with_timeout(
    _ timeoutMillis: Int,
    _ entryPointRaw: Int,
    _ continuation: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let outcome = runTimeoutBlock(
        timeoutMillis: timeoutMillis,
        entryPointRaw: entryPointRaw,
        continuation: continuation
    )
    if outcome.timedOut {
        outThrown?.pointee = runtimeAllocateTimeoutCancellationException(
            timeoutMillis: timeoutMillis
        )
        return 0
    }
    outThrown?.pointee = outcome.thrown
    return outcome.result
}

/// Legacy non-throwing ABI; new Kotlin calls use the throwing bridge below.
@_cdecl("kk_with_timeout_or_null")
public func kk_with_timeout_or_null(_ timeoutMillis: Int, _ entryPointRaw: Int, _ continuation: Int) -> Int {
    kk_with_timeout_or_null_throwing(timeoutMillis, entryPointRaw, continuation, nil)
}

/// Returns null only for this deadline's expiry; block failures propagate unchanged.
@_cdecl("kk_with_timeout_or_null_throwing")
public func kk_with_timeout_or_null_throwing(
    _ timeoutMillis: Int,
    _ entryPointRaw: Int,
    _ continuation: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let outcome = runTimeoutBlock(
        timeoutMillis: timeoutMillis,
        entryPointRaw: entryPointRaw,
        continuation: continuation
    )
    if outcome.timedOut {
        // Use the shared null-sentinel convention (see e.g. RuntimeRangeAndDispatch's
        // `orNull` helpers) rather than raw 0, which is a valid unboxed Int result and
        // would otherwise be indistinguishable from "no value" when printed/compared.
        return runtimeNullSentinelInt
    }
    outThrown?.pointee = outcome.thrown
    return outcome.result
}

// MARK: - Suspend Entry Loop

func runSuspendEntryLoop(
    entryPointRaw: Int,
    functionID: Int,
    jobHandle: RuntimeJobHandle? = nil,
    outThrown: UnsafeMutablePointer<Int>? = nil
) -> Int {
    guard suspendEntryPoint(from: entryPointRaw) != nil else {
        return 0
    }
    let continuation = kk_coroutine_continuation_new(functionID)
    if let jobHandle, let state = runtimeContinuationState(from: continuation) {
        jobHandle.continuationState = state
        state.jobHandle = jobHandle
        jobHandle.markStarted()
    }
    return runtimeRunBlockingOnEventLoop(
        entryPointRaw: entryPointRaw,
        continuation: continuation,
        outThrown: outThrown
    )
}

/// Drives a `runBlocking` body on a single-threaded FIFO event loop, draining
/// that loop on the calling thread until the body completes.
///
/// This mirrors `kotlinx.coroutines`' `runBlocking`, which installs a
/// `BlockingEventLoop` for the body and every child launched into it and then
/// drains it on the calling thread. Two consequences are load-bearing:
///
/// - Children launched into the body run *on this thread*, in queue order, so
///   the interleaving of their output is determined by the queue rather than
///   by the concurrent global pool.
/// - An already-draining loop is REUSED rather than nested behind a fresh one.
///   `kk_kxmini_run_blocking_with_cont` also drives `suspend () -> R` values
///   invoked from inside a coroutine; a second loop there would strand any job
///   the invoked block joins that is queued on the outer loop.
func runtimeRunBlockingOnEventLoop(
    entryPointRaw: Int,
    continuation: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let previousLoop = RuntimeEventLoop.current
    let previousTaskKey = RuntimeCoroutineScopeTaskKey.currentTaskKey
    let previousJob = RuntimeJobHandle.current
    let loop = previousLoop ?? RuntimeEventLoop()
    RuntimeEventLoop.current = loop
    defer {
        RuntimeEventLoop.current = previousLoop
        RuntimeCoroutineScopeTaskKey.installKey(previousTaskKey)
        RuntimeJobHandle.current = previousJob
    }

    let state = runtimeContinuationState(from: continuation)
    state?.eventLoop = loop
    // A fresh blocking coroutine owns its children's lifetime. Suspend-value
    // launcher thunks borrow an existing scope instead; joining that scope
    // here would wait for the very actor/producer executing this thunk.
    let ownedScope = state != nil && state?.scope == nil ? RuntimeCoroutineScope() : nil
    if let ownedScope {
        state?.scope = ownedScope
        // The owned scope's job is this blocking coroutine's job, so suspend
        // values invoked inside it keep observing `coroutineContext.job`
        // (KUU-964) and a scope cancel reaches the job itself.
        if let job = state?.jobHandle {
            ownedScope.adoptJob(job)
        }
    }

    final class Outcome: @unchecked Sendable {
        private let lock = NSLock()
        private var finished = false
        private var result = 0
        private var thrown = 0

        func complete(result: Int, thrown: Int) {
            lock.lock()
            finished = true
            self.result = result
            self.thrown = thrown
            lock.unlock()
        }

        var isFinished: Bool {
            lock.lock()
            defer { lock.unlock() }
            return finished
        }

        func snapshot() -> (result: Int, thrown: Int) {
            lock.lock()
            defer { lock.unlock() }
            return (result, thrown)
        }
    }
    let outcome = Outcome()

    // Async path: the entry loop returns as soon as the body suspends, so the
    // drain below -- not a parked thread -- is what carries it to completion.
    _ = runSuspendEntryLoopWithContinuation(
        entryPointRaw: entryPointRaw,
        continuation: continuation,
        onCompletion: { result, thrown in
            outcome.complete(result: result, thrown: thrown)
            loop.wake()
        }
    )
    loop.run(until: { outcome.isFinished })

    let (result, bodyThrown) = outcome.snapshot()
    // A child can fail first and cause the body to throw during cancellation.
    // Keep that original failure even if a catch/finally throws another error.
    let priorChildFailure = ownedScope?.childFailureSnapshot() ?? 0
    if bodyThrown != 0 {
        ownedScope?.cancel()
    }
    // Job/Deferred values may escape through the block's result or captures.
    // Joining only consumes the scope's retain, not the live Kotlin handle.
    let childThrown = ownedScope?.waitForChildren(releaseOriginalHandles: false) ?? 0
    let thrown = priorChildFailure != 0 ? priorChildFailure
        : (childThrown != 0 && (bodyThrown == 0 || kk_is_cancellation_exception(bodyThrown) != 0)
            ? childThrown : bodyThrown)
    // Same contract as the previous synchronous path: report the failure
    // through `outThrown` and hand back 0 as the value.
    outThrown?.pointee = thrown
    return thrown != 0 ? 0 : result
}

/// When `onCompletion` is nil, this runs the synchronous path and blocks the
/// caller on `completionGate`.
/// When `onCompletion` is non-nil, this starts the loop, returns immediately,
/// and invokes the callback on completion without blocking a dispatcher thread.
func runSuspendEntryLoopWithContinuation(
    entryPointRaw: Int,
    continuation: Int,
    outThrown: UnsafeMutablePointer<Int>? = nil,
    onCompletion: (@Sendable (_ result: Int, _ thrown: Int) -> Void)? = nil
) -> Int {
    guard let entryPoint = suspendEntryPoint(from: entryPointRaw) else {
        outThrown?.pointee = 0
        _ = kk_coroutine_state_exit(continuation, 0)
        onCompletion?(0, 0)
        return 0
    }

    // CORO-004: Continuation-based suspend/resume.
    //
    // Instead of blocking a GCD thread on DispatchSemaphore.wait() when the
    // coroutine suspends, we use a DispatchSemaphore only at the *outermost*
    // level (the completion gate) and install a non-blocking continuation
    // closure for each internal suspend point.
    //
    // Flow:
    //   1. The loop runs the entry point.
    //   2. If it returns COROUTINE_SUSPENDED, install a continuation closure
    //      on the RuntimeContinuationState.  This closure will re-enter the
    //      loop when signalResume() fires (from a timer, cancellation, etc.).
    //      The current GCD thread is released — no blocking.
    //   3. When the resume closure fires, it repeats from step 1.
    //   4. When the entry point returns a concrete value (not suspended) or
    //      throws, signal the completion gate (sync path) or invoke onCompletion
    //      (async path) so the caller is unblocked / notified.
    //
    // The completion gate semaphore is only used by the synchronous path
    // (runBlocking, join, await).  The async path (onCompletion != nil) never
    // blocks any GCD thread — the completion callback is invoked instead.

    // Sync path only: gate and result box.
    let completionGate: DispatchSemaphore? = onCompletion == nil ? DispatchSemaphore(value: 0) : nil
    // Companion to `completionGate` for the case where the *caller* is draining
    // a runBlocking event loop: parking on the semaphore there would stall the
    // only thread able to run the queued work this coroutine waits for, so the
    // sync path drains the loop against this predicate instead.
    let syncCompleted = RuntimeCompletionFlag()
    final class ResultBox: @unchecked Sendable { var value: Int = 0 }
    let resultBox = ResultBox()

    // CORO-003: Install the scope carried by this continuation into the
    // task-scope map so that child launches dispatched on this thread can
    // discover their parent scope without TLS.
    let contState = runtimeContinuationState(from: continuation)
    // Bind this coroutine to the runBlocking event loop draining the current
    // thread, if any, so every later resumption hop is queued on it. A body
    // dispatched onto a real dispatcher queue (`withContext(Dispatchers.IO)`,
    // `launch(Dispatchers.Default)`) starts here on a pool thread where
    // `current` is nil and therefore stays unbound, keeping its previous
    // global-pool behaviour.
    let callerEventLoop = RuntimeEventLoop.current
    if let contState, contState.eventLoop == nil {
        contState.eventLoop = callerEventLoop
    }
    let boundEventLoop = contState?.eventLoop
    // Capture this thread's ambient bindings before minting a fresh key so a
    // nested loop (e.g. a `coroutineScope { }` block's entry loop) hands them
    // back on exit (KUU-964).
    let outerTaskKey = RuntimeCoroutineScopeTaskKey.installedKey
    let outerJob = RuntimeJobHandle.current
    let currentTaskKey = RuntimeCoroutineScopeTaskKey.installFreshKey()
    RuntimeCoroutineScope.installScope(contState?.scope, forTask: currentTaskKey)
    RuntimeContinuationState.installState(contState, forTask: currentTaskKey)
    RuntimeJobHandle.current = contState?.jobHandle

    let suspendedToken = Int(bitPattern: kk_coroutine_suspended())

    // The loop body is factored into a closure so it can be re-entered from
    // the resume continuation without recursion or blocking.
    //
    // Using a box to hold the closure so it can reference itself.
    final class LoopBodyBox: @unchecked Sendable {
        var body: (() -> Void)?
    }
    let loopBodyBox = LoopBodyBox()

    // Shared mutable state for the task key, protected by the single-shot
    // continuation model (only one invocation of the loop body runs at a time).
    // `outerKey`/`outerJob` hold the ambient bindings this loop displaced —
    // captured per burst so that, whichever thread a burst ends on, exiting
    // the loop hands back that thread's previous ambient state instead of
    // leaving the thread keyless (KUU-964).
    final class TaskKeyBox: @unchecked Sendable {
        var key: RuntimeTaskKey
        var outerKey: RuntimeTaskKey?
        var outerJob: RuntimeJobHandle?
        init(key: RuntimeTaskKey) { self.key = key }
    }
    let taskKeyBox = TaskKeyBox(key: currentTaskKey)
    taskKeyBox.outerKey = outerTaskKey
    taskKeyBox.outerJob = outerJob

    loopBodyBox.body = {
        // Run every burst -- the initial one kicked off below and each resumed
        // one -- with the bound event loop installed, so a `launch{}` inside
        // the body and the pending-launch flush at the bottom queue onto it
        // rather than onto the global pool.
        let outerEventLoop = RuntimeEventLoop.current
        RuntimeEventLoop.current = boundEventLoop ?? outerEventLoop
        defer { RuntimeEventLoop.current = outerEventLoop }
        // BUG-041: mark this thread as synchronously running a coroutine body
        // for the duration of `entryPoint`'s call below, so RuntimePendingLaunchQueue
        // knows any `launch{}` it makes has a real burst to be flushed at.
        RuntimeCoroutineBurstDepth.enter()
        contState?.consumeCancellableDelivery()
        var thrownValue = 0
        let result = entryPoint(continuation, &thrownValue)
        if thrownValue != 0 {
            // BUG-041: this burst is ending (with a thrown exception); dispatch
            // anything it `launch`-ed for real now that no more synchronous
            // code on this thread can race a cancel() against them.
            RuntimeCoroutineBurstDepth.exit()
            RuntimePendingLaunchQueue.flush()
            RuntimeCoroutineScope.removeScope(forTask: taskKeyBox.key)
            RuntimeContinuationState.removeCurrent(forTask: taskKeyBox.key)
            RuntimeCoroutineScopeTaskKey.restoreKey(taskKeyBox.outerKey)
            RuntimeJobHandle.current = taskKeyBox.outerJob
            _ = kk_coroutine_state_exit(continuation, 0)
            // Record the thrown exception in the continuation state so callers
            // such as kk_kxmini_launch_with_exception_handler can reliably
            // distinguish a thrown exception from a normal (possibly non-zero)
            // return value without inspecting the object-pointer registry.
            contState?.thrownException = thrownValue
            if let onCompletion {
                loopBodyBox.body = nil
                onCompletion(0, thrownValue)
            } else {
                outThrown?.pointee = thrownValue
                resultBox.value = 0
                syncCompleted.set()
                completionGate?.signal()
                callerEventLoop?.wake()
            }
            return
        }
        if result != suspendedToken {
            // BUG-041: burst completed with a concrete result; flush before
            // signalling completion for the same reason as the thrown path.
            RuntimeCoroutineBurstDepth.exit()
            RuntimePendingLaunchQueue.flush()
            RuntimeCoroutineScope.removeScope(forTask: taskKeyBox.key)
            RuntimeContinuationState.removeCurrent(forTask: taskKeyBox.key)
            RuntimeCoroutineScopeTaskKey.restoreKey(taskKeyBox.outerKey)
            RuntimeJobHandle.current = taskKeyBox.outerJob
            if let onCompletion {
                loopBodyBox.body = nil
                onCompletion(result, 0)
            } else {
                outThrown?.pointee = 0
                resultBox.value = result
                syncCompleted.set()
                completionGate?.signal()
                callerEventLoop?.wake()
            }
            return
        }
        guard let state = runtimeContinuationState(from: continuation) else {
            // BUG-041: defensive terminal fallback; flush for consistency with
            // the other exit paths above.
            RuntimeCoroutineBurstDepth.exit()
            RuntimePendingLaunchQueue.flush()
            RuntimeCoroutineScope.removeScope(forTask: taskKeyBox.key)
            RuntimeContinuationState.removeCurrent(forTask: taskKeyBox.key)
            RuntimeCoroutineScopeTaskKey.restoreKey(taskKeyBox.outerKey)
            RuntimeJobHandle.current = taskKeyBox.outerJob
            if let onCompletion {
                loopBodyBox.body = nil
                onCompletion(0, 0)
            } else {
                outThrown?.pointee = 0
                resultBox.value = 0
                syncCompleted.set()
                completionGate?.signal()
                callerEventLoop?.wake()
            }
            return
        }
        // BUG-041: this burst is suspending, so it's yielding the thread --
        // dispatch anything it `launch`-ed for real now, exactly like a
        // single-threaded Kotlin dispatcher would once the caller yields.
        //
        // This MUST run before `installResumeContinuation` below.
        // `yield()` resumes its own continuation synchronously during the
        // burst, which only records a pending signal because nothing is
        // installed yet; the install then re-queues this coroutine. Flushing
        // first therefore places the coroutines launched during this burst
        // AHEAD of the yielding one in the event loop's FIFO queue, which is
        // the order kotlinx.coroutines produces. Installing first inverted it.
        RuntimeCoroutineBurstDepth.exit()
        RuntimePendingLaunchQueue.flush()
        // CORO-004: Install a continuation closure instead of blocking.
        // When signalResume() fires, this closure is queued on the bound event
        // loop (or dispatched to a GCD global queue when unbound), re-entering
        // the loop without blocking any thread.
        state.installResumeContinuation {
            // CORO-003: After suspend/resume we are on a (possibly different)
            // GCD thread.  Re-install the task key so the scope map lookup
            // still works.
            RuntimeCoroutineScope.removeScope(forTask: taskKeyBox.key)
            RuntimeContinuationState.removeCurrent(forTask: taskKeyBox.key)
            // Resumed on a (possibly different) thread — capture that thread's
            // displaced ambient bindings so a burst ending here restores them.
            taskKeyBox.outerKey = RuntimeCoroutineScopeTaskKey.installedKey
            taskKeyBox.outerJob = RuntimeJobHandle.current
            let freshKey = RuntimeCoroutineScopeTaskKey.installFreshKey()
            taskKeyBox.key = freshKey
            RuntimeCoroutineScope.installScope(state.scope, forTask: freshKey)
            RuntimeContinuationState.installState(state, forTask: freshKey)
            RuntimeJobHandle.current = state.jobHandle
            // Reset stale resume state from the previous cycle before
            // re-entering the loop.  Must happen here (not before
            // installResumeContinuation) to avoid clearing a pending
            // signal meant for the current suspend point.
            state.resetResumeState()
            loopBodyBox.body?()
        }
        // The current thread is released here — no blocking.
    }

    // Kick off the first iteration synchronously on the current thread.
    loopBodyBox.body?()

    if let gate = completionGate {
        // Sync path: wait until the coroutine completes.
        if let loop = callerEventLoop {
            // The caller is draining a runBlocking event loop. Blocking it here
            // would deadlock whenever this coroutine's progress depends on work
            // queued on that same loop, so keep draining instead.
            loop.run(until: { syncCompleted.isSet })
        } else {
            gate.wait()
        }

        // Break the strong reference cycle: loopBodyBox -> closure -> loopBodyBox
        loopBodyBox.body = nil
        RuntimeCoroutineScope.removeScope(forTask: currentTaskKey)
        RuntimeContinuationState.removeState(forTask: currentTaskKey)
        RuntimeCoroutineScopeTaskKey.restoreKey(outerTaskKey)
        RuntimeJobHandle.current = outerJob

        return resultBox.value
    }

    // Async path: return immediately.  The resume continuation chain handles
    // global-map cleanup (currentTaskKey entries) when the loop eventually
    // completes.  Clean up only the initial thread's locals here.
    RuntimeCoroutineScopeTaskKey.restoreKey(outerTaskKey)
    RuntimeJobHandle.current = outerJob
    return 0
}

// MARK: - STDLIB-CORO-068: Suspend Function Invocation

/// Invoke a suspend function with 0 arguments using continuation-passing style.
/// This is the runtime implementation for `kk_suspend_function_invoke_0`.
@_silgen_name("kk_suspend_function_invoke_0")
public func kk_suspend_function_invoke_0(
    _ functionRaw: Int,
    _ continuation: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeInvokeSuspendFunction(functionRaw, arguments: [], continuation: continuation, outThrown: outThrown)
}

/// Invoke a suspend function with 1 argument using continuation-passing style.
/// This is the runtime implementation for `kk_suspend_function_invoke`.
@_silgen_name("kk_suspend_function_invoke")
public func kk_suspend_function_invoke(
    _ functionRaw: Int,
    _ arg: Int,
    _ continuation: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeInvokeSuspendFunction(functionRaw, arguments: [arg], continuation: continuation, outThrown: outThrown)
}

/// Invoke a suspend function with 2 arguments using the function-value ABI.
@_silgen_name("kk_suspend_function_invoke_2")
public func kk_suspend_function_invoke_2(
    _ functionRaw: Int,
    _ arg1: Int,
    _ arg2: Int,
    _ continuation: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeInvokeSuspendFunction(functionRaw, arguments: [arg1, arg2], continuation: continuation, outThrown: outThrown)
}

@_silgen_name("kk_suspend_function_invoke_3")
public func kk_suspend_function_invoke_3(
    _ functionRaw: Int,
    _ arg1: Int,
    _ arg2: Int,
    _ arg3: Int,
    _ continuation: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeInvokeSuspendFunction(functionRaw, arguments: [arg1, arg2, arg3], continuation: continuation, outThrown: outThrown)
}

@_silgen_name("kk_suspend_function_invoke_4")
public func kk_suspend_function_invoke_4(
    _ functionRaw: Int,
    _ arg1: Int,
    _ arg2: Int,
    _ arg3: Int,
    _ arg4: Int,
    _ continuation: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeInvokeSuspendFunction(functionRaw, arguments: [arg1, arg2, arg3, arg4], continuation: continuation, outThrown: outThrown)
}

@_silgen_name("kk_suspend_function_invoke_5")
public func kk_suspend_function_invoke_5(
    _ functionRaw: Int,
    _ arg1: Int,
    _ arg2: Int,
    _ arg3: Int,
    _ arg4: Int,
    _ arg5: Int,
    _ continuation: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeInvokeSuspendFunction(functionRaw, arguments: [arg1, arg2, arg3, arg4, arg5], continuation: continuation, outThrown: outThrown)
}

@_silgen_name("kk_suspend_function_invoke_6")
public func kk_suspend_function_invoke_6(
    _ functionRaw: Int,
    _ arg1: Int,
    _ arg2: Int,
    _ arg3: Int,
    _ arg4: Int,
    _ arg5: Int,
    _ arg6: Int,
    _ continuation: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeInvokeSuspendFunction(functionRaw, arguments: [arg1, arg2, arg3, arg4, arg5, arg6], continuation: continuation, outThrown: outThrown)
}
