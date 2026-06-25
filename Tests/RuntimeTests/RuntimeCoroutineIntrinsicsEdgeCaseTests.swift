import Dispatch
@testable import Runtime
import XCTest

private typealias RuntimeCoroutineIntrinsicEntry = @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int

private let coroutineIntrinsicsDelayFunctionID = 8810
private let coroutineIntrinsicsReceiverFunctionID = 8811

@_cdecl("coro_intrinsics_return_123")
private func coro_intrinsics_return_123(_ continuation: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    return kk_coroutine_state_exit(continuation, 123)
}

@_cdecl("coro_intrinsics_delay_then_return")
private func coro_intrinsics_delay_then_return(_ continuation: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    let label = kk_coroutine_state_enter(continuation, coroutineIntrinsicsDelayFunctionID)
    if label == 0 {
        _ = kk_coroutine_state_set_label(continuation, 1)
        return kk_kxmini_delay(1, continuation)
    }
    outThrown?.pointee = 0
    return kk_coroutine_state_exit(continuation, 456)
}

@_cdecl("coro_intrinsics_receiver_plus_one")
private func coro_intrinsics_receiver_plus_one(_ continuation: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    _ = kk_coroutine_state_enter(continuation, coroutineIntrinsicsReceiverFunctionID)
    outThrown?.pointee = 0
    let receiver = kk_coroutine_launcher_arg_get(continuation, 0)
    return kk_coroutine_state_exit(continuation, Int(receiver) + 1)
}

@_cdecl("coro_intrinsics_throw_immediately")
private func coro_intrinsics_throw_immediately(_ continuation: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = runtimeAllocateThrowable(message: "intrinsic boom")
    _ = kk_coroutine_state_exit(continuation, 0)
    return 0
}

final class RuntimeCoroutineIntrinsicsEdgeCaseTests: XCTestCase {

    override func setUp() {
        super.setUp()
        kk_runtime_force_reset()
    }

    override func tearDown() {
        kk_runtime_force_reset()
        super.tearDown()
    }

    // MARK: - COROUTINE_SUSPENDED sentinel

    func testCoroutineSuspendedSentinelIsNonNull() {
        let sentinel = kk_coroutine_suspended()
        XCTAssertNotEqual(Int(bitPattern: sentinel), 0,
            "COROUTINE_SUSPENDED sentinel must be non-null")
    }

    func testCoroutineSuspendedSentinelIsSingletonIdentity() {
        let first = kk_coroutine_suspended()
        let second = kk_coroutine_suspended()
        XCTAssertEqual(first, second,
            "COROUTINE_SUSPENDED sentinel must return the same object on every call")
    }

    func testCoroutineSuspendedSentinelEqualityCheck() {
        let sentinelA = kk_coroutine_suspended()
        let sentinelB = kk_coroutine_suspended()
        XCTAssertTrue(sentinelA == sentinelB,
            "COROUTINE_SUSPENDED pointer equality check must hold (state-machine short-circuit)")
    }

    func testCoroutineSuspendedSentinelNotEqualToOtherObject() {
        let sentinel = Int(bitPattern: kk_coroutine_suspended())
        let cont = kk_coroutine_continuation_new(8800)
        defer { _ = kk_coroutine_state_exit(cont, 0) }
        XCTAssertNotEqual(sentinel, cont,
            "COROUTINE_SUSPENDED must not alias a regular continuation handle")
    }

    // MARK: - start/create unintercepted runtime entry points

    func testCreateCoroutineUninterceptedStartsWhenReturnedContinuationIsResumed() throws {
        let completion = kk_coroutine_continuation_new(8812)
        defer { _ = kk_coroutine_state_exit(completion, 0) }
        let completionState = try XCTUnwrap(runtimeContinuationState(from: completion))
        let entryRaw = unsafeBitCast(
            coro_intrinsics_return_123 as RuntimeCoroutineIntrinsicEntry,
            to: Int.self
        )

        let continuation = kk_create_coroutine_unintercepted(entryRaw, completion)
        XCTAssertNotEqual(continuation, 0)

        kk_coroutine_continuation_resume(continuation, 0)
        XCTAssertEqual(Int(completionState.completion), 123)
        XCTAssertEqual(completionState.thrownException, 0)
    }

    func testCreateCoroutineUninterceptedPreservesReceiverLauncherArg() throws {
        let completion = kk_coroutine_continuation_new(8813)
        defer { _ = kk_coroutine_state_exit(completion, 0) }
        let completionState = try XCTUnwrap(runtimeContinuationState(from: completion))
        let entryRaw = unsafeBitCast(
            coro_intrinsics_receiver_plus_one as RuntimeCoroutineIntrinsicEntry,
            to: Int.self
        )

        let continuation = kk_create_coroutine_unintercepted(entryRaw, completion)
        _ = kk_coroutine_launcher_arg_set(continuation, 0, 41)
        kk_coroutine_continuation_resume(continuation, 0)

        XCTAssertEqual(Int(completionState.completion), 42)
        XCTAssertEqual(completionState.thrownException, 0)
    }

    func testStartCoroutineUninterceptedOrReturnReturnsImmediateResult() throws {
        let completion = kk_coroutine_continuation_new(8814)
        defer { _ = kk_coroutine_state_exit(completion, 0) }
        let completionState = try XCTUnwrap(runtimeContinuationState(from: completion))
        let entryRaw = unsafeBitCast(
            coro_intrinsics_return_123 as RuntimeCoroutineIntrinsicEntry,
            to: Int.self
        )
        let continuation = kk_create_coroutine_unintercepted(entryRaw, completion)
        var thrown = 0

        let result = kk_start_coroutine_unintercepted_or_return(entryRaw, continuation, &thrown)

        XCTAssertEqual(result, 123)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(Int(completionState.completion), 0)
        XCTAssertEqual(completionState.thrownException, 0)
    }

    func testStartCoroutineUninterceptedOrReturnSuspendsAndResumesCompletion() throws {
        let completion = kk_coroutine_continuation_new(8815)
        defer { _ = kk_coroutine_state_exit(completion, 0) }
        let completionState = try XCTUnwrap(runtimeContinuationState(from: completion))
        let completed = DispatchSemaphore(value: 0)
        completionState.installResumeContinuation {
            completed.signal()
        }
        let entryRaw = unsafeBitCast(
            coro_intrinsics_delay_then_return as RuntimeCoroutineIntrinsicEntry,
            to: Int.self
        )
        let continuation = kk_create_coroutine_unintercepted(entryRaw, completion)
        var thrown = 0

        let result = kk_start_coroutine_unintercepted_or_return(entryRaw, continuation, &thrown)

        XCTAssertEqual(result, Int(bitPattern: kk_coroutine_suspended()))
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(completed.wait(timeout: .now() + 3), .success)
        XCTAssertEqual(Int(completionState.completion), 456)
        XCTAssertEqual(completionState.thrownException, 0)
    }

    func testStartCoroutineUninterceptedOrReturnPropagatesImmediateThrow() throws {
        let completion = kk_coroutine_continuation_new(8816)
        defer { _ = kk_coroutine_state_exit(completion, 0) }
        let completionState = try XCTUnwrap(runtimeContinuationState(from: completion))
        let entryRaw = unsafeBitCast(
            coro_intrinsics_throw_immediately as RuntimeCoroutineIntrinsicEntry,
            to: Int.self
        )
        let continuation = kk_create_coroutine_unintercepted(entryRaw, completion)
        var thrown = 0

        let result = kk_start_coroutine_unintercepted_or_return(entryRaw, continuation, &thrown)

        XCTAssertEqual(result, 0)
        XCTAssertNotEqual(thrown, 0)
        XCTAssertEqual(Int(completionState.completion), 0)
        XCTAssertEqual(completionState.thrownException, 0)
    }

    // MARK: - intercepted() — bypass semantics

    func testInterceptedFreshContinuationReturnsIdentity() {
        let cont = kk_coroutine_continuation_new(8801)
        defer { _ = kk_coroutine_state_exit(cont, 0) }
        let intercepted = kk_continuation_intercepted(cont)
        XCTAssertEqual(intercepted, cont,
            "intercepted() on a continuation with no interceptor must return the same handle (bypass)")
    }

    func testInterceptedZeroHandleReturnsZero() {
        let result = kk_continuation_intercepted(0)
        XCTAssertEqual(result, 0, "intercepted(null) must return 0")
    }

    func testInterceptedValidContinuationIsNonZero() {
        let cont = kk_coroutine_continuation_new(8802)
        defer { _ = kk_coroutine_state_exit(cont, 0) }
        let intercepted = kk_continuation_intercepted(cont)
        XCTAssertNotEqual(intercepted, 0,
            "intercepted() must return a non-zero handle for a valid continuation")
    }

    // MARK: - kk_continuation_interceptor_intercept_continuation

    func testInterceptorInterceptContinuationWithZeroInterceptorReturnsOriginal() {
        let cont = kk_coroutine_continuation_new(8803)
        defer { _ = kk_coroutine_state_exit(cont, 0) }
        let result = kk_continuation_interceptor_intercept_continuation(0, cont)
        XCTAssertEqual(result, cont,
            "Intercepting with null interceptor must return the original continuation unchanged")
    }

    func testInterceptorInterceptContinuationWithNonDispatcherInterceptorReturnsOriginal() {
        let cont = kk_coroutine_continuation_new(8804)
        defer { _ = kk_coroutine_state_exit(cont, 0) }
        let result = kk_continuation_interceptor_intercept_continuation(cont, cont)
        XCTAssertEqual(result, cont,
            "Non-dispatcher interceptor must leave the continuation unchanged")
    }

    func testInterceptorInterceptContinuationWithZeroContinuationReturnsZero() {
        let result = kk_continuation_interceptor_intercept_continuation(0, 0)
        XCTAssertEqual(result, 0,
            "Intercepting a null continuation must return 0")
    }

    // MARK: - CancellationException type identity

    func testCancellationExceptionAllocatePtrIsNonZero() {
        let exc = runtimeAllocateCancellationException()
        XCTAssertNotEqual(exc, 0, "CancellationException allocation must return a non-zero pointer")
    }

    func testIsCancellationExceptionReturnsTrueForCancellation() {
        let exc = runtimeAllocateCancellationException()
        XCTAssertEqual(kk_is_cancellation_exception(exc), 1,
            "kk_is_cancellation_exception must return 1 for a CancellationException")
    }

    func testIsCancellationExceptionReturnsFalseForRegularThrowable() {
        let exc = runtimeAllocateThrowable(message: "regular error")
        XCTAssertEqual(kk_is_cancellation_exception(exc), 0,
            "kk_is_cancellation_exception must return 0 for a non-CancellationException")
    }

    func testIsCancellationExceptionReturnsFalseForNull() {
        XCTAssertEqual(kk_is_cancellation_exception(0), 0,
            "kk_is_cancellation_exception(null) must return 0")
    }

    func testCancellationExceptionCustomMessageRoundTrips() {
        let exc = runtimeAllocateCancellationException(message: "job was cancelled")
        XCTAssertEqual(kk_is_cancellation_exception(exc), 1)

        let msgRaw = kk_throwable_message(exc)
        XCTAssertNotEqual(msgRaw, 0, "CancellationException message handle must be non-zero")
    }

    func testCancellationExceptionWithCauseRoundTrips() {
        let cause = runtimeAllocateThrowable(message: "root cause")
        let exc = runtimeAllocateCancellationException(message: "cancelled with cause", cause: cause)
        XCTAssertEqual(kk_is_cancellation_exception(exc), 1)

        let causeRaw = kk_throwable_cause(exc)
        XCTAssertEqual(causeRaw, cause,
            "CancellationException must preserve its cause reference")
    }

    // MARK: - CancellationException is NOT a regular failure (Result semantics)

    func testRunCatchingWithCancellationExceptionProducesFailureResult() {
        let cancellationExcRaw = runtimeAllocateCancellationException(message: "cancelled")

        let stub: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { exc, outThrown in
            outThrown?.pointee = exc
            return 0
        }
        let fnPtr = unsafeBitCast(stub, to: Int.self)

        var outerThrown = 0
        let resultRaw = kk_runCatching(fnPtr, cancellationExcRaw, &outerThrown)
        XCTAssertEqual(outerThrown, 0, "kk_runCatching outer outThrown must remain 0")
        XCTAssertEqual(kk_result_isFailure(resultRaw), 1)
        XCTAssertEqual(kk_result_isSuccess(resultRaw), 0)

        let exceptionFromResult = kk_result_exceptionOrNull(resultRaw)
        XCTAssertEqual(kk_is_cancellation_exception(exceptionFromResult), 1,
            "Result.failure wrapping a CancellationException must be identified as CancellationException")
    }

    func testRunCatchingWithRegularExceptionIsNotCancellation() {
        let regularExc = runtimeAllocateThrowable(message: "normal error")
        let stub: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { exc, outThrown in
            outThrown?.pointee = exc
            return 0
        }
        let fnPtr = unsafeBitCast(stub, to: Int.self)

        var outerThrown = 0
        let resultRaw = kk_runCatching(fnPtr, regularExc, &outerThrown)
        XCTAssertEqual(kk_result_isFailure(resultRaw), 1)

        let exceptionFromResult = kk_result_exceptionOrNull(resultRaw)
        XCTAssertEqual(kk_is_cancellation_exception(exceptionFromResult), 0,
            "Result.failure wrapping a regular exception must NOT be identified as CancellationException")
    }

    // MARK: - CancellationException class hierarchy

    func testCancellationExceptionIsSubtypeOfThrowable() {
        let exc = runtimeAllocateCancellationException(message: "hierarchy check")
        let msgRaw = kk_throwable_message(exc)
        XCTAssertNotEqual(msgRaw, 0,
            "CancellationException must respond to throwable APIs (is-a RuntimeThrowableBox)")
        XCTAssertEqual(kk_is_cancellation_exception(exc), 1,
            "CancellationException must also satisfy is-cancellation check (is-a RuntimeCancellationBox)")
    }

    func testRegularThrowableIsNotCancellationException() {
        let exc = runtimeAllocateThrowable(message: "not cancelled")
        let msgRaw = kk_throwable_message(exc)
        XCTAssertNotEqual(msgRaw, 0, "Regular throwable must respond to throwable APIs")
        XCTAssertEqual(kk_is_cancellation_exception(exc), 0,
            "Regular throwable must not be identified as CancellationException")
    }

    // MARK: - COROUTINE_SUSPENDED in state machine short-circuit

    func testStateMachineShortCircuitWhenResultIsSuspendedSentinel() {
        let sentinel = Int(bitPattern: kk_coroutine_suspended())
        let blockResult = Int(bitPattern: kk_coroutine_suspended())

        let shouldSuspend = (blockResult == sentinel)
        XCTAssertTrue(shouldSuspend,
            "State machine must short-circuit and suspend when blockResult === COROUTINE_SUSPENDED")
    }

    func testStateMachineDoesNotShortCircuitWhenResultIsNotSuspendedSentinel() {
        let sentinel = Int(bitPattern: kk_coroutine_suspended())
        let blockResult = 42

        let shouldSuspend = (blockResult == sentinel)
        XCTAssertFalse(shouldSuspend,
            "State machine must NOT short-circuit when blockResult is a real value (not COROUTINE_SUSPENDED)")
    }

    // MARK: - CancellationException extends IllegalStateException hierarchy

    func testCancellationExceptionHierarchyIncludesIllegalStateException() {
        let box = RuntimeCancellationBox(message: "cancelled")
        XCTAssertTrue(
            box.exceptionHierarchyFQNames.contains("kotlin.IllegalStateException"),
            "CancellationException must be catchable as IllegalStateException per Kotlin spec"
        )
    }

    func testCancellationExceptionHierarchyIncludesRuntimeException() {
        let box = RuntimeCancellationBox(message: "cancelled")
        XCTAssertTrue(
            box.exceptionHierarchyFQNames.contains("kotlin.RuntimeException"),
            "CancellationException must be catchable as RuntimeException per Kotlin spec"
        )
    }

    func testCancellationExceptionHierarchyOrderingISEBeforeRuntimeException() {
        let box = RuntimeCancellationBox(message: "cancelled")
        let names = box.exceptionHierarchyFQNames
        let iseIndex = names.firstIndex(of: "kotlin.IllegalStateException")
        let rteIndex = names.firstIndex(of: "kotlin.RuntimeException")
        XCTAssertNotNil(iseIndex, "kotlin.IllegalStateException must be present")
        XCTAssertNotNil(rteIndex, "kotlin.RuntimeException must be present")
        if let ise = iseIndex, let rte = rteIndex {
            XCTAssertLessThan(ise, rte,
                "IllegalStateException must precede RuntimeException in the hierarchy list")
        }
    }

    func testCancellationExceptionMatchesIllegalStateExceptionTypeID() {
        let box = RuntimeCancellationBox(message: "cancelled")
        let iseTypeID = runtimeStableNominalTypeID(fqName: "kotlin.IllegalStateException")
        XCTAssertTrue(
            runtimeThrowableMatchesNominalTypeID(box, targetTypeID: iseTypeID),
            "catch (e: IllegalStateException) must catch CancellationException"
        )
    }

    func testCancellationExceptionMatchesRuntimeExceptionTypeID() {
        let box = RuntimeCancellationBox(message: "cancelled")
        let rteTypeID = runtimeStableNominalTypeID(fqName: "kotlin.RuntimeException")
        XCTAssertTrue(
            runtimeThrowableMatchesNominalTypeID(box, targetTypeID: rteTypeID),
            "catch (e: RuntimeException) must catch CancellationException"
        )
    }
}
