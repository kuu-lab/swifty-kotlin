import Dispatch
@testable import Runtime
import XCTest

// ThreadSafe container for test results in concurrent environments
class ThreadSafeInt: @unchecked Sendable {
    private var value: Int = 0
    private let lock = NSLock()

    func set(_ newValue: Int) {
        lock.lock()
        value = newValue
        lock.unlock()
    }

    func get() -> Int {
        lock.lock()
        let result = value
        lock.unlock()
        return result
    }
}

/// Receive helper: returns `(status, value)` using the out-of-band `outValue` slot.
private func channelReceivePair(_ handle: Int, _ continuation: Int = 0) -> (status: Int, value: Int) {
    var value = 0
    let status = kk_channel_receive(handle, continuation, &value)
    return (status, value)
}

private func channelReceiveValue(_ handle: Int, _ continuation: Int = 0) -> Int {
    channelReceivePair(handle, continuation).value
}


// MARK: - BUG-041 × channel blocking interaction

/// Shared rendezvous-channel handle for `runtime_test_channel_pending_launch_send`.
private final class ChannelPendingLaunchTestState: @unchecked Sendable {
    private let lock = NSLock()
    private var channelHandle = 0

    func setChannel(_ handle: Int) {
        lock.lock()
        channelHandle = handle
        lock.unlock()
    }

    func channel() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return channelHandle
    }
}

private let channelPendingLaunchTestState = ChannelPendingLaunchTestState()
private let channelPendingLaunchFunctionID = 9201
private typealias ChannelPendingLaunchEntry = @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int

/// Launched body: send `42` into the shared rendezvous channel, then exit.
@_cdecl("runtime_test_channel_pending_launch_send")
func runtime_test_channel_pending_launch_send(
    _ continuation: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let status = kk_channel_send(channelPendingLaunchTestState.channel(), 42, continuation)
    return kk_coroutine_state_exit(continuation, status)
}

final class RuntimeChannelTests: IsolatedRuntimeXCTestCase {
    // swiftlint:disable:next static_over_final_class
    override class var requiredLockSet: RuntimeLockSet { .gcOnly }

    // MARK: - Rendezvous Channel (capacity == 0)

    func testRendezvousSendReceivePairing() {
        let channelHandle = kk_channel_create(0)
        XCTAssertNotEqual(channelHandle, 0)

        let expectation = XCTestExpectation(description: "receive completes")
        let sendDone = XCTestExpectation(description: "send completes")
        let receivedValue = ThreadSafeInt()
        let sendResult = ThreadSafeInt()

        // Receive on a background thread (will suspend until a sender pairs).
        DispatchQueue.global().async {
            receivedValue.set(channelReceiveValue(channelHandle, 0))
            expectation.fulfill()
        }

        // Give the receiver time to suspend.
        Thread.sleep(forTimeInterval: 0.05)

        // Send on the main thread -- should wake the receiver.
        DispatchQueue.global().async {
            sendResult.set(kk_channel_send(channelHandle, 42, 0))
            sendDone.fulfill()
        }

        wait(for: [expectation, sendDone], timeout: 2.0)
        XCTAssertEqual(sendResult.get(), kChannelResultSuccess, "send should return success status")
        XCTAssertEqual(receivedValue.get(), 42, "receiver should get the sent value")

        _ = kk_channel_close(channelHandle)
    }

    func testRendezvousSenderSuspendsUntilReceiverArrives() {
        let channelHandle = kk_channel_create(0)

        let sendDone = XCTestExpectation(description: "send completes")
        let receiveDone = XCTestExpectation(description: "receive completes")
        let sendResult = ThreadSafeInt()
        let receivedValue = ThreadSafeInt()

        // Send on background thread -- no receiver yet, so it should suspend.
        DispatchQueue.global().async {
            sendResult.set(kk_channel_send(channelHandle, 99, 0))
            sendDone.fulfill()
        }

        // Give the sender time to suspend.
        Thread.sleep(forTimeInterval: 0.05)

        // Receive on the main thread -- should unblock the sender.
        DispatchQueue.global().async {
            receivedValue.set(channelReceiveValue(channelHandle, 0))
            receiveDone.fulfill()
        }

        wait(for: [sendDone, receiveDone], timeout: 2.0)
        XCTAssertEqual(receivedValue.get(), 99)
        XCTAssertEqual(sendResult.get(), kChannelResultSuccess)

        _ = kk_channel_close(channelHandle)
    }

    // MARK: - Buffered Channel (capacity > 0)

    func testBufferedSendDoesNotBlockWhenBufferHasSpace() {
        let channelHandle = kk_channel_create(2)

        // Two sends should return immediately without any receiver.
        XCTAssertEqual(kk_channel_send(channelHandle, 10, 0), kChannelResultSuccess)
        XCTAssertEqual(kk_channel_send(channelHandle, 20, 0), kChannelResultSuccess)

        // Receive both in order.
        XCTAssertEqual(channelReceiveValue(channelHandle, 0), 10)
        XCTAssertEqual(channelReceiveValue(channelHandle, 0), 20)

        _ = kk_channel_close(channelHandle)
    }

    func testBufferedSendSuspendsWhenFull() {
        let channelHandle = kk_channel_create(1)

        // First send fills the buffer.
        XCTAssertEqual(kk_channel_send(channelHandle, 1, 0), kChannelResultSuccess)

        let sendDone = XCTestExpectation(description: "second send completes")
        let secondSendResult = ThreadSafeInt()

        // Second send should suspend (backpressure).
        DispatchQueue.global().async {
            secondSendResult.set(kk_channel_send(channelHandle, 2, 0))
            sendDone.fulfill()
        }

        // Give the sender time to suspend.
        Thread.sleep(forTimeInterval: 0.05)

        // Receive the first item -- should free buffer space and wake the sender.
        XCTAssertEqual(channelReceiveValue(channelHandle, 0), 1)

        wait(for: [sendDone], timeout: 2.0)
        XCTAssertEqual(secondSendResult.get(), kChannelResultSuccess, "suspended sender should complete after space opens")

        // The second value should now be in the buffer.
        XCTAssertEqual(channelReceiveValue(channelHandle, 0), 2)

        _ = kk_channel_close(channelHandle)
    }

    func testBufferedChannelPreservesFIFOOrder() {
        let channelHandle = kk_channel_create(4)

        for i in 1 ... 4 {
            XCTAssertEqual(kk_channel_send(channelHandle, i, 0), kChannelResultSuccess)
        }

        for i in 1 ... 4 {
            XCTAssertEqual(channelReceiveValue(channelHandle, 0), i, "FIFO order violated at index \(i)")
        }

        _ = kk_channel_close(channelHandle)
    }

    // MARK: - Close Semantics

    func testCloseWakesSuspendedReceiverWithSentinel() {
        let channelHandle = kk_channel_create(0)

        let receiveDone = XCTestExpectation(description: "receive wakes on close")
        let receivedValue = ThreadSafeInt()

        DispatchQueue.global().async {
            receivedValue.set(channelReceivePair(channelHandle, 0).status)
            receiveDone.fulfill()
        }

        // Give the receiver time to suspend.
        Thread.sleep(forTimeInterval: 0.05)

        _ = kk_channel_close(channelHandle)

        wait(for: [receiveDone], timeout: 2.0)
        XCTAssertEqual(
            kk_channel_is_closed_token(receivedValue.get()), 1,
            "Receiver should get closed status when channel closes with empty buffer"
        )
    }

    func testCloseWakesSuspendedSenderWithSentinel() {
        let channelHandle = kk_channel_create(0)

        let sendDone = XCTestExpectation(description: "send wakes on close")
        let sendResult = ThreadSafeInt()

        DispatchQueue.global().async {
            sendResult.set(kk_channel_send(channelHandle, 77, 0))
            sendDone.fulfill()
        }

        // Give the sender time to suspend.
        Thread.sleep(forTimeInterval: 0.05)

        _ = kk_channel_close(channelHandle)

        wait(for: [sendDone], timeout: 2.0)
        XCTAssertEqual(
            kk_channel_is_closed_token(sendResult.get()), 1,
            "Sender should get the closed sentinel when channel closes"
        )
    }

    func testSendOnClosedChannelReturnsSentinel() {
        let channelHandle = kk_channel_create(1)
        _ = kk_channel_close(channelHandle)

        let result = kk_channel_send(channelHandle, 42, 0)
        XCTAssertEqual(kk_channel_is_closed_token(result), 1)
    }

    func testReceiveOnClosedEmptyChannelReturnsSentinel() {
        let channelHandle = kk_channel_create(1)
        _ = kk_channel_close(channelHandle)

        let result = channelReceivePair(channelHandle, 0).status
        XCTAssertEqual(kk_channel_is_closed_token(result), 1)
    }

    func testReceiveAfterCloseDrainsBufferFirst() {
        let channelHandle = kk_channel_create(3)

        XCTAssertEqual(kk_channel_send(channelHandle, 10, 0), kChannelResultSuccess)
        XCTAssertEqual(kk_channel_send(channelHandle, 20, 0), kChannelResultSuccess)

        _ = kk_channel_close(channelHandle)

        // Buffered values should still be receivable after close.
        XCTAssertEqual(channelReceiveValue(channelHandle, 0), 10)
        XCTAssertEqual(channelReceiveValue(channelHandle, 0), 20)

        // Now the buffer is drained -- should get closed status.
        let result = channelReceivePair(channelHandle, 0).status
        XCTAssertEqual(kk_channel_is_closed_token(result), 1)
    }

    // MARK: - Closed Token Helper

    func testIsClosedTokenDistinguishesStatusCodes() {
        XCTAssertEqual(kk_channel_is_closed_token(kChannelResultSuccess), 0, "success is not a failure status")
        XCTAssertEqual(kk_channel_is_closed_token(kChannelResultClosed), 1, "closed is a failure status")
        XCTAssertEqual(kk_channel_is_closed_token(kChannelResultCancelled), 1, "cancelled is a failure status")
    }

    func testSendAndReceiveLongMinValue() {
        let ch = kk_channel_create(1)
        XCTAssertEqual(kk_channel_send(ch, Int.min, 0), kChannelResultSuccess)
        XCTAssertEqual(channelReceiveValue(ch, 0), Int.min, "Long.MIN_VALUE must round-trip through the channel")
        _ = kk_channel_close(ch)
    }

    /// End-to-end test: `kk_channel_is_closed_token` returns 1 only after close
    /// *and* buffer drain through the full runtime -> ABI boundary path.
    func testIsClosedTokenEndToEnd_closeThenDrain() {
        let ch = kk_channel_create(2)

        // Send two values, then close.
        _ = kk_channel_send(ch, 100, 0)
        _ = kk_channel_send(ch, 200, 0)
        _ = kk_channel_close(ch)

        // Drain buffered values -- these should succeed with real payloads.
        let pair1 = channelReceivePair(ch, 0)
        XCTAssertEqual(kk_channel_is_closed_token(pair1.status), 0,
                       "Buffered value after close must not be identified as failure")
        XCTAssertEqual(pair1.value, 100)

        let pair2 = channelReceivePair(ch, 0)
        XCTAssertEqual(kk_channel_is_closed_token(pair2.status), 0,
                       "Buffered value after close must not be identified as failure")
        XCTAssertEqual(pair2.value, 200)

        // Buffer is now drained -- receive should return closed status.
        let pair3 = channelReceivePair(ch, 0)
        XCTAssertEqual(kk_channel_is_closed_token(pair3.status), 1,
                       "Receive after close+drain must return closed status")

        // send on a closed channel should also return closed status.
        let sendStatus = kk_channel_send(ch, 999, 0)
        XCTAssertEqual(kk_channel_is_closed_token(sendStatus), 1,
                       "Send on closed channel must return closed status")
    }

    // MARK: - Race Condition: Sender Woken by Receiver, Then Close

    /// Verify that a suspended sender reports success when a receiver accepts
    /// its value, even if close() races concurrently.  Before the delivered-flag
    /// fix this would incorrectly return kChannelClosedSentinel.
    func testSenderReportsSuccessWhenReceiverAcceptsThenCloseRaces() {
        for _ in 0 ..< 20 {
            let ch = kk_channel_create(0) // rendezvous

            let sendDone = XCTestExpectation(description: "send completes")
            let receiveDone = XCTestExpectation(description: "receive completes")
            let sendResult = ThreadSafeInt()
            let receivedValue = ThreadSafeInt()

            // Sender suspends on rendezvous channel.
            DispatchQueue.global().async {
                sendResult.set(kk_channel_send(ch, 77, 0))
                sendDone.fulfill()
            }
            Thread.sleep(forTimeInterval: 0.01)

            // Receiver accepts the value -- sender should see success.
            DispatchQueue.global().async {
                receivedValue.set(channelReceiveValue(ch, 0))
                receiveDone.fulfill()
            }

            wait(for: [receiveDone], timeout: 2.0)
            XCTAssertEqual(receivedValue.get(), 77)

            // Close immediately after receive to create the race window.
            _ = kk_channel_close(ch)

            wait(for: [sendDone], timeout: 2.0)
            XCTAssertEqual(sendResult.get(), kChannelResultSuccess,
                           "Sender must report success when receiver accepted, even if close() races")
            XCTAssertEqual(kk_channel_is_closed_token(sendResult.get()), 0,
                           "Send result must NOT be a failure status when receiver accepted the value")
        }
    }

    // MARK: - Backpressure with Multiple Senders

    func testMultipleSendersBlockAndResumeInOrder() {
        let channelHandle = kk_channel_create(1)

        // Fill the single-slot buffer.
        XCTAssertEqual(kk_channel_send(channelHandle, 1, 0), kChannelResultSuccess)

        let send2Done = XCTestExpectation(description: "sender 2 completes")
        let send3Done = XCTestExpectation(description: "sender 3 completes")

        // Two more senders should both suspend.
        DispatchQueue.global().async {
            _ = kk_channel_send(channelHandle, 2, 0)
            send2Done.fulfill()
        }
        Thread.sleep(forTimeInterval: 0.02)
        DispatchQueue.global().async {
            _ = kk_channel_send(channelHandle, 3, 0)
            send3Done.fulfill()
        }
        Thread.sleep(forTimeInterval: 0.02)

        // Receive all three values in FIFO order.
        XCTAssertEqual(channelReceiveValue(channelHandle, 0), 1)
        XCTAssertEqual(channelReceiveValue(channelHandle, 0), 2)
        XCTAssertEqual(channelReceiveValue(channelHandle, 0), 3)

        wait(for: [send2Done, send3Done], timeout: 2.0)

        _ = kk_channel_close(channelHandle)
    }

    // MARK: - Multiple Receivers

    func testMultipleReceiversBlockAndEachGetsOneValue() {
        let channelHandle = kk_channel_create(0)

        let recv1Done = XCTestExpectation(description: "receiver 1 completes")
        let recv2Done = XCTestExpectation(description: "receiver 2 completes")
        let received1 = ThreadSafeInt()
        let received2 = ThreadSafeInt()

        DispatchQueue.global().async {
            received1.set(channelReceiveValue(channelHandle, 0))
            recv1Done.fulfill()
        }
        Thread.sleep(forTimeInterval: 0.02)
        DispatchQueue.global().async {
            received2.set(channelReceiveValue(channelHandle, 0))
            recv2Done.fulfill()
        }
        Thread.sleep(forTimeInterval: 0.02)

        // Send two values -- each receiver gets one.
        _ = kk_channel_send(channelHandle, 10, 0)
        _ = kk_channel_send(channelHandle, 20, 0)

        wait(for: [recv1Done, recv2Done], timeout: 2.0)

        let values = Set([received1.get(), received2.get()])
        XCTAssertEqual(values, Set([10, 20]), "Each receiver should get exactly one distinct value")

        _ = kk_channel_close(channelHandle)
    }

    // MARK: - close() Returns Boolean (Kotlin Semantics)

    func testCloseReturnsTrueOnFirstCloseFalseOnSubsequent() {
        let ch = kk_channel_create(1)

        // First close should return 1 (true).
        let firstClose = kk_channel_close(ch)
        XCTAssertEqual(firstClose, 1, "First close() should return 1 (true)")

        // Second close should return 0 (false) -- already closed.
        let secondClose = kk_channel_close(ch)
        XCTAssertEqual(secondClose, 0, "Second close() should return 0 (false)")

        // Third close should also return 0 (false).
        let thirdClose = kk_channel_close(ch)
        XCTAssertEqual(thirdClose, 0, "Subsequent close() should return 0 (false)")
    }

    // MARK: - Cancellation-Aware Send/Receive

    func testSendWithCancelledContinuationReturnsSentinel() {
        let ch = kk_channel_create(0) // rendezvous -- send would block

        // Create a job handle and cancel it, then create a continuation linked to it.
        let job = RuntimeJobHandle()
        let contState = RuntimeContinuationState(functionID: 999)
        contState.jobHandle = job
        job.continuationState = contState

        // Cancel the job.
        _ = job.cancel()

        // Get the continuation as an opaque Int.
        let contPtr = Unmanaged.passRetained(contState).toOpaque()
        let contInt = Int(bitPattern: contPtr)

        // Send with the cancelled continuation should return the sentinel immediately
        // without blocking (even though no receiver is waiting).
        let result = kk_channel_send(ch, 42, contInt)
        XCTAssertEqual(kk_channel_is_closed_token(result), 1,
                       "send() with cancelled continuation should return the closed sentinel")

        // Clean up.
        Unmanaged<RuntimeContinuationState>.fromOpaque(contPtr).release()
        _ = kk_channel_close(ch)
    }

    func testReceiveWithCancelledContinuationReturnsSentinel() {
        let ch = kk_channel_create(0) // rendezvous -- receive would block

        // Create a job handle and cancel it, then create a continuation linked to it.
        let job = RuntimeJobHandle()
        let contState = RuntimeContinuationState(functionID: 999)
        contState.jobHandle = job
        job.continuationState = contState

        // Cancel the job.
        _ = job.cancel()

        // Get the continuation as an opaque Int.
        let contPtr = Unmanaged.passRetained(contState).toOpaque()
        let contInt = Int(bitPattern: contPtr)

        // Receive with the cancelled continuation should return the sentinel immediately
        // without blocking (even though no sender is waiting).
        let result = channelReceivePair(ch, contInt).status
        XCTAssertEqual(kk_channel_is_closed_token(result), 1,
                       "receive() with cancelled continuation should return failure status")

        // Clean up.
        Unmanaged<RuntimeContinuationState>.fromOpaque(contPtr).release()
        _ = kk_channel_close(ch)
    }

    func testSendWithZeroContinuationStillWorks() {
        // Verify backward compatibility: continuation == 0 means no cancellation check.
        let ch = kk_channel_create(1) // buffered -- send won't block

        let result = kk_channel_send(ch, 42, 0)
        XCTAssertEqual(result, kChannelResultSuccess, "send() with zero continuation should succeed normally")

        let received = channelReceiveValue(ch, 0)
        XCTAssertEqual(received, 42)

        _ = kk_channel_close(ch)
    }

    // MARK: - CORO-001: Post-Wakeup Cancellation Semantics

    /// Once a rendezvous send is matched with a receiver, the send result should
    /// report success even if cancellation races with the wakeup.
    func testSendWithCancellationDuringSuspensionSucceedsAfterDelivery() {
        let ch = kk_channel_create(0) // rendezvous - will suspend

        let sendDone = XCTestExpectation(description: "send completes")
        let receiveDone = XCTestExpectation(description: "receive completes")
        let sendResult = ThreadSafeInt()
        let receivedValue = ThreadSafeInt()

        // Create a job handle that we'll cancel while send is suspended
        let job = RuntimeJobHandle()
        let contState = RuntimeContinuationState(functionID: 999)
        contState.jobHandle = job
        job.continuationState = contState

        let contPtr = Unmanaged.passRetained(contState).toOpaque()
        let contInt = Int(bitPattern: contPtr)

        // Send on background thread - will suspend waiting for receiver
        DispatchQueue.global().async {
            sendResult.set(kk_channel_send(ch, 42, contInt))
            sendDone.fulfill()
        }

        // Give the sender time to suspend
        Thread.sleep(forTimeInterval: 0.05)

        // Cancel the job while sender is suspended
        _ = job.cancel()

        // Now add a receiver - the rendezvous completes before cancellation can
        // affect the next suspension point, so the send still succeeds.
        DispatchQueue.global().async {
            receivedValue.set(channelReceiveValue(ch, 0))
            receiveDone.fulfill()
        }

        wait(for: [sendDone, receiveDone], timeout: 2.0)
        XCTAssertEqual(sendResult.get(), kChannelResultSuccess, "Send should succeed once the value is delivered")
        XCTAssertEqual(receivedValue.get(), 42, "Receiver should observe the delivered value")

        // Clean up
        Unmanaged<RuntimeContinuationState>.fromOpaque(contPtr).release()
        _ = kk_channel_close(ch)
    }

    /// Once a rendezvous receive is matched with a sender, the receive result should
    /// return the delivered value even if cancellation races with the wakeup.
    func testReceiveWithCancellationDuringSuspensionSucceedsAfterDelivery() {
        let ch = kk_channel_create(0) // rendezvous - will suspend

        let receiveDone = XCTestExpectation(description: "receive completes")
        let sendDone = XCTestExpectation(description: "send completes")

        let receiveResult = ThreadSafeInt()
        let sendResult = ThreadSafeInt()

        // Create a job handle that we'll cancel while receive is suspended
        let job = RuntimeJobHandle()
        let contState = RuntimeContinuationState(functionID: 999)
        contState.jobHandle = job
        job.continuationState = contState

        let contPtr = Unmanaged.passRetained(contState).toOpaque()
        let contInt = Int(bitPattern: contPtr)

        // Receive on background thread - will suspend waiting for sender
        DispatchQueue.global().async {
            receiveResult.set(channelReceiveValue(ch, contInt))
            receiveDone.fulfill()
        }

        // Give the receiver time to suspend
        Thread.sleep(forTimeInterval: 0.05)

        // Cancel the job while receiver is suspended
        _ = job.cancel()

        // Now add a sender - the rendezvous completes before cancellation can
        // retroactively discard the received value.
        DispatchQueue.global().async {
            sendResult.set(kk_channel_send(ch, 99, 0))
            sendDone.fulfill()
        }

        wait(for: [receiveDone, sendDone], timeout: 2.0)
        XCTAssertEqual(receiveResult.get(), 99, "Receive should succeed once a sender delivered a value")
        XCTAssertEqual(sendResult.get(), kChannelResultSuccess, "Sender should observe successful delivery")

        // Clean up
        Unmanaged<RuntimeContinuationState>.fromOpaque(contPtr).release()
        _ = kk_channel_close(ch)
    }

    // MARK: - CORO-001: Buffer Overflow Strategy Tests

    /// Test DROP_OLDEST buffer overflow strategy
    func testBufferOverflowDropOldest() {
        // Create a channel with DROP_OLDEST strategy
        let ch = RuntimeChannelHandle(capacity: 2, bufferOverflow: .dropOldest)

        // Fill the buffer
        XCTAssertEqual(ch.send(1), .success)
        XCTAssertEqual(ch.send(2), .success)

        // Send one more - should drop oldest (1) and add new one (3)
        XCTAssertEqual(ch.send(3), .success)

        // Buffer should now contain [2, 3]
        XCTAssertEqual(ch.receive().value, 2)
        XCTAssertEqual(ch.receive().value, 3)
    }

    /// Test DROP_LATEST buffer overflow strategy
    func testBufferOverflowDropLatest() {
        // Create a channel with DROP_LATEST strategy
        let ch = RuntimeChannelHandle(capacity: 2, bufferOverflow: .dropLatest)

        // Fill the buffer
        XCTAssertEqual(ch.send(1), .success)
        XCTAssertEqual(ch.send(2), .success)

        // Send one more - should be dropped, buffer remains [1, 2]
        XCTAssertEqual(ch.send(3), .success)

        // Buffer should still contain [1, 2]
        XCTAssertEqual(ch.receive().value, 1)
        XCTAssertEqual(ch.receive().value, 2)
    }

    /// Test SUSPEND buffer overflow strategy (default behavior)
    func testBufferOverflowSuspendBlocks() {
        let ch = RuntimeChannelHandle(capacity: 1, bufferOverflow: .suspend)

        // Fill the buffer
        XCTAssertEqual(ch.send(1), .success)

        let sendDone = XCTestExpectation(description: "second send completes")
        let sendResult = ThreadSafeInt()

        // Second send should suspend
        DispatchQueue.global().async {
            sendResult.set(ch.send(2).rawValue)
            sendDone.fulfill()
        }

        // Give sender time to suspend
        Thread.sleep(forTimeInterval: 0.05)

        // Receive to free up space
        XCTAssertEqual(ch.receive().value, 1)

        wait(for: [sendDone], timeout: 2.0)
        XCTAssertEqual(sendResult.get(), ChannelOperationStatus.success.rawValue)
    }

    func testCancelAllWaitersWakesSuspendedSenders() {
        let ch = RuntimeChannelHandle(capacity: 0) // rendezvous

        let sendDone = XCTestExpectation(description: "send wakes on cancel")
        let sendResult = ThreadSafeInt()

        DispatchQueue.global().async {
            sendResult.set(ch.send(42).rawValue)
            sendDone.fulfill()
        }

        // Give the sender time to suspend.
        Thread.sleep(forTimeInterval: 0.05)

        // Cancel all waiters.
        ch.cancelAllWaiters()

        wait(for: [sendDone], timeout: 2.0)
        XCTAssertEqual(
            kk_channel_is_closed_token(sendResult.get()), 1,
            "Cancelled sender should get failure status"
        )
    }

    // MARK: - CORO-004: Continuation Model Tests

    /// Test that continuation-based suspension works correctly
    func testContinuationBasedSend() {
        // This test would require codegen support to fully test the continuation model
        // For now, we test that the fallback to semaphore still works
        let ch = kk_channel_create(0) // rendezvous

        let sendDone = XCTestExpectation(description: "send completes")
        let receiveDone = XCTestExpectation(description: "receive completes")
        let sendResult = ThreadSafeInt()
        let receivedValue = ThreadSafeInt()

        DispatchQueue.global().async {
            sendResult.set(kk_channel_send(ch, 42, 0)) // no continuation - fallback to semaphore
            sendDone.fulfill()
        }

        Thread.sleep(forTimeInterval: 0.05)

        DispatchQueue.global().async {
            receivedValue.set(channelReceiveValue(ch, 0))
            receiveDone.fulfill()
        }

        wait(for: [sendDone, receiveDone], timeout: 2.0)
        XCTAssertEqual(receivedValue.get(), 42)
        XCTAssertEqual(sendResult.get(), kChannelResultSuccess)

        _ = kk_channel_close(ch)
    }

    /// Test that the resume methods work correctly
    func testResumeMethodsWork() {
        let ch = RuntimeChannelHandle(capacity: 0)

        // Test that resume methods don't crash and handle nil resumeClosure gracefully
        let sender = SuspendedSender(semaphore: DispatchSemaphore(value: 0), continuation: 0, value: 42)
        let receiver = SuspendedReceiver(semaphore: DispatchSemaphore(value: 0), continuation: 0)

        // These should not crash and should fall back to semaphore
        ch.resumeSender(sender)
        ch.resumeReceiver(receiver)

        // Test with resume closure
        let resumeExpectation = XCTestExpectation(description: "resume closure called")
        let senderWithClosure = SuspendedSender(semaphore: DispatchSemaphore(value: 0), continuation: 0, value: 42)
        senderWithClosure.resumeClosure = {
            resumeExpectation.fulfill()
        }

        ch.resumeSender(senderWithClosure)
        wait(for: [resumeExpectation], timeout: 1.0)
    }

    func testCancelAllWaitersWakesSuspendedReceivers() {
        let ch = RuntimeChannelHandle(capacity: 0) // rendezvous

        let recvDone = XCTestExpectation(description: "receive wakes on cancel")
        let recvResult = ThreadSafeInt()

        DispatchQueue.global().async {
            recvResult.set(ch.receive().status.rawValue)
            recvDone.fulfill()
        }

        // Give the receiver time to suspend.
        Thread.sleep(forTimeInterval: 0.05)

        // Cancel all waiters.
        ch.cancelAllWaiters()

        wait(for: [recvDone], timeout: 2.0)
        XCTAssertEqual(
            kk_channel_is_closed_token(recvResult.get()), 1,
            "Cancelled receiver should get failure status"
        )
    }

    /// BUG-041 deferred `launch{}` must be flushed before channel receive blocks.
    ///
    /// Reproduces the channel_basic.kt hang (diff run exit 124): inside an active
    /// coroutine burst, `launch { send }` is queued in RuntimePendingLaunchQueue
    /// and never dispatched until the burst yields. Channel receive is still a
    /// blocking semaphore wait (not a true suspend point), so without an explicit
    /// flush before `wait()` the receiver deadlocks forever.
    func testReceiveFlushesPendingLaunchBeforeBlocking() {
        let channel = kk_channel_create(0)
        channelPendingLaunchTestState.setChannel(channel)

        RuntimeCoroutineBurstDepth.enter()
        defer {
            RuntimeCoroutineBurstDepth.exit()
            RuntimePendingLaunchQueue.flush()
        }

        let entryRaw = unsafeBitCast(
            runtime_test_channel_pending_launch_send as ChannelPendingLaunchEntry,
            to: Int.self
        )
        let job = kk_kxmini_launch(entryRaw, channelPendingLaunchFunctionID)
        XCTAssertNotEqual(job, 0, "launch should return a job handle")

        var value = 0
        let status = kk_channel_receive(channel, 0, &value)
        XCTAssertEqual(status, kChannelResultSuccess, "receive should complete after flushing the pending sender")
        XCTAssertEqual(value, 42)
        XCTAssertEqual(kk_job_join(job, 0), kChannelResultSuccess)
    }

}
