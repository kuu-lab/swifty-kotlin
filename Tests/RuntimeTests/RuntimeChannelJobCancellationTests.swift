import Dispatch
import Foundation
@testable import Runtime
import Testing

private final class ChannelCancellationResult: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = -1
    func set(_ value: Int) { lock.lock(); stored = value; lock.unlock() }
    func get() -> Int { lock.lock(); defer { lock.unlock() }; return stored }
}

private func waitForCancellationWaiters(_ channel: RuntimeChannelHandle, sending: Bool, count: Int) -> Bool {
    let deadline = DispatchTime.now() + .seconds(2)
    repeat {
        let counts = channel.suspendedWaiterCountsSnapshot()
        if counts.senders == (sending ? count : 0), counts.receivers == (sending ? 0 : count) { return true }
        Thread.sleep(forTimeInterval: 0.001)
    } while DispatchTime.now() < deadline
    return false
}

@Suite(.serialized)
struct RuntimeChannelJobCancellationTests {
    @Test(arguments: [false, true], [false, true])
    func cancellationWakesOnlyTheSuspendedOperation(sending: Bool, ambientJob: Bool) {
        let channel = RuntimeChannelHandle(capacity: 0)
        let job = RuntimeJobHandle()
        job.markStarted()
        let state = RuntimeContinuationState(functionID: 999)
        state.jobHandle = job
        job.continuationState = state
        let pointer = Unmanaged.passRetained(state).toOpaque()
        let continuation = ambientJob ? 0 : Int(bitPattern: pointer)
        let result = ChannelCancellationResult()
        let done = DispatchGroup()
        done.enter()
        defer {
            _ = channel.cancel()
            #expect(done.wait(timeout: .now() + .seconds(2)) == .success)
            Unmanaged<RuntimeContinuationState>.fromOpaque(pointer).release()
        }
        DispatchQueue.global().async {
            if ambientJob { RuntimeJobHandle.current = job }
            defer {
                if ambientJob { RuntimeJobHandle.current = nil }
                done.leave()
            }
            var value = 0
            let status = sending ? channel.send(42, continuation: continuation)
                : channel.receive(continuation: continuation, outValue: &value)
            result.set(status.rawValue)
            _ = job.complete(with: 0)
        }
        #expect(waitForCancellationWaiters(channel, sending: sending, count: 1))
        _ = job.cancel()
        #expect(done.wait(timeout: .now() + .seconds(2)) == .success)
        #expect(result.get() == kChannelResultCancelled)
        #expect(waitForCancellationWaiters(channel, sending: sending, count: 0))
        #expect(channel.trySend(99) == .failed)
        var value = 0
        #expect(channel.tryReceive(outValue: &value) == .failed)
        #expect(job.completedSnapshot())
    }

    @Test(arguments: [false, true])
    func cancellingOneWaiterPreservesOtherJobsAndFIFO(sending: Bool) {
        let channel = RuntimeChannelHandle(capacity: 0)
        let job = RuntimeJobHandle()
        job.markStarted()
        let state = RuntimeContinuationState(functionID: 998)
        state.jobHandle = job
        let pointer = Unmanaged.passRetained(state).toOpaque()
        let continuation = Int(bitPattern: pointer)
        let cancelledResult = ChannelCancellationResult()
        let results = [ChannelCancellationResult(), ChannelCancellationResult()]
        let values = [ChannelCancellationResult(), ChannelCancellationResult()]
        let cancelledDone = DispatchGroup()
        let otherDone = DispatchGroup()
        cancelledDone.enter()
        defer {
            _ = channel.cancel()
            #expect(cancelledDone.wait(timeout: .now() + .seconds(2)) == .success)
            #expect(otherDone.wait(timeout: .now() + .seconds(2)) == .success)
            Unmanaged<RuntimeContinuationState>.fromOpaque(pointer).release()
        }
        DispatchQueue.global().async {
            var value = 0
            let status = sending ? channel.send(11, continuation: continuation)
                : channel.receive(continuation: continuation, outValue: &value)
            cancelledResult.set(status.rawValue)
            _ = job.complete(with: 0)
            cancelledDone.leave()
        }
        #expect(waitForCancellationWaiters(channel, sending: sending, count: 1))
        for index in 0..<2 {
            otherDone.enter()
            DispatchQueue.global().async {
                var value = 0
                let status = sending ? channel.send(42 + index) : channel.receive(outValue: &value)
                values[index].set(value)
                results[index].set(status.rawValue)
                otherDone.leave()
            }
            #expect(waitForCancellationWaiters(channel, sending: sending, count: index + 2))
        }
        _ = job.cancel()
        #expect(cancelledDone.wait(timeout: .now() + .seconds(2)) == .success)
        #expect(cancelledResult.get() == kChannelResultCancelled)
        #expect(waitForCancellationWaiters(channel, sending: sending, count: 2))
        for index in 0..<2 {
            if sending {
                var value = 0
                #expect(channel.tryReceive(outValue: &value) == .success)
                #expect(value == 42 + index)
            } else {
                #expect(channel.trySend(42 + index) == .success)
            }
        }
        #expect(otherDone.wait(timeout: .now() + .seconds(2)) == .success)
        for index in 0..<2 {
            #expect(results[index].get() == kChannelResultSuccess)
            if !sending { #expect(values[index].get() == 42 + index) }
        }
        #expect(waitForCancellationWaiters(channel, sending: sending, count: 0))
    }
}

private final class ProducerCompletionCloseGate: @unchecked Sendable {
    let entered = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)
}
private let producerCompletionCloseGate = ProducerCompletionCloseGate()

@_cdecl("runtime_test_producer_completion_close_gate")
private func runtime_test_producer_completion_close_gate(_ closure: Int, _ cause: Int, _ thrown: UnsafeMutablePointer<Int>?) -> Int {
    thrown?.pointee = 0
    producerCompletionCloseGate.entered.signal()
    _ = producerCompletionCloseGate.release.wait(timeout: .now() + .seconds(5))
    return 0
}

@Suite(.serialized)
struct RuntimeProducerCompletionOrderingTests {
    @Test(arguments: [0, 1, 2])
    func closeCallbacksFinishBeforeJoinOrCompletionHandlers(terminal: Int) throws {
        let channel = kk_channel_create(64)
        let object = try #require(runtimeChannelHandleObject(from: channel))
        let job = RuntimeJobHandle()
        job.producerChannel = channel
        if terminal != 2 { job.markStarted() }
        let callback: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = runtime_test_producer_completion_close_gate
        #expect(object.addCloseHandler(fnPtr: unsafeBitCast(callback, to: Int.self), closureRaw: 0))
        let completeDone = DispatchGroup()
        let blockingJoinDone = DispatchGroup()
        let blockingJoinStarted = DispatchSemaphore(value: 0)
        let blockingJoined = ChannelCancellationResult()
        let failure = terminal == 0 ? 0 : runtimeAllocateIllegalStateException(message: "producer")
        completeDone.enter()
        var released = false
        defer {
            if !released { producerCompletionCloseGate.release.signal() }
            #expect(completeDone.wait(timeout: .now() + .seconds(2)) == .success)
            #expect(blockingJoinDone.wait(timeout: .now() + .seconds(2)) == .success)
        }
        DispatchQueue.global().async {
            switch terminal {
            case 0: _ = job.complete(with: 0)
            case 1: _ = job.completeExceptionally(with: failure)
            default: _ = job.cancel(message: "producer", cause: failure)
            }
            completeDone.leave()
        }
        #expect(producerCompletionCloseGate.entered.wait(timeout: .now() + .seconds(2)) == .success)
        let joined = ChannelCancellationResult()
        let handler = ChannelCancellationResult()
        job.addJoinResumer { joined.set($0) }
        _ = job.addCompletionHandler(onCancelling: false) { handler.set($0) }
        blockingJoinDone.enter()
        DispatchQueue.global().async {
            blockingJoinStarted.signal()
            blockingJoined.set(job.join())
            blockingJoinDone.leave()
        }
        #expect(blockingJoinStarted.wait(timeout: .now() + .seconds(2)) == .success)
        #expect(blockingJoinDone.wait(timeout: .now() + .milliseconds(50)) == .timedOut)
        #expect(!job.completedSnapshot())
        #expect(!job.completionSnapshot().completed)
        #expect(joined.get() == -1)
        #expect(handler.get() == -1)
        producerCompletionCloseGate.release.signal()
        released = true
        #expect(completeDone.wait(timeout: .now() + .seconds(2)) == .success)
        #expect(blockingJoinDone.wait(timeout: .now() + .seconds(2)) == .success)
        #expect(blockingJoined.get() == failure)
        #expect(joined.get() == failure)
        #expect(handler.get() == (terminal == 0 ? runtimeNullSentinelInt : failure))
        #expect(object.closeCauseSnapshot() == failure)
        #expect(job.completedSnapshot())
    }
}
