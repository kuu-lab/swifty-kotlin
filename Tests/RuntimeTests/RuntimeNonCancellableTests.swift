import Foundation
@testable import Runtime
import Testing

@_cdecl("noncancellable_return_block_job")
func noncancellable_return_block_job(_ continuation: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    return RuntimeContinuationState.current?.jobHandle?.identityHandle ?? 0
}

@_cdecl("noncancellable_throw_from_block")
func noncancellable_throw_from_block(_ continuation: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    let state = runtimeContinuationState(from: continuation)
    state?.launcherArgs[0] = Int64(state?.jobHandle?.identityHandle ?? 0)
    outThrown?.pointee = runtimeAllocateIllegalStateException(message: "cleanup")
    return 0
}

@Suite(.runtimeIsolation(.gcAndMetadata))
struct RuntimeNonCancellableTests {
    private func nominalToken(_ name: String) -> Int {
        let typeID = runtimeStableNominalTypeID(fqName: name)
        return Int(RuntimeTypeTokenEncoding.nominalBase | (typeID << RuntimeTypeTokenEncoding.payloadShift))
    }

    @Test func singletonSupportsNominalChecksAndCasts() {
        let singleton = kk_non_cancellable_instance()
        #expect(kk_non_cancellable_instance() == singleton)
        for name in [
            "kotlinx.coroutines.NonCancellable", "kotlinx.coroutines.Job",
            "kotlin.coroutines.AbstractCoroutineContextElement",
            "kotlin.coroutines.CoroutineContext.Element", "kotlin.coroutines.CoroutineContext",
        ] {
            let token = nominalToken(name)
            #expect(kk_op_is(singleton, token) == 1)
            #expect(kk_op_safe_cast(singleton, token) == singleton)
            var thrown = 123
            #expect(kk_op_cast(singleton, token, &thrown) == singleton)
            #expect(thrown == 0)
        }
        let unrelated = nominalToken("kotlinx.coroutines.Deferred")
        #expect(kk_op_is(singleton, unrelated) == 0)
        #expect(kk_op_safe_cast(singleton, unrelated) == runtimeNullSentinelInt)
        var thrown = 0
        _ = kk_op_cast(singleton, unrelated, &thrown)
        #expect(thrown != 0)
    }

    @Test func joinThrowsButAwaitCancellationStillSuspends() throws {
        let continuation = kk_coroutine_continuation_new(1087)
        var thrown = 0
        #expect(kk_job_join(kk_non_cancellable_instance(), continuation, &thrown) == 0)
        let pointer = try #require(UnsafeMutableRawPointer(bitPattern: thrown))
        let exception = try #require(tryCast(pointer, to: RuntimeThrowableBox.self))
        #expect(exception.message == "This job is always active")
        #expect(runtimeThrowableMatchesNominalTypeID(
            exception,
            targetTypeID: runtimeStableNominalTypeID(fqName: "kotlin.UnsupportedOperationException")
        ))
        #expect(kk_await_cancellation(continuation) == Int(bitPattern: kk_coroutine_suspended()))
        thrown = 0
        #expect(kk_job_await_completion(kk_non_cancellable_instance(), continuation, &thrown) == 0)
        #expect(thrown != 0)
    }

    @Test func nestedShieldSuppressesOnlyCancellationResumes() {
        let state = RuntimeContinuationState(functionID: 1087)
        let loop = RuntimeEventLoop()
        state.eventLoop = loop
        let resumed = RuntimeCompletionFlag()
        state.beginCancellationShield()
        state.beginCancellationShield()
        state.signalResume(isCancellation: true)
        state.installResumeContinuation { resumed.set() }
        let outerCancellationResumed = loop.run(until: { resumed.isSet }, deadline: Date().addingTimeInterval(0.01))
        #expect(!outerCancellationResumed)
        state.endCancellationShield()
        state.signalResume(isCancellation: true)
        let nestedCancellationResumed = loop.run(until: { resumed.isSet }, deadline: Date().addingTimeInterval(0.01))
        #expect(!nestedCancellationResumed)
        state.signalResume()
        let completionResumed = loop.run(until: { resumed.isSet }, deadline: Date().addingTimeInterval(1))
        #expect(completionResumed)
        state.endCancellationShield()

        let cancelled = RuntimeCompletionFlag()
        state.installResumeContinuation { cancelled.set() }
        state.signalResume(isCancellation: true)
        let unshieldedCancellationResumed = loop.run(until: { cancelled.isSet }, deadline: Date().addingTimeInterval(1))
        #expect(unshieldedCancellationResumed)
    }

    @Test func ordinaryCompletedJobJoinClearsThrowSlot() {
        let job = kk_job_new()
        _ = kk_job_complete(job, 42)
        var thrown = 123
        #expect(kk_job_join(job, 0, &thrown) == 42)
        #expect(thrown == 0)
    }

    @Test func forwardedCancellationRespectsChildShield() {
        let caller = RuntimeContinuationState(functionID: 1087)
        let child = RuntimeContinuationState(functionID: 1088)
        let loop = RuntimeEventLoop()
        child.eventLoop = loop
        let resumed = RuntimeCompletionFlag()
        caller.bindSuspendedCallChild(child)
        child.beginCancellationShield()
        child.installResumeContinuation { resumed.set() }
        caller.signalResume(isCancellation: true)
        let cancelled = loop.run(until: { resumed.isSet }, deadline: Date().addingTimeInterval(0.01))
        #expect(!cancelled)
        caller.signalResume()
        let completed = loop.run(until: { resumed.isSet }, deadline: Date().addingTimeInterval(1))
        #expect(completed)
        child.endCancellationShield()
        caller.unbindSuspendedCallChild(child)
    }

    @Test(arguments: [false, true])
    func withContextUsesDistinctBlockJobAndRestoresCancelledCaller(fullContext: Bool) throws {
        let continuation = kk_coroutine_continuation_new(1087)
        let state = try #require(runtimeContinuationState(from: continuation))
        let original = RuntimeJobHandle()
        state.jobHandle = original
        _ = original.cancel()
        let entry = unsafeBitCast(
            noncancellable_return_block_job as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int,
            to: Int.self
        )
        let context = kk_non_cancellable_instance()
        let result = fullContext
            ? kk_with_context_full(context, entry, continuation)
            : kk_with_context(context, entry, continuation)
        let blockJob = try #require(runtimeJobHandle(from: result))
        #expect(result != context)
        #expect(blockJob !== original)
        #expect(blockJob.completedSnapshot())
        #expect(!blockJob.cancellationSnapshot())
        #expect(state.jobHandle === original)
        var thrown = 0
        #expect(kk_coroutine_check_cancellation(continuation, &thrown) == 1)
    }

    @Test func throwingWithContextCompletesBlockJobAndRestoresCaller() throws {
        let continuation = kk_coroutine_continuation_new(1087)
        let state = try #require(runtimeContinuationState(from: continuation))
        let original = RuntimeJobHandle()
        state.jobHandle = original
        let entry = unsafeBitCast(
            noncancellable_throw_from_block as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int,
            to: Int.self
        )
        _ = kk_with_context_full(kk_non_cancellable_instance(), entry, continuation)
        let blockJob = try #require(runtimeJobHandle(from: Int(state.launcherArgs[0] ?? 0)))
        #expect(blockJob.isFailedSnapshot())
        #expect(blockJob.completedSnapshot())
        #expect(state.jobHandle === original)
    }
}
