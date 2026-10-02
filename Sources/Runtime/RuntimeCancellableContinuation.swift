import Foundation

private struct RuntimeCancellationCallback: Sendable {
    let fnPtr: Int
    let closureRaw: Int

    func invoke(_ cause: Int) {
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
        guard let ptr = UnsafeMutableRawPointer(bitPattern: jobRaw),
              let job = tryCast(ptr, to: RuntimeJobHandle.self) else { return }
        parent = job
        parentHandlerID = job.addCompletionHandler(onCancelling: true) { [weak self] cause in
            if cause != 0 { self?.cancelFromParent(cause) }
        }
        if job.cancellationSnapshot() {
            cancelFromParent(job.cancellationCauseSnapshot())
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
        let deliveredResult = runtimeContinuationState(from: delegate) == nil ? takeResultForDelivery() : result
        __kk_coroutine_continuation_resume_with(delegate, deliveredResult, nil)
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
        if let parent, parent.cancellationSnapshot() {
            cancelFromParent(parent.cancellationCauseSnapshot())
        }
        lock.lock()
        delivered = true
        let result = self.result
        lock.unlock()
        parent?.removeCompletionHandler(id: parentHandlerID)
        return result
    }

    func getResult(_ outThrown: UnsafeMutablePointer<Int>?) -> Int {
        lock.lock()
        if state == .active || state == .reserved {
            runtimeContinuationState(from: delegate)?.installCancellableDelivery(self)
            suspended = true
            lock.unlock()
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
