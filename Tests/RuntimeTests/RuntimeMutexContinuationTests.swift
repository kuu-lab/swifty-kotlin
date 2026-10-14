import Foundation
@testable import Runtime
import Testing

@Suite(.runtimeIsolation(.gcOnly))
struct RuntimeMutexContinuationTests {
    @Test(arguments: [false, true])
    func alreadyCancelledWaiterReceivesCancellation(owner: Bool) throws {
        let mutex = RuntimeMutexHandle()
        #expect(mutex.tryLock())
        let job = RuntimeJobHandle()
        job.markStarted()
        #expect(job.cancel())
        let continuation = kk_coroutine_continuation_new(2138)
        let state = try #require(runtimeContinuationState(from: continuation))
        state.jobHandle = job
        let token = owner ? 42 : 0
        #expect(mutex.lockSync(continuation: continuation, owner: token, outThrown: nil)
            == Int(bitPattern: kk_coroutine_suspended()))
        state.consumeCancellableDelivery()
        #expect(kk_is_cancellation_exception(state.takeThrownException()) == 1)
        #expect(mutex.unlock() == 0)
        #expect(!mutex.isLocked)
    }

    @Test(arguments: [false, true], [false, true])
    func cancelledAcquisitionReturnsOwnership(owner: Bool, cancelAfterHandoff: Bool) throws {
        let mutex = RuntimeMutexHandle()
        #expect(mutex.tryLock())
        let job = RuntimeJobHandle()
        job.markStarted()
        let continuation = kk_coroutine_continuation_new(2139)
        let state = try #require(runtimeContinuationState(from: continuation))
        state.jobHandle = job
        job.continuationState = state
        let token = owner ? 42 : 0
        var thrown = 0
        #expect(mutex.lockSync(continuation: continuation, owner: token, outThrown: &thrown)
            == Int(bitPattern: kk_coroutine_suspended()))
        #expect(thrown == 0)
        if cancelAfterHandoff {
            #expect(mutex.unlock() == 0)
            #expect(mutex.isLocked)
        }
        #expect(job.cancel())
        state.consumeCancellableDelivery()
        #expect(kk_is_cancellation_exception(state.takeThrownException()) == 1)
        if !cancelAfterHandoff {
            #expect(mutex.unlock() == 0)
        }
        #expect(!mutex.isLocked)
        #expect(!mutex.holdsLock(owner: token))
        #expect(mutex.tryLock())
        #expect(mutex.unlock() == 0)
    }

    @Test(arguments: [false, true])
    func deliveredAcquisitionSurvivesLaterCancellation(owner: Bool) throws {
        let mutex = RuntimeMutexHandle()
        #expect(mutex.tryLock())
        let job = RuntimeJobHandle()
        job.markStarted()
        let continuation = kk_coroutine_continuation_new(2140)
        let state = try #require(runtimeContinuationState(from: continuation))
        state.jobHandle = job
        job.continuationState = state
        let token = owner ? 42 : 0
        #expect(mutex.lockSync(continuation: continuation, owner: token, outThrown: nil)
            == Int(bitPattern: kk_coroutine_suspended()))
        #expect(mutex.unlock() == 0)
        state.consumeCancellableDelivery()
        #expect(state.takeThrownException() == 0)
        #expect(job.cancel())
        #expect(mutex.isLocked)
        if owner { #expect(mutex.holdsLock(owner: token)) }
        #expect(mutex.unlock(expectedOwner: token) == 0)
    }
}
