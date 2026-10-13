import Dispatch
import Foundation
@testable import Runtime
import Testing

private final class CancellationProbe: @unchecked Sendable {
    var causes: [Int] = []
    var handle = 0
}

private func recordCancellation(_ closure: Int, _ cause: Int, _ thrown: UnsafeMutablePointer<Int>?) -> Int {
    let probe = Unmanaged<CancellationProbe>.fromOpaque(UnsafeRawPointer(bitPattern: closure)!).takeUnretainedValue()
    probe.causes.append(cause)
    if probe.handle != 0 {
        _ = __kk_cancellable_continuation_state(probe.handle)
        _ = __kk_cancellable_continuation_cancel(probe.handle, cause)
    }
    thrown?.pointee = 0
    return 0
}

@Suite(.runtimeIsolation(.gcOnly))
struct RuntimeCancellableContinuationTests {
    private func makeHandle(parent: RuntimeJobHandle? = nil) -> Int {
        let delegate = kk_coroutine_continuation_new(9003)
        runtimeContinuationState(from: delegate)?.jobHandle = parent
        return __kk_cancellable_continuation_new(delegate)
    }

    private func callback(_ probe: CancellationProbe) -> Int {
        let fn = unsafeBitCast(recordCancellation as @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int, to: Int.self)
        return kk_function_create_1(fn, runtimeRegisterObject(probe), nil)
    }

    @Test func synchronousNullAndDuplicateResume() {
        let handle = makeHandle()
        var thrown = 0
        #expect(__kk_cancellable_continuation_state(handle) == 0)
        __kk_cancellable_continuation_resume(handle, runtimeResultSuccess(runtimeNullSentinelInt), 0, &thrown)
        #expect(thrown == 0)
        #expect(__kk_cancellable_continuation_get_result(handle, &thrown) == runtimeNullSentinelInt)
        #expect(thrown == 0)
        #expect(__kk_cancellable_continuation_state(handle) == 1)
        __kk_cancellable_continuation_resume(handle, runtimeResultSuccess(2), 0, &thrown)
        #expect(thrown != 0)
    }

    @Test func cancellationHandlersCanReenterAndResumeDiscardsOnce() {
        let handle = makeHandle()
        let probe = CancellationProbe()
        probe.handle = handle
        let handler = callback(probe)
        var thrown = 0
        __kk_cancellable_continuation_invoke_on_cancellation(handle, handler, &thrown)
        let cause = runtimeAllocateCancellationException(message: "stop")
        #expect(__kk_cancellable_continuation_cancel(handle, cause) == 1)
        #expect(__kk_cancellable_continuation_cancel(handle, cause) == 0)
        #expect(probe.causes == [cause])
        __kk_cancellable_continuation_resume(handle, runtimeResultSuccess(42), handler, &thrown)
        #expect(thrown == 0)
        #expect(probe.causes == [cause, cause])
        __kk_cancellable_continuation_resume(handle, runtimeResultSuccess(43), handler, &thrown)
        #expect(thrown != 0)
        #expect(probe.causes.count == 2)
        _ = __kk_cancellable_continuation_get_result(handle, &thrown)
        #expect(thrown == cause)
        #expect(__kk_cancellable_continuation_state(handle) == 2)
    }

    @Test func lateHandlerAndDuplicateRegistration() {
        let handle = makeHandle()
        let cause = runtimeAllocateCancellationException(message: "late")
        _ = __kk_cancellable_continuation_cancel(handle, cause)
        let probe = CancellationProbe()
        var thrown = 0
        __kk_cancellable_continuation_invoke_on_cancellation(handle, callback(probe), &thrown)
        #expect(probe.causes == [cause])
        __kk_cancellable_continuation_invoke_on_cancellation(handle, callback(probe), &thrown)
        #expect(thrown != 0)
        #expect(probe.causes == [cause])
    }

    @Test func reservationTokensValidateOwnerAndPreserveFailures() {
        let handle = makeHandle()
        let key = runtimeRegisterObject(NSObject())
        let cause = runtimeAllocateThrowable(message: "failure")
        let result = runtimeResultFailure(cause)
        let token = __kk_cancellable_continuation_try_resume(handle, result, key)
        #expect(token != runtimeNullSentinelInt)
        #expect(__kk_cancellable_continuation_try_resume(handle, result, key) == token)
        #expect(__kk_cancellable_continuation_try_resume(handle, result, runtimeNullSentinelInt) == runtimeNullSentinelInt)
        #expect(__kk_cancellable_continuation_cancel(handle, cause) == 0)
        var thrown = 0
        __kk_cancellable_continuation_complete_resume(makeHandle(), token, &thrown)
        #expect(thrown != 0)
        __kk_cancellable_continuation_complete_resume(handle, token, &thrown)
        #expect(thrown == 0)
        _ = __kk_cancellable_continuation_get_result(handle, &thrown)
        #expect(thrown == cause)
    }

    @Test(arguments: [false, true])
    func parentCancellationDiscardsUndeliveredSuccess(taskHandle: Bool) {
        let task = RuntimeAsyncTask()
        let taskRaw = runtimeRegisterObject(task)
        defer { _ = runtimeReleaseObject(taskRaw) }
        let parent = taskHandle ? task.completionJob : RuntimeJobHandle()
        let handle = makeHandle(parent: parent)
        let handlerProbe = CancellationProbe()
        let discardProbe = CancellationProbe()
        var thrown = 0
        __kk_cancellable_continuation_invoke_on_cancellation(handle, callback(handlerProbe), &thrown)
        __kk_cancellable_continuation_resume(handle, runtimeResultSuccess(42), callback(discardProbe), &thrown)
        let cause = runtimeAllocateCancellationException(message: "parent")
        _ = parent.cancel(cause: cause)
        _ = __kk_cancellable_continuation_get_result(handle, &thrown)
        #expect(thrown == cause)
        #expect(handlerProbe.causes == [cause])
        #expect(discardProbe.causes == [cause])
    }

    @Test func concurrentResumeHasOneWinner() {
        let handle = makeHandle()
        DispatchQueue.concurrentPerform(iterations: 16) { value in
            __kk_cancellable_continuation_resume(handle, runtimeResultSuccess(value), 0, nil)
        }
        var thrown = 0
        let result = __kk_cancellable_continuation_get_result(handle, &thrown)
        #expect((0..<16).contains(result))
        #expect(thrown == 0)
        #expect(__kk_cancellable_continuation_state(handle) == 1)
    }
}
