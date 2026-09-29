import Dispatch
import Foundation

// Channel runtime (CORO-001) and Channel iterator (CORO-075).
//
// Split out from `RuntimeCoroutine.swift`.

// MARK: - Channel Runtime (CORO-001)

/// Out-of-band status codes returned by channel operations.
/// The actual payload (when present) is written to an `outValue` pointer on receive,
/// matching the status+out-pointer pattern used by `kk_coroutine_check_cancellation`.
enum ChannelOperationStatus: Int {
    case success = 0
    case closed = 1
    case cancelled = 2
    case failed = 3
}

let kChannelResultSuccess: Int = ChannelOperationStatus.success.rawValue
let kChannelResultClosed: Int = ChannelOperationStatus.closed.rawValue
let kChannelResultCancelled: Int = ChannelOperationStatus.cancelled.rawValue
let kChannelResultFailed: Int = ChannelOperationStatus.failed.rawValue

/// Buffer overflow strategies for Channel send operations (CORO-001)
enum ChannelBufferOverflow {
    /// Suspend the sender when buffer is full (default Kotlin behavior)
    case suspend
    /// Drop the oldest element in buffer to make room
    case dropOldest
    /// Drop the element being sent
    case dropLatest
}

/// Mutable box for a suspended sender so receivers can mark delivery before
/// resuming the continuation.  Using a class (reference type) ensures the
/// `delivered` flag set under the channel lock is visible to the sender
/// after it re-acquires the lock post-wakeup.
final class SuspendedSender: @unchecked Sendable {
    let semaphore: DispatchSemaphore // CORO-004: Keep for backward compatibility during migration
    let continuation: Int
    let value: Int
    /// CORO-004: Resume closure for continuation-based implementation
    var resumeClosure: (@Sendable () -> Void)?

    /// Set to `true` (under the channel lock) when the sender's value is
    /// delivered to a receiver. The sender checks this after waking to distinguish a
    /// successful delivery from a close-induced wakeup.
    var delivered: Bool = false
    /// Set to `true` (under the channel lock) when the sender is woken due to
    /// coroutine cancellation. Distinct from close-induced wakeup.
    var cancelledWakeup: Bool = false

    init(semaphore: DispatchSemaphore, continuation: Int, value: Int) {
        self.semaphore = semaphore
        self.continuation = continuation
        self.value = value
    }
}

/// Mutable box for a suspended receiver so senders / close can mark the
/// wakeup reason before resuming the continuation. Mirrors `SuspendedSender`.
final class SuspendedReceiver: @unchecked Sendable {
    let semaphore: DispatchSemaphore // CORO-004: Keep for backward compatibility during migration
    let continuation: Int
    /// CORO-004: Resume closure for continuation-based implementation
    var resumeClosure: (@Sendable () -> Void)?
    /// The value deposited by a sender. `nil` means woken by close or cancel.
    var result: Int?
    /// Set to `true` when woken due to coroutine cancellation.
    var cancelledWakeup: Bool = false

    init(semaphore: DispatchSemaphore, continuation: Int) {
        self.semaphore = semaphore
        self.continuation = continuation
    }
}

/// Channel with proper Kotlin suspend semantics:
///   - **Rendezvous** (`capacity == 0`): every `send` suspends until a matching
///     `receive` and vice-versa.
///   - **Buffered** (`capacity > 0`): `send` suspends (backpressure) when the
///     buffer is full; `receive` suspends when the buffer is empty.
///   - **`close()`**: marks the channel as closed.  Pending senders are woken
///     and return the closed-send sentinel.  Pending receivers drain the
///     remaining buffer, then return the closed sentinel.  Returns `true` the
///     first time (Kotlin semantics), `false` if already closed.
///   - **Cancellation**: `send` and `receive` check the caller's continuation
///     for cancellation before suspending, and suspended waiters can be removed
///     via `cancelAllWaiters()` (cooperatively from the coroutine runtime).
final class RuntimeChannelHandle: @unchecked Sendable {
    private let lock = NSLock()
    // `buffer`, `senderQueue`, and `receiverQueue` are head-index FIFO queues:
    // dequeue is O(1) amortized, so draining an UNLIMITED/backed-up channel
    // stays linear instead of quadratic in the buffered element count.
    private var buffer = RuntimeFIFOQueue<Int>()
    let capacity: Int
    private(set) var closed = false
    /// The `Throwable` handle passed to `close(cause:)` / `cancel(cause:)`,
    /// or `0` when the channel is still open or was closed without a cause.
    /// Retained so result-returning operations (`trySend` and friends) can
    /// report the exact close cause via `ChannelResult.exceptionOrNull()`.
    private(set) var closeCause: Int = 0
    private let bufferOverflow: ChannelBufferOverflow

    // Waiting-sender queue: each suspended sender is a `SuspendedSender`
    // reference.  Receivers set `delivered = true` before signaling the
    // semaphore so that senders can distinguish successful delivery from a
    // close-induced wakeup.
    private var senderQueue = RuntimeFIFOQueue<SuspendedSender>()

    // Waiting-receiver queue: each suspended receiver is a `SuspendedReceiver`
    // reference.  Senders deposit a value before signaling the semaphore.
    private var receiverQueue = RuntimeFIFOQueue<SuspendedReceiver>()

    init(capacity: Int, bufferOverflow: ChannelBufferOverflow = .suspend) {
        self.capacity = max(0, capacity)
        self.bufferOverflow = bufferOverflow
    }

    /// Send a value into the channel, suspending (blocking) the caller when
    /// backpressure is needed.
    ///
    /// `continuation` is the opaque continuation handle for the calling coroutine.
    /// When non-zero, cancellation is checked before suspending and the sentinel
    /// is returned if the coroutine has been cancelled (matching Kotlin's behavior
    /// of throwing `CancellationException` from `send`).
    ///
    /// Returns `.success` when the value is delivered, or `.closed` / `.cancelled`
    /// when the channel is closed or the calling coroutine is cancelled.
    func send(_ value: Int, continuation: Int = 0) -> ChannelOperationStatus {
        lock.lock()

        // 0. Check cancellation before any blocking (Kotlin suspend semantics).
        if isCancelled(continuation: continuation) {
            lock.unlock()
            return .cancelled
        }

        // 1. Closed channel -- fail immediately.
        if closed {
            lock.unlock()
            return .closed
        }

        // 2. If there is a waiting receiver, hand the value off directly
        //    (both rendezvous and buffered benefit from this fast path).
        if let receiver = receiverQueue.dequeue() {
            receiver.result = value
            lock.unlock()
            // Preserve rendezvous handoff ordering: let the sender resume and
            // return from `send` before the waiting receiver continues.
            resumeReceiverAsync(receiver)
            return .success
        }

        // 3. Buffered channel with space -- enqueue and return immediately.
        if capacity > 0, buffer.count < capacity {
            buffer.enqueue(value)
            lock.unlock()
            return .success
        }

        // 3a. Handle buffer overflow based on strategy (CORO-001)
        if capacity > 0, buffer.count >= capacity {
            switch bufferOverflow {
            case .suspend:
                // Fall through to suspension logic below
                break
            case .dropOldest:
                // Remove oldest element and add new one
                _ = buffer.dequeue()
                buffer.enqueue(value)
                lock.unlock()
                return .success
            case .dropLatest:
                // Drop the element being sent
                lock.unlock()
                return .success
            }
        }

        // 4. No room (buffer full or rendezvous) -- suspend the sender.
        // CORO-004: Store continuation for later dispatch while maintaining
        // semaphore compatibility during migration.
        let senderSem = DispatchSemaphore(value: 0)
        let entry = SuspendedSender(semaphore: senderSem, continuation: continuation, value: value)

        senderQueue.enqueue(entry)
        lock.unlock()

        // Channel send is not yet lowered as a true suspend point, so the
        // runtime must block here until a receiver or close/cancellation wakes it.
        // BUG-041 interaction: flush undispatched launch{} work before blocking
        // so a sibling `launch { receive() }` queued on this thread can run.
        RuntimePendingLaunchQueue.flush()
        runtimeWaitDrainingEventLoop(senderSem)

        // After waking, check the wakeup reason.
        lock.lock()
        let wasDelivered = entry.delivered
        let wasCancelled = entry.cancelledWakeup
        lock.unlock()

        // Cancellation only aborts the send if delivery did not already complete.
        if wasCancelled || (!wasDelivered && isCancelled(continuation: continuation)) {
            return wasCancelled ? .cancelled : .closed
        }
        return wasDelivered ? .success : .closed
    }

    /// Attempt to send a value without suspending.  A full rendezvous or
    /// buffered channel reports `.failed`; a closed channel reports `.closed`.
    func trySend(_ value: Int) -> ChannelOperationStatus {
        lock.lock()

        if closed {
            lock.unlock()
            return .closed
        }

        if let receiver = receiverQueue.dequeue() {
            receiver.result = value
            lock.unlock()
            resumeReceiverAsync(receiver)
            return .success
        }

        if capacity > 0, buffer.count < capacity {
            buffer.enqueue(value)
            lock.unlock()
            return .success
        }

        if capacity > 0, buffer.count >= capacity {
            switch bufferOverflow {
            case .suspend:
                break
            case .dropOldest:
                _ = buffer.dequeue()
                buffer.enqueue(value)
                lock.unlock()
                return .success
            case .dropLatest:
                lock.unlock()
                return .success
            }
        }

        lock.unlock()
        return .failed
    }

    /// Receive a value from the channel, suspending (blocking) the caller when
    /// the buffer is empty and no sender is ready.
    ///
    /// `continuation` is the opaque continuation handle for the calling coroutine.
    /// When non-zero, cancellation is checked before suspending (Kotlin suspend
    /// semantics: `receive` throws `CancellationException` if cancelled).
    ///
    /// On `.success`, writes the received value to `outValue`.  Returns `.closed`
    /// when the channel is closed and fully drained, or `.cancelled` when the
    /// coroutine was cancelled.
    func receive(continuation: Int = 0, outValue: UnsafeMutablePointer<Int>) -> ChannelOperationStatus {
        lock.lock()

        // 0. Check cancellation before any blocking (Kotlin suspend semantics).
        if isCancelled(continuation: continuation) {
            lock.unlock()
            return .cancelled
        }

        // 1. Try to take from the buffer.
        if let value = buffer.dequeue() {
            // If a sender is suspended (backpressure), wake the oldest one and
            // move its value into the buffer to maintain ordering.
            if let sender = senderQueue.dequeue() {
                buffer.enqueue(sender.value)
                sender.delivered = true
                lock.unlock()
                // CORO-004: Use continuation-based resume if available
                resumeSender(sender)
            } else {
                lock.unlock()
            }
            outValue.pointee = value
            return .success
        }

        // 2. Buffer is empty -- try to pair directly with a waiting sender
        //    (rendezvous fast-path, also applies to buffered when a sender
        //    arrived while the buffer was full and then got drained completely).
        if let sender = senderQueue.dequeue() {
            let value = sender.value
            sender.delivered = true
            lock.unlock()
            // CORO-004: Use continuation-based resume if available
            resumeSender(sender)
            outValue.pointee = value
            return .success
        }

        // 3. Nothing available -- if closed, report closed status.
        if closed {
            lock.unlock()
            return .closed
        }

        // 4. Suspend the receiver.
        // CORO-004: Store continuation for later dispatch while maintaining
        // semaphore compatibility during migration.
        let receiverEntry = SuspendedReceiver(semaphore: DispatchSemaphore(value: 0), continuation: continuation)

        receiverQueue.enqueue(receiverEntry)
        lock.unlock()

        // Channel receive is not yet lowered as a true suspend point, so the
        // runtime must block here until a sender, close, or cancellation wakes it.
        // BUG-041 interaction: flush undispatched launch{} work before blocking
        // so a sibling `launch { send(x) }` queued on this thread can run.
        // Without this, channel_basic-style rendezvous deadlocks (run exit 124).
        // On a runBlocking event loop the flush only *queues* that sibling, so
        // the wait below has to keep draining the queue rather than park.
        RuntimePendingLaunchQueue.flush()
        runtimeWaitDrainingEventLoop(receiverEntry.semaphore)

        // After waking, check the wakeup reason.
        lock.lock()
        let wasCancelled = receiverEntry.cancelledWakeup
        let value = receiverEntry.result
        lock.unlock()

        // Cancellation only aborts the receive if no sender delivered a value.
        if wasCancelled || (value == nil && isCancelled(continuation: continuation)) {
            return wasCancelled ? .cancelled : .closed
        }
        if let value {
            outValue.pointee = value
            return .success
        }
        // Woken by close() with no value -- channel is done.
        return .closed
    }

    /// Convenience wrapper used by in-process runtime tests.
    func receive(continuation: Int = 0) -> (status: ChannelOperationStatus, value: Int) {
        var value = 0
        let status = receive(continuation: continuation, outValue: &value)
        return (status, value)
    }

    /// `true` when the channel is closed AND its buffer is fully drained.
    /// Once `isClosedForReceive` is `true`, any subsequent `receive()` call will
    /// immediately return `.closed` without blocking.
    /// Matches Kotlin's `ReceiveChannel.isClosedForReceive` contract.
    var isClosedForReceive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return closed && buffer.isEmpty && senderQueue.isEmpty
    }

    /// Close the channel.  Remaining buffered values are still receivable.
    ///
    /// `cause` is the optional `Throwable` handle carried by Kotlin's
    /// `close(cause: Throwable?)` / `ReceiveChannel.cancel(cause:)`; the first
    /// successful close retains it for `ChannelResult`-based queries. A `0`
    /// cause marks a normal close.
    ///
    /// Returns `true` if this call actually closed the channel, `false` if it
    /// was already closed.  Matches Kotlin's `SendChannel.close()` contract.
    @discardableResult
    func close(cause: Int = 0) -> Bool {
        lock.lock()
        if closed {
            lock.unlock()
            return false
        }
        closed = true
        closeCause = cause
        let pendingSenders = senderQueue.drain()
        let pendingReceivers = receiverQueue.drain()
        lock.unlock()

        // Wake all suspended senders -- they will see `closed == true` and
        // return the closed sentinel.
        for sender in pendingSenders {
            // CORO-004: Use continuation-based resume if available
            resumeSender(sender)
        }
        // Wake all suspended receivers -- they will find no result deposited
        // and return the closed sentinel.
        for receiver in pendingReceivers {
            // CORO-004: Use continuation-based resume if available
            resumeReceiver(receiver)
        }
        return true
    }

    /// Thread-safe snapshot of the retained close cause (0 when none).
    func closeCauseSnapshot() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return closeCause
    }

    /// `true` when no element is currently receivable: the buffer is drained
    /// and no suspended sender is waiting to hand off a value.
    /// Matches Kotlin's `ReceiveChannel.isEmpty` contract.
    func isEmptySnapshot() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return buffer.isEmpty && senderQueue.isEmpty
    }

    /// Cancel all suspended senders and receivers.  This is called when a
    /// coroutine is cancelled while it has an outstanding channel operation.
    ///
    /// In the current design we cancel *all* waiters because the continuation
    /// identity is not threaded into the waiter entries (the suspend-point is
    /// blocking the calling thread directly).  This is safe because each
    /// channel operation is called from exactly one coroutine at a time.
    func cancelAllWaiters() {
        lock.lock()
        let pendingSenders = senderQueue.drain()
        let pendingReceivers = receiverQueue.drain()
        lock.unlock()

        for sender in pendingSenders {
            sender.cancelledWakeup = true
            // CORO-004: Use continuation-based resume if available
            resumeSender(sender)
        }
        for receiver in pendingReceivers {
            receiver.cancelledWakeup = true
            // CORO-004: Use continuation-based resume if available
            resumeReceiver(receiver)
        }
    }

    /// Returns the current suspended waiter counts under the channel lock.
    ///
    /// Runtime tests use this snapshot to synchronize with actual suspension
    /// instead of assuming a background queue has progressed after a fixed delay.
    func suspendedWaiterCountsSnapshot() -> (senders: Int, receivers: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (senderQueue.count, receiverQueue.count)
    }

    // MARK: - Private helpers

    /// CORO-004: Resume a suspended sender using continuation model if available,
    /// falling back to semaphore for backward compatibility.
    func resumeSender(_ sender: SuspendedSender) {
        if let resumeClosure = sender.resumeClosure {
            // Continuation-based implementation
            DispatchQueue.global().async {
                resumeClosure()
            }
        } else {
            // Fallback to semaphore
            sender.semaphore.signal()
        }
    }

    /// CORO-004: Resume a suspended receiver using continuation model if available,
    /// falling back to semaphore for backward compatibility.
    func resumeReceiver(_ receiver: SuspendedReceiver) {
        if let resumeClosure = receiver.resumeClosure {
            // Continuation-based implementation
            DispatchQueue.global().async {
                resumeClosure()
            }
        } else {
            // Fallback to semaphore
            receiver.semaphore.signal()
        }
    }

    /// Dispatch receiver wakeup asynchronously even for semaphore-backed waiters.
    /// This keeps direct sender->receiver handoff aligned with Kotlin's observed
    /// rendezvous ordering where the sender resumes from `send` before the
    /// receiver continues past `receive`.
    func resumeReceiverAsync(_ receiver: SuspendedReceiver) {
        DispatchQueue.global().async {
            self.resumeReceiver(receiver)
        }
    }

    /// Check whether the coroutine associated with `continuation` has been cancelled.
    private func isCancelled(continuation: Int) -> Bool {
        guard continuation != 0 else {
            return false
        }
        guard let state = runtimeContinuationState(from: continuation),
              let job = state.jobHandle
        else {
            return false
        }
        return job.cancellationSnapshot()
    }

    /// Thread-safe snapshot of the closed flag.
    ///
    /// Acquires the channel lock before reading `closed` to avoid data races
    /// with concurrent `send()`, `receive()`, and `close()` calls.
    func isClosedSnapshot() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return closed
    }
}

@_cdecl("kk_channel_create")
public func kk_channel_create(_ capacity: Int) -> Int {
    let channel = RuntimeChannelHandle(capacity: capacity)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(channel).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

public func kk_channel_send(_ handle: Int, _ value: Int) -> Int {
    kk_channel_send(handle, value, 0)
}

@_cdecl("kk_channel_send")
public func kk_channel_send(_ handle: Int, _ value: Int, _ continuation: Int) -> Int {
    func isRegisteredChannelHandle(_ raw: Int) -> Bool {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
            return false
        }
        let isRegistered = runtimeStorage.withGCLock { state in
            state.objectPointers.contains(UInt(bitPattern: ptr))
        }
        guard isRegistered else {
            return false
        }
        return tryCast(ptr, to: RuntimeChannelHandle.self) != nil
    }

    let resolvedHandle: Int
    let resolvedValue: Int
    if !isRegisteredChannelHandle(handle), isRegisteredChannelHandle(value) {
        resolvedHandle = value
        resolvedValue = handle
    } else {
        resolvedHandle = handle
        resolvedValue = value
    }

    guard let resolvedPtr = UnsafeMutableRawPointer(bitPattern: resolvedHandle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_channel_send received invalid channel handle")
    }
    let channel = Unmanaged<RuntimeChannelHandle>.fromOpaque(resolvedPtr).takeUnretainedValue()
    return channel.send(resolvedValue, continuation: continuation).rawValue
}

/// Non-suspending channel send used by `ProducerScope.trySend`.
@_cdecl("kk_channel_try_send")
public func kk_channel_try_send(_ handle: Int, _ value: Int) -> Int {
    func isRegisteredChannelHandle(_ raw: Int) -> Bool {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
            return false
        }
        let isRegistered = runtimeStorage.withGCLock { state in
            state.objectPointers.contains(UInt(bitPattern: ptr))
        }
        guard isRegistered else {
            return false
        }
        return tryCast(ptr, to: RuntimeChannelHandle.self) != nil
    }

    let resolvedHandle: Int
    let resolvedValue: Int
    if !isRegisteredChannelHandle(handle), isRegisteredChannelHandle(value) {
        resolvedHandle = value
        resolvedValue = handle
    } else {
        resolvedHandle = handle
        resolvedValue = value
    }

    guard let resolvedPtr = UnsafeMutableRawPointer(bitPattern: resolvedHandle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_channel_try_send received invalid channel handle")
    }
    let channel = Unmanaged<RuntimeChannelHandle>.fromOpaque(resolvedPtr).takeUnretainedValue()
    return channel.trySend(resolvedValue).rawValue
}

// MARK: - ChannelResult token encoding (KSP-1571)
//
// `ChannelResult` is a `@JvmInline value class` over a single Int token so an
// `external` member on `SendChannel` can return it directly.  The token packs
// a 2-bit tag with a payload pointer:
//
//   token = (payload << 2) | tag
//   tag 0 = success (payload = element pointer, or the shared Unit box)
//   tag 1 = closed  (payload = retained close-cause `Throwable` pointer, or 0)
//   tag 2 = failed  (payload = 0)
//
// Payloads are registered object pointers, so `payload << 2` stays positive
// and `token >>> 2` restores the pointer exactly.

private let kChannelResultTagShift = 2
private let kChannelResultTagSuccess = 0
private let kChannelResultTagClosed = 1
private let kChannelResultTagFailed = 2

/// trySend variant returning the tagged `ChannelResult` token consumed by the
/// bundled `SendChannel.trySend` member.  Argument order is swizzled the same
/// way as `kk_channel_try_send` (member bindings do not guarantee receiver
/// position).
@_cdecl("__kk_channel_try_send")
public func kk_channel_try_send_tagged(_ arg0: Int, _ arg1: Int) -> Int {
    func isRegisteredChannelHandle(_ raw: Int) -> Bool {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
            return false
        }
        let isRegistered = runtimeStorage.withGCLock { state in
            state.objectPointers.contains(UInt(bitPattern: ptr))
        }
        guard isRegistered else {
            return false
        }
        return tryCast(ptr, to: RuntimeChannelHandle.self) != nil
    }

    let resolvedHandle: Int
    let resolvedValue: Int
    if !isRegisteredChannelHandle(arg0), isRegisteredChannelHandle(arg1) {
        resolvedHandle = arg1
        resolvedValue = arg0
    } else {
        resolvedHandle = arg0
        resolvedValue = arg1
    }

    guard let resolvedPtr = UnsafeMutableRawPointer(bitPattern: resolvedHandle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_channel_try_send received invalid channel handle")
    }
    let channel = Unmanaged<RuntimeChannelHandle>.fromOpaque(resolvedPtr).takeUnretainedValue()
    let status = channel.trySend(resolvedValue)
    switch status {
    case .success:
        let unitPayload = kk_box_unit(0)
        return (unitPayload << kChannelResultTagShift) | kChannelResultTagSuccess
    case .closed, .cancelled:
        let cause = channel.closeCauseSnapshot()
        return (cause << kChannelResultTagShift) | kChannelResultTagClosed
    case .failed:
        return kChannelResultTagFailed
    }
}

/// Decode helper: returns the element/value pointer stored in a success token
/// (`token >>> 2` when tag == 0), or 0 for non-success tokens.
@_cdecl("__kk_channel_result_value")
public func kk_channel_result_value(_ token: Int) -> Int {
    guard (token & 3) == kChannelResultTagSuccess, token != 0 else {
        return 0
    }
    return token >> kChannelResultTagShift
}

/// Decode helper: returns the close-cause `Throwable` pointer stored in a
/// closed token (`token >>> 2` when tag == 1), or 0 for non-closed tokens.
@_cdecl("__kk_channel_result_cause")
public func kk_channel_result_cause(_ token: Int) -> Int {
    guard (token & 3) == kChannelResultTagClosed else {
        return 0
    }
    return token >> kChannelResultTagShift
}

/// Encode helper for `ChannelResult.Companion.success(value)`: packs the
/// element pointer into a success token.
@_cdecl("__kk_channel_result_success")
public func kk_channel_result_success(_ value: Int) -> Int {
    if value == 0 {
        return 0
    }
    return (value << kChannelResultTagShift) | kChannelResultTagSuccess
}

/// Encode helper for `ChannelResult.Companion.closed(cause)`: packs the cause
/// `Throwable` pointer (or 0) into a closed token.
@_cdecl("__kk_channel_result_closed")
public func kk_channel_result_closed(_ cause: Int) -> Int {
    return (cause << kChannelResultTagShift) | kChannelResultTagClosed
}

@_cdecl("kk_channel_receive")
public func kk_channel_receive(
    _ handle: Int,
    _ continuation: Int,
    _ outValue: UnsafeMutablePointer<Int>?
) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_channel_receive received invalid channel handle")
    }
    let channel = Unmanaged<RuntimeChannelHandle>.fromOpaque(ptr).takeUnretainedValue()
    if let outValue {
        return channel.receive(continuation: continuation, outValue: outValue).rawValue
    }
    var scratch = 0
    return channel.receive(continuation: continuation, outValue: &scratch).rawValue
}

@_cdecl("kk_channel_close")
public func kk_channel_close(_ handle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_channel_close received invalid channel handle")
    }
    let channel = Unmanaged<RuntimeChannelHandle>.fromOpaque(ptr).takeUnretainedValue()
    return channel.close() ? 1 : 0
}

/// Returns 1 when `status` indicates a closed or cancelled channel operation,
/// 0 for successful and non-closed try-send failures.
@_cdecl("kk_channel_is_closed_token")
public func kk_channel_is_closed_token(_ status: Int) -> Int {
    return status == kChannelResultClosed || status == kChannelResultCancelled ? 1 : 0
}

/// Returns 1 if the channel is closed for receiving (i.e., it is closed AND the buffer
/// is empty — no more values will ever be available).  Returns 0 if the channel is
/// open or if it is closed but still has buffered values to drain.
///
/// Maps to Kotlin's `Channel.isClosedForReceive` property.
@_cdecl("kk_channel_is_closed_for_receive")
public func kk_channel_is_closed_for_receive(_ handle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_channel_is_closed_for_receive received invalid channel handle")
    }
    let channel = Unmanaged<RuntimeChannelHandle>.fromOpaque(ptr).takeUnretainedValue()
    return channel.isClosedForReceive ? 1 : 0
}

/// Returns 1 if the channel is closed for sending (i.e., it has been closed via
/// `close()`).  Returns 0 if the channel is still open for new sends.
///
/// Maps to Kotlin's `Channel.isClosedForSend` property.
@_cdecl("kk_channel_is_closed_for_send")
public func kk_channel_is_closed_for_send(_ handle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_channel_is_closed_for_send received invalid channel handle")
    }
    let channel = Unmanaged<RuntimeChannelHandle>.fromOpaque(ptr).takeUnretainedValue()
    return channel.isClosedSnapshot() ? 1 : 0
}

/// Returns 1 when the channel currently has no receivable element: the buffer
/// is empty and no suspended sender is waiting to hand off a value.
///
/// Maps to Kotlin's `ReceiveChannel.isEmpty` property.
@_cdecl("kk_channel_is_empty")
public func kk_channel_is_empty(_ handle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_channel_is_empty received invalid channel handle")
    }
    let channel = Unmanaged<RuntimeChannelHandle>.fromOpaque(ptr).takeUnretainedValue()
    return channel.isEmptySnapshot() ? 1 : 0
}

/// Returns the `Throwable` handle retained by the first successful
/// `close(cause:)` / `cancel(cause:)`, or 0 when the channel was closed
/// without a cause (or is still open).  Consumed by Kotlin-side
/// `ChannelResult` / `consume` helpers to surface `exceptionOrNull()`.
@_cdecl("kk_channel_close_cause")
public func kk_channel_close_cause(_ handle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_channel_close_cause received invalid channel handle")
    }
    let channel = Unmanaged<RuntimeChannelHandle>.fromOpaque(ptr).takeUnretainedValue()
    return channel.closeCauseSnapshot()
}

/// Close-with-cause bridge for Kotlin's `SendChannel.close(cause:)` and
/// `ReceiveChannel.cancel(cause:)`. `cause` is a `Throwable` object handle or
/// 0.  Returns 1 the first time the channel actually closes, 0 when it was
/// already closed.
@_cdecl("__kk_channel_close_cause")
public func kk_channel_close_cause(_ handle: Int, _ cause: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_channel_close_cause received invalid channel handle")
    }
    let channel = Unmanaged<RuntimeChannelHandle>.fromOpaque(ptr).takeUnretainedValue()
    return channel.close(cause: cause) ? 1 : 0
}

// MARK: - Channel Iterator (CORO-075)
//
// A lightweight wrapper that allows channels to participate in the
// `kk_range_iterator` / `kk_range_hasNext` / `kk_range_next` loop protocol.
//
// The iterator holds the channel handle (strongly retained) and caches the
// result of the most recent `receive()` call.  `hasNext` must be called before
// `next` in each iteration step — which matches the pattern emitted by
// ControlFlowLowerer.lowerForExpr.
//
// IMPORTANT: `kk_channel_iterator_hasNext` suspends (blocking) on each call
// until either a value arrives or the channel is closed.  This means that
// for-in loops over channels are blocking-suspend operations, consistent with
// Kotlin's semantics when running inside runBlocking / launch.
private final class RuntimeChannelIterator: @unchecked Sendable {
    let channel: RuntimeChannelHandle
    /// Most recent value fetched by `hasNext`.  Reset to `nil` after `next`.
    var peekedValue: Int?
    /// Set to `true` once we observe the closed sentinel from `receive()`.
    var done: Bool = false
    private let lock = NSLock()

    init(channel: RuntimeChannelHandle) {
        self.channel = channel
    }

    /// Advance the iterator by doing a blocking receive.  Returns `true` if a
    /// value is available, `false` if the channel is closed and drained.
    func advance(continuation: Int = 0) -> Bool {
        lock.lock()
        if done {
            lock.unlock()
            return false
        }
        lock.unlock()

        var value = 0
        let status = channel.receive(continuation: continuation, outValue: &value)
        lock.lock()
        defer { lock.unlock() }
        if status != .success {
            done = true
            peekedValue = nil
            return false
        }
        peekedValue = value
        return true
    }

    /// Return the cached value and clear it.
    func takeValue() -> Int {
        lock.lock()
        defer { lock.unlock() }
        let v = peekedValue ?? 0
        peekedValue = nil
        return v
    }
}

/// Create a channel iterator for use in for-in loops.  The iterator reference
/// is registered in `runtimeStorage` so the GC can track it.
@_cdecl("kk_channel_iterator")
public func kk_channel_iterator(_ handle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_channel_iterator received invalid channel handle")
    }
    let channel = Unmanaged<RuntimeChannelHandle>.fromOpaque(ptr).takeUnretainedValue()
    let iter = RuntimeChannelIterator(channel: channel)
    let iterPtr = UnsafeMutableRawPointer(Unmanaged.passRetained(iter).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: iterPtr))
    }
    return Int(bitPattern: iterPtr)
}

/// Returns 1 if the channel iterator has a next value, 0 if the channel is
/// closed and drained.  Blocks (suspends) until a value arrives or the channel
/// is closed.
@_cdecl("kk_channel_iterator_hasNext")
public func kk_channel_iterator_hasNext(_ iterHandle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: iterHandle) else {
        return 0
    }
    let iter = Unmanaged<RuntimeChannelIterator>.fromOpaque(ptr).takeUnretainedValue()
    return iter.advance() ? 1 : 0
}

/// Returns the value fetched by the most recent `kk_channel_iterator_hasNext`
/// call.  Must only be called after `kk_channel_iterator_hasNext` returns 1.
@_cdecl("kk_channel_iterator_next")
public func kk_channel_iterator_next(_ iterHandle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: iterHandle) else {
        return 0
    }
    let iter = Unmanaged<RuntimeChannelIterator>.fromOpaque(ptr).takeUnretainedValue()
    return iter.takeValue()
}

/// Read an element from a runtime array by index (mirrors kk_array_get without throw).
func runtimeReadArrayElement(arrayRaw: Int, index: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: arrayRaw) else {
        return 0
    }
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return 0
    }
    guard let arrayBox = tryCast(ptr, to: RuntimeArrayBox.self) else {
        return 0
    }
    guard index >= 0, index < arrayBox.count else {
        return 0
    }
    return arrayBox[index]
}
