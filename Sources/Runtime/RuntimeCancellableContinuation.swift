import Foundation

private struct RuntimeCancellationCallback: Sendable {
    let fnPtr: Int
    let closureRaw: Int
    let native: (@Sendable (Int) -> Void)?

    init(fnPtr: Int, closureRaw: Int, native: (@Sendable (Int) -> Void)? = nil) {
        self.fnPtr = fnPtr
        self.closureRaw = closureRaw
        self.native = native
    }

    func invoke(_ cause: Int) {
        if let native {
            native(cause)
            return
        }
        guard fnPtr != 0 else { return }
        var thrown = 0
        _ = runtimeInvokeCollectionLambda1MaybeWrapped(
            fnPtr: fnPtr, closureRaw: closureRaw, value: cause, outThrown: &thrown
        )
        if thrown != 0 { _ = kk_native_processUnhandledException(thrown, nil) }
    }
}

private final class RuntimeResumeToken {}

final class RuntimeCancellableContinuation: @unchecked Sendable {
    private enum State { case active, reserved, completed, cancelled }
    private let lock = NSLock()
    private let delegate: Int
    private var delegateExited = false
    private var state: State = .active
    private var suspended = false
    private var delivered = false
    private var result: Int = 0
    private var cancelCause: Int = 0
    private var cancellationHandler: RuntimeCancellationCallback?
    private var resumeCancellation: RuntimeCancellationCallback?
    private var resumedAfterCancellation = false
    private var token: Int = 0
    private var idempotent: Int = runtimeNullSentinelInt
    private weak var parent: RuntimeJobHandle?
    private var parentHandlerID = 0

    init(delegate: Int) {
        self.delegate = delegate
    }

    func initParent() {
        let context = __kk_coroutine_continuation_context(delegate, nil)
        let jobRaw = kk_context_get_job(context)
        // A launch/async Job is represented by its task identity in the
        // coroutine context. Its cancellation state lives on completionJob.
        guard let job = runtimeJobHandle(from: jobRaw)
            ?? runtimeAsyncTask(from: jobRaw)?.completionJob else { return }
        lock.lock()
        guard !delegateExited else {
            lock.unlock()
            return
        }
        parent = job
        lock.unlock()
        let delegateState = runtimeContinuationState(from: delegate)
        let handlerID = job.addCompletionHandler(onCancelling: true) { [weak self, weak job, delegateState] cause in
            if cause != 0, cause != runtimeNullSentinelInt, let job {
                guard delegateState?.isExited != true else { return }
                self?.cancelFromParent(runtimeJobCancellationException(job))
            }
        }
        lock.lock()
        let delegateExited = self.delegateExited
        if !delegateExited { parentHandlerID = handlerID }
        lock.unlock()
        if delegateExited {
            job.removeCompletionHandler(id: handlerID)
            return
        }
        if job.cancellationSnapshot() || job.isFailedSnapshot() {
            cancelFromParent(runtimeJobCancellationException(job))
        }
    }

    var stateValue: Int {
        lock.lock()
        defer { lock.unlock() }
        switch state {
        case .active: return 0
        case .reserved, .completed: return 1
        case .cancelled: return 2
        }
    }

    private func dispatchResult(_ result: Int) {
        lock.lock()
        guard !delegateExited else {
            lock.unlock()
            return
        }
        // Resolve while holding the same lock that delegate exit uses to retire
        // this continuation. The temporary strong reference keeps the raw ABI
        // handle alive until resume_with has finished using it.
        let delegateState = runtimeContinuationState(from: delegate)
        guard delegateState?.isExited != true else {
            lock.unlock()
            return
        }
        lock.unlock()
        let deliveredResult = delegateState == nil ? takeResultForDelivery() : result
        __kk_coroutine_continuation_resume_with(delegate, deliveredResult, nil)
        withExtendedLifetime(delegateState) {}
    }

    /// The delegate's state machine can finish through another completion path
    /// while a channel or parent Job still retains this cancellable continuation.
    /// Retire the parent callback before the delegate handle is released so a
    /// late cancellation cannot resume a stale raw continuation pointer.
    func delegateDidExit() {
        lock.lock()
        guard !delegateExited else {
            lock.unlock()
            return
        }
        delegateExited = true
        let parent = self.parent
        let handlerID = parentHandlerID
        parentHandlerID = 0
        let shouldCancel = !delivered && (
            state == .active || state == .reserved
                || (state == .completed && runtimeResultIsSuccess(result))
        )
        let cause: Int
        if shouldCancel {
            cause = cancelCause != 0
                ? cancelCause
                : runtimeAllocateCancellationException(message: "Continuation delegate exited before delivery")
            state = .cancelled
            cancelCause = cause
            result = runtimeResultFailure(cause)
        } else {
            cause = 0
        }
        let handler = shouldCancel ? cancellationHandler : nil
        let callback = shouldCancel ? resumeCancellation : nil
        cancellationHandler = nil
        resumeCancellation = nil
        lock.unlock()

        if handlerID != 0 { parent?.removeCompletionHandler(id: handlerID) }
        if cause != 0 {
            handler?.invoke(cause)
            callback?.invoke(cause)
        }
    }

    /// Kernel resources must be returned if cancellation wins before delivery.
    func resume(value: Int, onCancellation: @escaping @Sendable () -> Void) {
        resume(runtimeResultSuccess(value), callback: RuntimeCancellationCallback(
            fnPtr: 0, closureRaw: 0, native: { _ in onCancellation() }
        ), outThrown: nil)
    }

    func resume(failure cause: Int) {
        resume(runtimeResultFailure(cause), callback: RuntimeCancellationCallback(fnPtr: 0, closureRaw: 0), outThrown: nil)
    }

    fileprivate func resume(_ proposed: Int, callback: RuntimeCancellationCallback, outThrown: UnsafeMutablePointer<Int>?) {
        lock.lock()
        if state == .cancelled && !resumedAfterCancellation {
            resumedAfterCancellation = true
            let cause = cancelCause
            lock.unlock()
            callback.invoke(cause)
            return
        }
        guard state == .active else {
            lock.unlock()
            outThrown?.pointee = runtimeAllocateIllegalStateException(message: "Already resumed")
            return
        }
        state = .completed
        result = proposed
        resumeCancellation = runtimeResultIsSuccess(proposed) ? callback : nil
        let shouldDispatch = suspended
        lock.unlock()
        if shouldDispatch { dispatchResult(proposed) }
    }

    @discardableResult
    func cancel(_ cause: Int) -> Bool {
        cancel(cause, fromParent: false)
    }

    private func cancelFromParent(_ cause: Int) {
        _ = cancel(cause, fromParent: true)
    }

    private func cancel(_ cause: Int, fromParent: Bool) -> Bool {
        let resolved = cause == 0 || cause == runtimeNullSentinelInt
            ? runtimeAllocateCancellationException(message: "Continuation was cancelled") : cause
        lock.lock()
        guard !delegateExited else {
            lock.unlock()
            return false
        }
        let wasActive = state == .active
        let promptCancellation = fromParent && state == .completed && !delivered && runtimeResultIsSuccess(result)
        guard wasActive || promptCancellation else {
            lock.unlock()
            return false
        }
        if wasActive { state = .cancelled }
        cancelCause = resolved
        result = runtimeResultFailure(resolved)
        let handler = cancellationHandler
        let callback = resumeCancellation
        resumeCancellation = nil
        let shouldDispatch = wasActive && suspended
        lock.unlock()
        handler?.invoke(resolved)
        callback?.invoke(resolved)
        if shouldDispatch { dispatchResult(runtimeResultFailure(resolved)) }
        return wasActive
    }

    fileprivate func invokeOnCancellation(_ handler: RuntimeCancellationCallback, outThrown: UnsafeMutablePointer<Int>?) {
        lock.lock()
        guard cancellationHandler == nil else {
            lock.unlock()
            outThrown?.pointee = runtimeAllocateIllegalStateException(message: "Multiple cancellation handlers")
            return
        }
        cancellationHandler = handler
        let cause = cancelCause
        lock.unlock()
        if cause != 0 { handler.invoke(cause) }
    }

    func tryResume(_ proposed: Int, idempotent: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }
        if state != .active {
            return idempotent != runtimeNullSentinelInt && idempotent == self.idempotent
                && token != 0 ? token : runtimeNullSentinelInt
        }
        state = .reserved
        result = proposed
        self.idempotent = idempotent
        token = runtimeRegisterObject(RuntimeResumeToken())
        return token
    }

    func completeResume(_ token: Int, outThrown: UnsafeMutablePointer<Int>?) {
        lock.lock()
        guard token == self.token && token != 0 && (state == .reserved || state == .completed) else {
            lock.unlock()
            outThrown?.pointee = runtimeAllocateIllegalStateException(message: "Invalid resume token")
            return
        }
        guard state == .reserved else { lock.unlock(); return }
        state = .completed
        let proposed = result
        let shouldDispatch = suspended
        lock.unlock()
        if shouldDispatch { dispatchResult(proposed) }
    }

    func takeResultForDelivery() -> Int {
        if let parent, parent.cancellationSnapshot() || parent.isFailedSnapshot() {
            cancelFromParent(runtimeJobCancellationException(parent))
        }
        lock.lock()
        delivered = true
        let result = self.result
        let parent = self.parent
        let handlerID = parentHandlerID
        parentHandlerID = 0
        lock.unlock()
        if handlerID != 0 { parent?.removeCompletionHandler(id: handlerID) }
        return result
    }

    func getResult(_ outThrown: UnsafeMutablePointer<Int>?) -> Int {
        lock.lock()
        if state == .active || state == .reserved {
            let delegateState = runtimeContinuationState(from: delegate)
            let installed = delegateState?.installCancellableDelivery(self) ?? true
            suspended = true
            lock.unlock()
            if !installed {
                delegateDidExit()
                return runtimeResultGetOrThrow(takeResultForDelivery(), outThrown)
            }
            return Int(bitPattern: kk_coroutine_suspended())
        }
        lock.unlock()
        return runtimeResultGetOrThrow(takeResultForDelivery(), outThrown)
    }
}

private func cancellableContinuation(_ handle: Int) -> RuntimeCancellableContinuation {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle),
          let continuation = tryCast(ptr, to: RuntimeCancellableContinuation.self) else {
        fatalError("Invalid cancellable continuation handle")
    }
    return continuation
}

@_cdecl("__kk_cancellable_continuation_new")
public func __kk_cancellable_continuation_new(_ delegate: Int) -> Int {
    let continuation = RuntimeCancellableContinuation(delegate: delegate)
    let handle = runtimeRegisterObject(continuation)
    continuation.initParent()
    return handle
}

@_cdecl("__kk_cancellable_continuation_state")
public func __kk_cancellable_continuation_state(_ handle: Int) -> Int {
    cancellableContinuation(handle).stateValue
}

@_cdecl("__kk_cancellable_continuation_resume")
public func __kk_cancellable_continuation_resume(
    _ handle: Int, _ result: Int, _ fnPtr: Int, _ outThrown: UnsafeMutablePointer<Int>?
) {
    outThrown?.pointee = 0
    cancellableContinuation(handle).resume(result, callback: RuntimeCancellationCallback(fnPtr: fnPtr, closureRaw: 0), outThrown: outThrown)
}

@_cdecl("__kk_cancellable_continuation_cancel")
public func __kk_cancellable_continuation_cancel(_ handle: Int, _ cause: Int) -> Int {
    cancellableContinuation(handle).cancel(cause) ? 1 : 0
}

@_cdecl("__kk_cancellable_continuation_invoke_on_cancellation")
public func __kk_cancellable_continuation_invoke_on_cancellation(
    _ handle: Int, _ fnPtr: Int, _ outThrown: UnsafeMutablePointer<Int>?
) {
    outThrown?.pointee = 0
    cancellableContinuation(handle).invokeOnCancellation(RuntimeCancellationCallback(fnPtr: fnPtr, closureRaw: 0), outThrown: outThrown)
}

@_cdecl("__kk_cancellable_continuation_try_resume")
public func __kk_cancellable_continuation_try_resume(_ handle: Int, _ result: Int, _ idempotent: Int) -> Int {
    cancellableContinuation(handle).tryResume(result, idempotent: idempotent)
}

@_cdecl("__kk_cancellable_continuation_complete_resume")
public func __kk_cancellable_continuation_complete_resume(_ handle: Int, _ token: Int, _ outThrown: UnsafeMutablePointer<Int>?) {
    outThrown?.pointee = 0
    cancellableContinuation(handle).completeResume(token, outThrown: outThrown)
}

@_cdecl("__kk_cancellable_continuation_get_result")
public func __kk_cancellable_continuation_get_result(_ handle: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    return cancellableContinuation(handle).getResult(outThrown)
}
