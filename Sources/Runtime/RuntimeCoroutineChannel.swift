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

    // KSP-1573: `invokeOnClose` handlers, as (fnPtr, closureRaw) function-value
    // pairs.  They run exactly once, on the first successful `close()`, with a
    // nil cause argument until `close(cause:)` lands.
    private var closeHandlers: [(fnPtr: Int, closureRaw: Int)] = []

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

    /// Attempt to receive a value without suspending (KSP-1572).
    ///
    /// Mirrors the non-suspending prefix of `receive(continuation:outValue:)`:
    /// drain the buffer, then pair with the oldest waiting sender. An empty
    /// but open channel reports `.failed`; a closed and fully drained channel
    /// reports `.closed`. Every state transition happens under the channel
    /// lock, so the result is a consistent atomic snapshot of the channel.
    func tryReceive(outValue: UnsafeMutablePointer<Int>) -> ChannelOperationStatus {
        lock.lock()

        // 1. Try to take from the buffer, waking the oldest suspended sender
        //    so its value keeps FIFO ordering behind the drained element.
        if let value = buffer.dequeue() {
            if let sender = senderQueue.dequeue() {
                buffer.enqueue(sender.value)
                sender.delivered = true
                lock.unlock()
                resumeSender(sender)
            } else {
                lock.unlock()
            }
            outValue.pointee = value
            return .success
        }

        // 2. Buffer is empty -- pair directly with a waiting sender.
        if let sender = senderQueue.dequeue() {
            let value = sender.value
            sender.delivered = true
            lock.unlock()
            resumeSender(sender)
            outValue.pointee = value
            return .success
        }

        // 3. Nothing available without suspending.
        if closed {
            lock.unlock()
            return .closed
        }

        lock.unlock()
        return .failed
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
        // A Kotlin `null` cause arrives as the null sentinel; store 0 so
        // `closeCauseSnapshot` keeps its "no cause" contract.
        closeCause = cause == runtimeNullSentinelInt ? 0 : cause
        let pendingSenders = senderQueue.drain()
        let pendingReceivers = receiverQueue.drain()
        let pendingCloseHandlers = closeHandlers
        closeHandlers.removeAll()
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
        for handler in pendingCloseHandlers {
            guard handler.fnPtr != 0 else { continue }
            _ = runtimeInvokeCollectionLambda1MaybeWrapped(
                fnPtr: handler.fnPtr,
                closureRaw: handler.closureRaw,
                value: runtimeNullSentinelInt,
                outThrown: nil
            )
        }
        return true
    }

    /// Registers an `invokeOnClose` handler (KSP-1573).
    ///
    /// Returns `true` when the handler was queued and will run on the first
    /// close.  When the channel is already closed the handler is invoked
    /// inline with a nil cause, matching kotlinx.coroutines semantics, and
    /// `false` is returned.
    @discardableResult
    func addCloseHandler(fnPtr: Int, closureRaw: Int) -> Bool {
        lock.lock()
        if closed {
            lock.unlock()
            guard fnPtr != 0 else { return false }
            _ = runtimeInvokeCollectionLambda1MaybeWrapped(
                fnPtr: fnPtr,
                closureRaw: closureRaw,
                value: runtimeNullSentinelInt,
                outThrown: nil
            )
            return false
        }
        closeHandlers.append((fnPtr, closureRaw))
        lock.unlock()
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

/// KSP-1573: `Channel(capacity, onBufferOverflow)` factory bridge. The
/// `onBufferOverflow` argument is the `BufferOverflow` ordinal (0 SUSPEND,
/// 1 DROP_OLDEST, 2 DROP_LATEST).  Negative capacity values keep their
/// kotlinx.coroutines sentinel semantics: -1 CONFLATED maps to a
/// one-slot DROP_OLDEST channel, -2 BUFFERED expands to the default buffer
/// size, and -3 OPTIONAL_CHANNEL falls back to a rendezvous channel.
@_cdecl("__kk_channel_create_with_policy")
public func __kk_channel_create_with_policy(_ capacity: Int, _ onBufferOverflow: Int) -> Int {
    var resolvedCapacity = capacity
    var overflow: ChannelBufferOverflow
    switch onBufferOverflow {
    case 1:
        overflow = .dropOldest
    case 2:
        overflow = .dropLatest
    default:
        overflow = .suspend
    }
    switch capacity {
    case -1:
        resolvedCapacity = 1
        overflow = .dropOldest
    case -2:
        resolvedCapacity = 64
    case -3:
        resolvedCapacity = 0
    default:
        break
    }
    let channel = RuntimeChannelHandle(capacity: resolvedCapacity, bufferOverflow: overflow)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(channel).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

/// KSP-1573: `SendChannel.invokeOnClose(handler)` bridge. `handler` crosses
/// the boundary as an (fnPtr, closureRaw) pair, the same function-value
/// convention `kk_job_invoke_on_completion` uses. The handler is invoked with
/// a nil cause when the channel first closes, or immediately when it is
/// already closed.
@_cdecl("__kk_channel_invoke_on_close")
public func __kk_channel_invoke_on_close(_ handle: Int, _ handlerFnPtr: Int, _ handlerClosureRaw: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle),
          let channel = tryCast(ptr, to: RuntimeChannelHandle.self)
    else {
        return 0
    }
    return channel.addCloseHandler(fnPtr: handlerFnPtr, closureRaw: handlerClosureRaw) ? 1 : 0
}

/// Identity bridge used by bundled stdlib declarations that reinterpret a
/// runtime handle under a different static type (e.g. Channel as
/// ProducerScope/SendChannel) where both sides share the same object
/// representation.
@_cdecl("__kk_identity")
public func __kk_identity(_ value: Int) -> Int {
    value
}

/// True when `raw` is a GC-registered `RuntimeChannelHandle`.
///
/// Channel send ABIs take `(handle, value)` where both sides are the same
/// `Int` slot width; compiled code can reach them with the receiver and the
/// element in either order, so the callee resolves the handle positionally.
private func runtimeIsRegisteredChannelHandle(_ raw: Int) -> Bool {
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

/// Split a `(handle, value)` channel call pair into its parts, tolerating
/// the receiver arriving in either argument position.
private func runtimeResolveChannelCall(_ handle: Int, _ value: Int) -> (channel: RuntimeChannelHandle, value: Int) {
    let resolvedHandle: Int
    let resolvedValue: Int
    if !runtimeIsRegisteredChannelHandle(handle), runtimeIsRegisteredChannelHandle(value) {
        resolvedHandle = value
        resolvedValue = handle
    } else {
        resolvedHandle = handle
        resolvedValue = value
    }

    guard let resolvedPtr = UnsafeMutableRawPointer(bitPattern: resolvedHandle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: channel ABI received invalid channel handle")
    }
    let channel = Unmanaged<RuntimeChannelHandle>.fromOpaque(resolvedPtr).takeUnretainedValue()
    return (channel, resolvedValue)
}

public func kk_channel_send(_ handle: Int, _ value: Int) -> Int {
    kk_channel_send(handle, value, 0)
}

@_cdecl("kk_channel_send")
public func kk_channel_send(_ handle: Int, _ value: Int, _ continuation: Int) -> Int {
    let (channel, resolvedValue) = runtimeResolveChannelCall(handle, value)
    return channel.send(resolvedValue, continuation: continuation).rawValue
}

/// Non-suspending channel send used by `ProducerScope.trySend`.
@_cdecl("kk_channel_try_send")
public func kk_channel_try_send(_ handle: Int, _ value: Int) -> Int {
    let (channel, resolvedValue) = runtimeResolveChannelCall(handle, value)
    return channel.trySend(resolvedValue).rawValue
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

// MARK: - ChannelResult Box (KSP-1572; close-cause extension KSP-1571)
//
// `ChannelResult<T>` is exposed to bundled Kotlin source as an opaque box
// handle, mirroring `RuntimeResultBox` / `kotlin.Result`. The box pairs the
// out-of-band `ChannelOperationStatus` with the received element so a single
// `Int` return can carry both halves of a tryReceive/receiveCatching result,
// plus the close cause a closed/cancelled operation reports.

final class RuntimeChannelResultBox {
    /// `ChannelOperationStatus` raw value (success / closed / cancelled / failed).
    let status: Int
    /// The received element on success, 0 otherwise.
    let value: Int
    /// Close cause `Throwable` handle carried by closed/cancelled results
    /// (upstream `Closed.closeCause`), 0 when none.
    let cause: Int

    init(status: Int, value: Int, cause: Int) {
        self.status = status
        self.value = value
        self.cause = cause
    }
}

/// `kotlinx.coroutines.channels.ClosedSendChannelException`, materialised for
/// closed send-side results whose channel has no retained cause (upstream's
/// `sendException = closeCause ?: ClosedSendChannelException(DEFAULT)`).
final class RuntimeClosedSendChannelExceptionBox: RuntimeThrowableBox {
    override var exceptionFQName: String {
        "kotlinx.coroutines.channels.ClosedSendChannelException"
    }

    override var exceptionHierarchyFQNames: [String] {
        [
            "kotlinx.coroutines.channels.ClosedSendChannelException",
            "kotlin.IllegalStateException",
            "kotlin.RuntimeException",
            "kotlin.Exception",
            "kotlin.Throwable",
        ]
    }

    override var renderedMessage: String {
        runtimeRenderedExceptionMessage("ClosedSendChannelException", message)
    }
}

/// Allocates a `kotlinx.coroutines.channels.ClosedSendChannelException`.
func runtimeAllocateClosedSendChannelException(message: String? = "Channel was closed") -> Int {
    let throwable = RuntimeClosedSendChannelExceptionBox(message: message)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(throwable).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

private func channelResultBoxFromRaw(_ raw: Int) -> RuntimeChannelResultBox? {
    guard let pointer = normalizeNullableRuntimePointer(UnsafeMutableRawPointer(bitPattern: raw)) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: pointer))
    }
    guard isObjectPointer else {
        return nil
    }
    return tryCast(pointer, to: RuntimeChannelResultBox.self)
}

private func runtimeChannelResultBox(status: ChannelOperationStatus, value: Int, cause: Int) -> Int {
    registerRuntimeObject(
        RuntimeChannelResultBox(status: status.rawValue, value: value, cause: cause),
        typeID: runtimeStableNominalTypeID(fqName: "kotlinx.coroutines.channels.ChannelResult")
    )
}

/// Close cause for a send-side operation result box: the channel's retained
/// close cause when present, otherwise upstream's `sendException` — upstream
/// bakes `closeCause ?: ClosedSendChannelException` into send results at
/// operation time. Receive-side ops store the raw close cause instead (their
/// `Closed` holder keeps it nullable).
private func channelResultSendCause(channel: RuntimeChannelHandle, status: ChannelOperationStatus) -> Int {
    guard status == .closed || status == .cancelled else {
        return 0
    }
    let retained = channel.closeCauseSnapshot()
    return retained != 0 ? retained : runtimeAllocateClosedSendChannelException()
}

/// Close cause for a receive-side operation result box: the channel's retained
/// close cause verbatim (0 when the channel closed normally) — upstream
/// `tryReceive`/`receiveCatching` report `closed(closeCause)`.
private func channelResultReceiveCause(channel: RuntimeChannelHandle, status: ChannelOperationStatus) -> Int {
    guard status == .closed || status == .cancelled else {
        return 0
    }
    return channel.closeCauseSnapshot()
}

/// KSP-1572: `ReceiveChannel.tryReceive()` bridge. Non-blocking receive that
/// returns a `ChannelResult` box instead of a bare status so the received
/// element travels with the status.
@_cdecl("__kk_channel_try_receive")
public func __kk_channel_try_receive(_ handle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_channel_try_receive received invalid channel handle")
    }
    let channel = Unmanaged<RuntimeChannelHandle>.fromOpaque(ptr).takeUnretainedValue()
    var value = 0
    let status = channel.tryReceive(outValue: &value)
    let cause = channelResultReceiveCause(channel: channel, status: status)
    return runtimeChannelResultBox(status: status, value: value, cause: cause)
}

/// KSP-1572: `SendChannel.trySend(element)` bridge returning a `ChannelResult`
/// box. `kk_channel_try_send` keeps its bare-status contract for runtime
/// tests; this variant produces the boxed shape `ChannelResult` exposes.
@_cdecl("__kk_channel_try_send")
public func __kk_channel_try_send(_ handle: Int, _ value: Int) -> Int {
    let (channel, resolvedValue) = runtimeResolveChannelCall(handle, value)
    let status = channel.trySend(resolvedValue)
    let cause = channelResultSendCause(channel: channel, status: status)
    // trySend succeeds with `Unit`: store the shared Unit box (upstream's
    // `success(Unit)` holder) so getOrNull/getOrThrow return a real object.
    let boxValue = status == .success ? kk_box_unit(0) : 0
    return runtimeChannelResultBox(status: status, value: boxValue, cause: cause)
}

/// KSP-1572: `ReceiveChannel.receiveCatching()` bridge. Performs the same
/// blocking receive as `kk_channel_receive`, but returns the outcome as a
/// `ChannelResult` box so closed and cancelled outcomes are observable to
/// Kotlin source.
@_cdecl("__kk_channel_receive_catching")
public func __kk_channel_receive_catching(_ handle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_channel_receive_catching received invalid channel handle")
    }
    let channel = Unmanaged<RuntimeChannelHandle>.fromOpaque(ptr).takeUnretainedValue()
    var value = 0
    let status = channel.receive(continuation: 0, outValue: &value)
    let cause = channelResultReceiveCause(channel: channel, status: status)
    return runtimeChannelResultBox(status: status, value: value, cause: cause)
}

/// Returns the `ChannelOperationStatus` stored in a `ChannelResult` box.
@_cdecl("__kk_channel_result_status")
public func __kk_channel_result_status(_ boxRaw: Int) -> Int {
    guard let box = channelResultBoxFromRaw(boxRaw) else {
        return kChannelResultFailed
    }
    return box.status
}

/// Returns the element stored in a `ChannelResult` box, or the null sentinel
/// when the result is not a success.
@_cdecl("__kk_channel_result_value_or_null")
public func __kk_channel_result_value_or_null(_ boxRaw: Int) -> Int {
    guard let box = channelResultBoxFromRaw(boxRaw), box.status == kChannelResultSuccess else {
        return runtimeNullSentinelInt
    }
    return box.value
}

/// Returns the close-cause `Throwable` stored in a `ChannelResult` box, or the
/// null sentinel when the box carries none (non-closed results and
/// `ChannelResult.closed(null)`).
@_cdecl("__kk_channel_result_cause")
public func __kk_channel_result_cause(_ boxRaw: Int) -> Int {
    guard let box = channelResultBoxFromRaw(boxRaw), box.cause != 0 else {
        return runtimeNullSentinelInt
    }
    return box.cause
}

/// `ChannelResult` companion maker (`success` / `failure` / `closed`). The
/// cause is stored verbatim — the send/receive exception substitution is a
/// property of the channel operations, not the companion factories.
@_cdecl("__kk_channel_result_create")
public func __kk_channel_result_create(_ status: Int, _ value: Int, _ cause: Int) -> Int {
    let opStatus = ChannelOperationStatus(rawValue: status) ?? .failed
    let normalizedCause = cause == runtimeNullSentinelInt ? 0 : cause
    return runtimeChannelResultBox(status: opStatus, value: value, cause: normalizedCause)
}

/// `ChannelResult.getOrThrow()`: returns the element on success; on a closed
/// result throws the stored close cause; on a cause-less closed result or a
/// generic failure throws the "failed channel result" `IllegalStateException`
/// kotlinx reports (`"... result: Closed(null)"` / `"... result: Failed"`).
@_cdecl("__kk_channel_result_get_or_throw")
public func __kk_channel_result_get_or_throw(
    _ boxRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let box = channelResultBoxFromRaw(boxRaw) else {
        outThrown?.pointee = runtimeAllocateIllegalStateException(message: "ChannelResult is null")
        return 0
    }
    switch box.status {
    case kChannelResultSuccess:
        return box.value
    case kChannelResultClosed, kChannelResultCancelled:
        if box.cause != 0 {
            outThrown?.pointee = box.cause
        } else {
            outThrown?.pointee = runtimeAllocateIllegalStateException(
                message: "Trying to call 'getOrThrow' on a failed channel result: Closed(null)"
            )
        }
        return 0
    default:
        outThrown?.pointee = runtimeAllocateIllegalStateException(
            message: "Trying to call 'getOrThrow' on a failed channel result: Failed"
        )
        return 0
    }
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
