import Dispatch
import Foundation

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

/// `Channel.Factory` capacity sentinels (kotlinx.coroutines `Channel.kt`).
let kChannelCapacityConflated: Int = -1
let kChannelCapacityBuffered: Int = -2
let kChannelCapacityOptionalChannel: Int = -3
/// Upstream `kotlinx.coroutines.channels.defaultBufferSize` system-property
/// default, used for `Channel(Channel.BUFFERED)`.
let kChannelDefaultBufferCapacity: Int = 64

enum ChannelBufferOverflow {
    case suspend
    case dropOldest
    case dropLatest
}

private struct RuntimeChannelBuffer {
    private var queue = RuntimeFIFOQueue<RuntimeGCRootedValue>()

    var count: Int { queue.count }
    var isEmpty: Bool { queue.isEmpty }

    mutating func enqueue(_ value: Int) {
        queue.enqueue(RuntimeGCRootedValue(value))
    }

    mutating func dequeue(discard: Bool = false) -> Int? {
        guard let value = queue.dequeue() else { return nil }
        return discard ? value.value : value.rootedValue()
    }

    mutating func drain() {
        while queue.dequeue() != nil {}
    }
}

private struct RuntimeChannelCloseHandler {
    let fnPtr: Int
    let closureRaw: Int
    private let functionRoot: RuntimeGCRootedValue
    private let captureRoot: RuntimeGCRootedValue

    init(fnPtr: Int, closureRaw: Int) {
        self.fnPtr = fnPtr
        self.closureRaw = closureRaw
        functionRoot = RuntimeGCRootedValue(fnPtr)
        captureRoot = RuntimeGCRootedValue(closureRaw)
    }
}

/// Mutable box for a suspended sender so receivers can mark delivery before
/// resuming the continuation.  Using a class (reference type) ensures the
/// `delivered` flag set under the channel lock is visible to the sender
/// after it re-acquires the lock post-wakeup.
final class SuspendedSender: @unchecked Sendable {
    let semaphore: DispatchSemaphore // CORO-004: Keep for backward compatibility during migration
    let continuation: Int
    private let rootedPayload: RuntimeGCRootedValue
    var value: Int { rootedPayload.value }

    func rootedValue() -> Int { rootedPayload.rootedValue() }
    var resumeClosure: (@Sendable () -> Void)?

    /// Set to `true` (under the channel lock) when the sender's value is
    /// delivered to a receiver. The sender checks this after waking to distinguish a
    /// successful delivery from a close-induced wakeup.
    var delivered: Bool = false
    /// Set to `true` (under the channel lock) when the sender is woken due to
    /// coroutine cancellation. Distinct from close-induced wakeup.
    var cancelledWakeup: Bool = false
    /// Set when the sender suspended through its coroutine continuation
    /// instead of blocking the calling thread (UNDISPATCHED parents).
    var waiter: RuntimeCancellableContinuation?

    init(semaphore: DispatchSemaphore, continuation: Int, value: Int) {
        self.semaphore = semaphore
        self.continuation = continuation
        self.rootedPayload = RuntimeGCRootedValue(value)
    }
}

/// Mutable box for a suspended receiver so senders / close can mark the
/// wakeup reason before resuming the continuation. Mirrors `SuspendedSender`.
final class SuspendedReceiver: @unchecked Sendable {
    let semaphore: DispatchSemaphore // CORO-004: Keep for backward compatibility during migration
    let continuation: Int
    var resumeClosure: (@Sendable () -> Void)?
    /// The value deposited by a sender. `nil` means woken by close or cancel.
    private var rootedResultValue: RuntimeGCRootedValue?
    var result: Int? {
        get { rootedResultValue?.value }
        set { rootedResultValue = newValue.map(RuntimeGCRootedValue.init) }
    }
    func rootedResult() -> Int? { rootedResultValue?.rootedValue() }
    var cancelledWakeup: Bool = false

    init(semaphore: DispatchSemaphore, continuation: Int) {
        self.semaphore = semaphore
        self.continuation = continuation
    }
}

/// Entries in `senderQueue`/`receiverQueue`: real suspended operations and
/// select-clause offers (`onSend`/`onReceive` waiters) share one FIFO each so
/// a channel rendezvous resolves in registration order and a select offer can
/// be claimed — through `runtimeSelectClaimLock` — instead of polled.
enum ChannelSenderWaiter {
    case suspended(SuspendedSender)
    case select(RuntimeSelectWaiter)

    var suspended: SuspendedSender? {
        if case .suspended(let sender) = self { return sender }
        return nil
    }

    var selectWaiter: RuntimeSelectWaiter? {
        if case .select(let waiter) = self { return waiter }
        return nil
    }
}

enum ChannelReceiverWaiter {
    case suspended(SuspendedReceiver)
    case select(RuntimeSelectWaiter)

    var suspended: SuspendedReceiver? {
        if case .suspended(let receiver) = self { return receiver }
        return nil
    }

    var selectWaiter: RuntimeSelectWaiter? {
        if case .select(let waiter) = self { return waiter }
        return nil
    }
}

/// Runtime representation of `kotlinx.coroutines.channels.ClosedReceiveChannelException`
/// (KUU-1404). Distinct `RuntimeThrowableBox` subclass so `kk_op_is` / catch-clause
/// dispatch can discriminate it via `exceptionHierarchyFQNames`. On the JVM this
/// class extends `java.util.NoSuchElementException` (kotlinx-coroutines 1.10.2).
final class RuntimeClosedReceiveChannelExceptionBox: RuntimeThrowableBox {
    override var exceptionFQName: String {
        "kotlinx.coroutines.channels.ClosedReceiveChannelException"
    }

    override var exceptionHierarchyFQNames: [String] {
        [
            "kotlinx.coroutines.channels.ClosedReceiveChannelException",
            "kotlinx.coroutines.ClosedReceiveChannelException",
            "ClosedReceiveChannelException",
            "kotlin.NoSuchElementException",
            "kotlin.RuntimeException",
            "kotlin.Exception",
            "kotlin.Throwable",
        ]
    }

    override var renderedMessage: String {
        runtimeRenderedExceptionMessage("ClosedReceiveChannelException", message)
    }
}

final class RuntimeClosedSendChannelExceptionBox: RuntimeThrowableBox {
    override var exceptionFQName: String {
        "kotlinx.coroutines.channels.ClosedSendChannelException"
    }

    override var exceptionHierarchyFQNames: [String] {
        [
            "kotlinx.coroutines.channels.ClosedSendChannelException",
            "kotlinx.coroutines.ClosedSendChannelException",
            "ClosedSendChannelException",
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

func runtimeAllocateClosedReceiveChannelException(message: String?, cause: Int = 0, messageRaw: Int = 0) -> Int {
    runtimeRegisterThrowable(RuntimeClosedReceiveChannelExceptionBox(message: message, cause: cause, messageRaw: messageRaw))
}

func runtimeAllocateClosedSendChannelException(message: String? = "Channel was closed", cause: Int = 0, messageRaw: Int = 0) -> Int {
    runtimeRegisterThrowable(RuntimeClosedSendChannelExceptionBox(message: message, cause: cause, messageRaw: messageRaw))
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
    private var buffer = RuntimeChannelBuffer()
    let capacity: Int
    private(set) var closed = false
    /// `true` when the channel was closed via `cancel(cause:)` (buffer
    /// discarded) rather than `close(cause:)` (buffer drains normally).
    private(set) var cancelled = false
    /// The `Throwable` handle passed to `close(cause:)` / `cancel(cause:)`,
    /// or `0` when the channel is still open or was closed without a cause.
    /// Retained so result-returning operations (`trySend` and friends) can
    /// report the exact close cause via `ChannelResult.exceptionOrNull()`.
    private(set) var closeCause: Int = 0 {
        didSet { closeCauseRoot = closeCause == 0 ? nil : RuntimeGCRootedValue(closeCause) }
    }
    private var closeCauseRoot: RuntimeGCRootedValue?
    /// Raw handle of the `CancellationException` (or the cause passed to
    /// `cancel(cause:)`) installed by `cancel()`, re-thrown from every
    /// subsequent `send`/`receive` (KUU-1404: JVM `cancel` stores the
    /// cancellation cause on the channel).
    private var cancelCauseRaw: Int = 0 {
        didSet { cancelCauseRoot = cancelCauseRaw == 0 ? nil : RuntimeGCRootedValue(cancelCauseRaw) }
    }
    private var cancelCauseRoot: RuntimeGCRootedValue?
    private let bufferOverflow: ChannelBufferOverflow

    // Receivers set `delivered = true` before signaling the semaphore so that
    // senders can distinguish successful delivery from a close-induced wakeup.
    // Select `onSend` clauses park a `RuntimeSelectWaiter` here: the queued
    // entry holds the element and is claimed atomically by a receiver instead
    // of suspending the selecting coroutine.
    private var senderQueue = RuntimeFIFOQueue<ChannelSenderWaiter>()

    // Senders deposit a value before signaling the semaphore.
    // Select `onReceive` clauses park a `RuntimeSelectWaiter` here for a later
    // send to claim atomically.
    private var receiverQueue = RuntimeFIFOQueue<ChannelReceiverWaiter>()
    private var awaitCloseRegistered = false
    private var awaitCloseSignal: DispatchSemaphore?
    /// KUU-1439: the CoroutineScope facet minted when this channel backs a
    /// `produce`/`channelFlow`/`callbackFlow` ProducerScope receiver. The
    /// runtime hands the raw channel handle to the producer block as `this`,
    /// so CoroutineScope member calls (`launch`/`async`/`cancel`/`isActive`)
    /// arrive at the kk_coroutine_scope_* bridges carrying a channel handle;
    /// `runtimeCoroutineScope(from:)` resolves it back through this link.
    private var producerScopeStorage: RuntimeCoroutineScope?
    /// `actor` shares `__kk_produce_launch` with `produce`; this marks the
    /// channel so its launch registers the ActorScope type that the block's
    /// receiver checkcast expects instead of ProducerScope.
    private var backsActorScopeStorage = false

    // KSP-1573: `invokeOnClose` handlers, as (fnPtr, closureRaw) function-value
    // pairs.  They run exactly once, on the first successful `close()`, with a
    // nil cause argument until `close(cause:)` lands.
    private var closeHandlers: [RuntimeChannelCloseHandler] = []

    init(capacity: Int, bufferOverflow: ChannelBufferOverflow = .suspend) {
        // KUU-1403: `Channel.Factory` negative capacity sentinels resolve here
        // so every construction path (`Channel(capacity)`, `Channel(capacity,
        // onBufferOverflow)`, and the produce/actor internals) shares upstream
        // `Channel(capacity, onBufferOverflow)` semantics:
        //   CONFLATED (-1)          -> one-slot channel keeping the latest value
        //   BUFFERED  (-2)          -> default 64-slot buffer, or one slot when
        //                            a non-suspend overflow policy was requested
        //   OPTIONAL_CHANNEL (-3)   -> internal "implementation default" marker:
        //                            upstream normalizes it to BUFFERED before a
        //                            channel is allocated (ChannelFlow.produceCapacity),
        //                            so it shares the BUFFERED resolution below.
        //                            The public bundled factories reject -3 with
        //                            IllegalArgumentException before reaching here.
        //   RENDEZVOUS (0) + DROP_* -> upstream's one-slot ArrayChannel
        //   other negatives         -> clamped to rendezvous (upstream throws
        //                            IllegalArgumentException; the bundled
        //                            Kotlin factories validate first)
        switch capacity {
        case kChannelCapacityConflated:
            self.capacity = 1
            self.bufferOverflow = .dropOldest
        case kChannelCapacityBuffered, kChannelCapacityOptionalChannel:
            self.capacity = bufferOverflow == .suspend ? kChannelDefaultBufferCapacity : 1
            self.bufferOverflow = bufferOverflow
        case 0 where bufferOverflow != .suspend:
            self.capacity = 1
            self.bufferOverflow = bufferOverflow
        default:
            self.capacity = max(0, capacity)
            self.bufferOverflow = bufferOverflow
        }
    }

    /// `continuation` is the opaque continuation handle for the calling coroutine.
    /// When non-zero, cancellation is checked before suspending and the sentinel
    /// is returned if the coroutine has been cancelled (matching Kotlin's behavior
    /// of throwing `CancellationException` from `send`).
    func send(_ value: Int, continuation: Int = 0) -> ChannelOperationStatus {
        send(value, continuation: continuation, suspendedResult: nil)
    }

    /// When `suspendedResult` is non-nil and `continuation` is non-zero, a send
    /// that has to wait parks the continuation instead of blocking the thread:
    /// `suspendedResult` receives `COROUTINE_SUSPENDED` and `.success` is
    /// returned; the eventual outcome is delivered by resuming the continuation.
    func send(
        _ value: Int,
        continuation: Int,
        suspendedResult: UnsafeMutablePointer<Int>?
    ) -> ChannelOperationStatus {
        lock.lock()

        if isCancelled(continuation: continuation) {
            lock.unlock()
            return .cancelled
        }

        // Cancelled channel -- fail immediately with the cancellation
        // cause (JVM `send` throws `CancellationException` on a cancelled
        // channel). Checked before `closed` so callers can tell the two
        // terminal states apart.
        if cancelled {
            lock.unlock()
            return .cancelled
        }

        if closed {
            lock.unlock()
            return .closed
        }

        if let receiverEntry = withSelectClaimLock({ dequeueLiveReceiverUnlocked(deliverValue: value) }) {
            switch receiverEntry {
            case .suspended(let receiver):
                receiver.result = value
                lock.unlock()
                // Preserve rendezvous handoff ordering: let the sender resume and
                // return from `send` before the waiting receiver continues.
                resumeReceiverAsync(receiver)
            case .select:
                // The parked select offer was claimed atomically inside
                // dequeueLiveReceiver; no coroutine needs resuming.
                lock.unlock()
            }
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
                _ = buffer.dequeue(discard: true)
                buffer.enqueue(value)
                lock.unlock()
                return .success
            case .dropLatest:
                lock.unlock()
                return .success
            }
        }

        let senderSem = DispatchSemaphore(value: 0)
        let entry = SuspendedSender(semaphore: senderSem, continuation: continuation, value: value)

        if let suspendedResult, continuation != 0, runtimeContinuationState(from: continuation) != nil {
            // Park the caller's continuation; receive/close/cancel resume it.
            // Parent cancellation reaches the waiter through initParent().
            let waiter = RuntimeCancellableContinuation(delegate: continuation)
            suspendedResult.pointee = waiter.getResult(nil)
            entry.waiter = waiter
            senderQueue.enqueue(.suspended(entry))
            waiter.initParent()
            lock.unlock()
            return .success
        }

        senderQueue.enqueue(.suspended(entry))
        lock.unlock()

        let job = callingJob(continuation: continuation)
        let cancellationHandler = job?.addCompletionHandler(onCancelling: true) { [weak self, weak entry, weak job] _ in
            guard job?.cancellationSnapshot() == true, let self, let entry else { return }
            self.lock.lock()
            let removed = self.senderQueue.removeFirst { $0.suspended === entry }
            if removed { entry.cancelledWakeup = true }
            self.lock.unlock()
            if removed { self.resumeSender(entry) }
        }
        defer {
            if let cancellationHandler { job?.removeCompletionHandler(id: cancellationHandler) }
        }

        // Channel send is not yet lowered as a true suspend point, so the
        // runtime must block here until a receiver or close/cancellation wakes it.
        // BUG-041 interaction: flush undispatched launch{} work before blocking
        // so a sibling `launch { receive() }` queued on this thread can run.
        RuntimePendingLaunchQueue.flush()
        runtimeWaitDrainingEventLoop(senderSem)

        lock.lock()
        let wasDelivered = entry.delivered
        let wasCancelled = entry.cancelledWakeup
        lock.unlock()

        // Cancellation only aborts the send if delivery did not already
        // complete.  A channel cancel (`wasCancelled`) and a job cancel of the
        // calling coroutine both surface as `.cancelled` so the caller throws
        // `CancellationException` (KUU-1404); only a plain close() wakeup maps
        // to `.closed`.
        if wasCancelled || (!wasDelivered && isCancelled(continuation: continuation)) {
            return .cancelled
        }
        return wasDelivered ? .success : .closed
    }

    /// Attempt to send a value without suspending.  A full rendezvous or
    /// buffered channel reports `.failed`; a closed channel reports `.closed`.
    func trySend(_ value: Int) -> ChannelOperationStatus {
        lock.lock()

        if cancelled {
            lock.unlock()
            return .cancelled
        }

        if closed {
            lock.unlock()
            return .closed
        }

        if let receiverEntry = withSelectClaimLock({ dequeueLiveReceiverUnlocked(deliverValue: value) }) {
            switch receiverEntry {
            case .suspended(let receiver):
                receiver.result = value
                lock.unlock()
                resumeReceiverAsync(receiver)
            case .select:
                lock.unlock()
            }
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
                _ = buffer.dequeue(discard: true)
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

    /// `continuation` is the opaque continuation handle for the calling coroutine.
    /// When non-zero, cancellation is checked before suspending (Kotlin suspend
    /// semantics: `receive` throws `CancellationException` if cancelled).
    ///
    /// On `.success`, writes the received value to `outValue`.  Returns `.closed`
    /// when the channel is closed and fully drained, or `.cancelled` when the
    /// coroutine was cancelled.
    func receive(continuation: Int = 0, outValue: UnsafeMutablePointer<Int>) -> ChannelOperationStatus {
        lock.lock()

        if isCancelled(continuation: continuation) {
            lock.unlock()
            return .cancelled
        }

        // Cancelled channel -- fail immediately with the cancellation
        // cause, even if elements remain buffered (JVM `cancel` discards
        // pending elements).
        if cancelled {
            lock.unlock()
            return .cancelled
        }

        if let value = buffer.dequeue() {
            // If a sender is suspended (backpressure), wake the oldest one and
            // move its value into the buffer to maintain ordering.
            if let senderEntry = withSelectClaimLock({ dequeueLiveSenderUnlocked() }) {
                switch senderEntry {
                case .suspended(let sender):
                    buffer.enqueue(sender.value)
                    sender.delivered = true
                    lock.unlock()
                    resumeSender(sender)
                case .select(let waiter):
                    // The parked select offer was claimed inside
                    // dequeueLiveSender; its element refills the freed slot.
                    buffer.enqueue(waiter.value)
                    lock.unlock()
                }
            } else {
                lock.unlock()
            }
            outValue.pointee = value
            return .success
        }

        // Buffer is empty -- try to pair directly with a waiting sender
        // (rendezvous fast-path, also applies to buffered when a sender
        // arrived while the buffer was full and then got drained completely).
        if let senderEntry = withSelectClaimLock({ dequeueLiveSenderUnlocked() }) {
            switch senderEntry {
            case .suspended(let sender):
                let value = sender.rootedValue()
                sender.delivered = true
                lock.unlock()
                resumeSender(sender)
                outValue.pointee = value
            case .select(let waiter):
                let value = waiter.rootedValue()
                lock.unlock()
                outValue.pointee = value
            }
            return .success
        }

        if closed {
            lock.unlock()
            return .closed
        }

        let receiverEntry = SuspendedReceiver(semaphore: DispatchSemaphore(value: 0), continuation: continuation)

        receiverQueue.enqueue(.suspended(receiverEntry))
        lock.unlock()

        let job = callingJob(continuation: continuation)
        let cancellationHandler = job?.addCompletionHandler(onCancelling: true) { [weak self, weak receiverEntry, weak job] _ in
            guard job?.cancellationSnapshot() == true, let self, let receiverEntry else { return }
            self.lock.lock()
            let removed = self.receiverQueue.removeFirst { $0.suspended === receiverEntry }
            if removed { receiverEntry.cancelledWakeup = true }
            self.lock.unlock()
            if removed { self.resumeReceiver(receiverEntry) }
        }
        defer {
            if let cancellationHandler { job?.removeCompletionHandler(id: cancellationHandler) }
        }

        // Channel receive is not yet lowered as a true suspend point, so the
        // runtime must block here until a sender, close, or cancellation wakes it.
        // BUG-041 interaction: flush undispatched launch{} work before blocking
        // so a sibling `launch { send(x) }` queued on this thread can run.
        // Without this, channel_basic-style rendezvous deadlocks (run exit 124).
        // On a runBlocking event loop the flush only *queues* that sibling, so
        // the wait below has to keep draining the queue rather than park.
        RuntimePendingLaunchQueue.flush()
        runtimeWaitDrainingEventLoop(receiverEntry.semaphore)

        lock.lock()
        let wasCancelled = receiverEntry.cancelledWakeup
        let value = receiverEntry.rootedResult()
        lock.unlock()

        // Cancellation only aborts the receive if no sender delivered a value.
        // Both channel cancel and calling-coroutine job cancel surface as
        // `.cancelled` -> `CancellationException` (KUU-1404); a plain close()
        // wakeup maps to `.closed`.
        if wasCancelled || (value == nil && isCancelled(continuation: continuation)) {
            return .cancelled
        }
        if let value {
            outValue.pointee = value
            return .success
        }
        // Woken by close() with no value -- channel is done.
        return .closed
    }

    /// Mirrors the non-suspending prefix of `receive(continuation:outValue:)`:
    /// drain the buffer, then pair with the oldest waiting sender. An empty
    /// but open channel reports `.failed`; a closed and fully drained channel
    /// reports `.closed`. Every state transition happens under the channel
    /// lock, so the result is a consistent atomic snapshot of the channel.
    func tryReceive(outValue: UnsafeMutablePointer<Int>) -> ChannelOperationStatus {
        lock.lock()

        // Take from the buffer, waking the oldest suspended sender
        // so its value keeps FIFO ordering behind the drained element.
        if let value = buffer.dequeue() {
            if let senderEntry = withSelectClaimLock({ dequeueLiveSenderUnlocked() }) {
                switch senderEntry {
                case .suspended(let sender):
                    buffer.enqueue(sender.value)
                    sender.delivered = true
                    lock.unlock()
                    resumeSender(sender)
                case .select(let waiter):
                    buffer.enqueue(waiter.value)
                    lock.unlock()
                }
            } else {
                lock.unlock()
            }
            outValue.pointee = value
            return .success
        }

        if let senderEntry = withSelectClaimLock({ dequeueLiveSenderUnlocked() }) {
            switch senderEntry {
            case .suspended(let sender):
                let value = sender.rootedValue()
                sender.delivered = true
                lock.unlock()
                resumeSender(sender)
                outValue.pointee = value
            case .select(let waiter):
                let value = waiter.rootedValue()
                lock.unlock()
                outValue.pointee = value
            }
            return .success
        }

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

    /// Bind the producer scope facet (see `producerScopeStorage`). Called once
    /// at producer launch, before the block observes the channel as `this`.
    func bindProducerScope(_ scope: RuntimeCoroutineScope) {
        lock.lock()
        producerScopeStorage = scope
        lock.unlock()
    }

    var backsActorScope: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return backsActorScopeStorage
        }
        set {
            lock.lock()
            backsActorScopeStorage = newValue
            lock.unlock()
        }
    }

    var producerScope: RuntimeCoroutineScope? {
        lock.lock()
        defer { lock.unlock() }
        return producerScopeStorage
    }

    func registerAwaitClose(_ signal: DispatchSemaphore) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !awaitCloseRegistered else { return false }
        awaitCloseRegistered = true
        if closed {
            signal.signal()
        } else {
            awaitCloseSignal = signal
        }
        return true
    }

    func removeAwaitCloseSignal() {
        lock.lock()
        awaitCloseSignal = nil
        lock.unlock()
    }

    var hasAwaitCloseWaiter: Bool {
        lock.lock()
        defer { lock.unlock() }
        return awaitCloseSignal != nil
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
        let closeSignal = awaitCloseSignal
        awaitCloseSignal = nil
        let pendingCloseHandlers = closeHandlers
        closeHandlers.removeAll()
        lock.unlock()

        closeSignal?.signal()

        // Wake all suspended senders -- they will see `closed == true` and
        // return the closed sentinel.
        for entry in pendingSenders {
            switch entry {
            case .suspended(let sender):
                resumeSender(sender)
            case .select(let waiter):
                // Closing resolves a parked select offer: the clause
                // materializes the closed outcome on its next poll.
                _ = claimSelectWaiter(waiter, status: .closed, cause: closeCause)
            }
        }
        // Wake all suspended receivers -- they will find no result deposited
        // and return the closed sentinel.
        for entry in pendingReceivers {
            switch entry {
            case .suspended(let receiver):
                resumeReceiver(receiver)
            case .select(let waiter):
                _ = claimSelectWaiter(waiter, status: .closed, cause: closeCause)
            }
        }
        for handler in pendingCloseHandlers {
            guard handler.fnPtr != 0 else { continue }
            // `invokeOnClose` receives the close cause (null when none),
            // matching kotlinx's `invokeOnClose(handler: (Throwable?) -> Unit)`.
            withExtendedLifetime(handler) {
                _ = runtimeInvokeCollectionLambda1MaybeWrapped(
                    fnPtr: handler.fnPtr,
                    closureRaw: handler.closureRaw,
                    value: closeCause != 0 ? closeCause : runtimeNullSentinelInt,
                    outThrown: nil
                )
            }
        }
        return true
    }

    /// `ReceiveChannel.cancel(cause:)`: like `close`, but the buffered
    /// elements are discarded immediately instead of draining first
    /// (upstream `cancelInternal`). Suspended waiters wake with `.cancelled`.
    /// KUU-1404: the stored cancellation cause is re-thrown from every
    /// subsequent `send`/`receive` (JVM `cancel` installs the cause on the
    /// channel).
    ///
    /// Returns `true` if this call actually cancelled the channel, `false` if
    /// it was already closed or cancelled.
    @discardableResult
    func cancel(cause: Int = 0) -> Bool {
        lock.lock()
        if closed {
            // cancel also discards elements after close. The first close cause
            // and its waiter/handler publication remain authoritative.
            buffer.drain()
            lock.unlock()
            return false
        }
        closed = true
        cancelled = true
        closeCause = cause == runtimeNullSentinelInt ? 0 : cause
        if cancelCauseRaw == 0 {
            cancelCauseRaw = closeCause != 0
                ? closeCause
                : runtimeAllocateCancellationException(message: "Channel was cancelled")
        }
        buffer.drain()
        let pendingSenders = senderQueue.drain()
        let pendingReceivers = receiverQueue.drain()
        let closeSignal = awaitCloseSignal
        awaitCloseSignal = nil
        let pendingCloseHandlers = closeHandlers
        closeHandlers.removeAll()
        lock.unlock()

        closeSignal?.signal()

        for entry in pendingSenders {
            switch entry {
            case .suspended(let sender):
                sender.cancelledWakeup = true
                resumeSender(sender)
            case .select(let waiter):
                _ = claimSelectWaiter(waiter, status: .cancelled, cause: closeCause)
            }
        }
        for entry in pendingReceivers {
            switch entry {
            case .suspended(let receiver):
                receiver.cancelledWakeup = true
                resumeReceiver(receiver)
            case .select(let waiter):
                _ = claimSelectWaiter(waiter, status: .cancelled, cause: closeCause)
            }
        }
        for handler in pendingCloseHandlers {
            guard handler.fnPtr != 0 else { continue }
            withExtendedLifetime(handler) {
                _ = runtimeInvokeCollectionLambda1MaybeWrapped(
                    fnPtr: handler.fnPtr,
                    closureRaw: handler.closureRaw,
                    value: closeCause != 0 ? closeCause : runtimeNullSentinelInt,
                    outThrown: nil
                )
            }
        }
        return true
    }

    /// The throwable that a terminal `.cancelled` status converts into at the
    /// C ABI boundary: the stored cancellation cause after `cancel()`, or a
    /// fresh `CancellationException` when the calling coroutine itself was
    /// cancelled.
    func cancellationThrowable() -> Int {
        lock.lock()
        let existing = cancelCauseRoot?.rootedValue() ?? cancelCauseRaw
        lock.unlock()
        if existing != 0 {
            return existing
        }
        return runtimeAllocateCancellationException(message: "Channel was cancelled")
    }

    /// Returns `true` when the handler was queued and will run on the first
    /// close.  When the channel is already closed the handler is invoked
    /// inline with the retained close cause, matching kotlinx.coroutines
    /// semantics, and `false` is returned.
    @discardableResult
    func addCloseHandler(fnPtr: Int, closureRaw: Int) -> Bool {
        lock.lock()
        if closed {
            let retainedCause = closeCauseRoot?.rootedValue() ?? closeCause
            let handler = RuntimeChannelCloseHandler(fnPtr: fnPtr, closureRaw: closureRaw)
            lock.unlock()
            guard fnPtr != 0 else { return false }
            withExtendedLifetime(handler) {
                _ = runtimeInvokeCollectionLambda1MaybeWrapped(
                    fnPtr: fnPtr,
                    closureRaw: closureRaw,
                    value: retainedCause != 0 ? retainedCause : runtimeNullSentinelInt,
                    outThrown: nil
                )
            }
            return false
        }
        closeHandlers.append(RuntimeChannelCloseHandler(fnPtr: fnPtr, closureRaw: closureRaw))
        lock.unlock()
        return true
    }

    /// Thread-safe snapshot of the retained close cause (0 when none).
    func closeCauseSnapshot() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return closeCauseRoot?.rootedValue() ?? closeCause
    }

    /// `true` when no element is currently receivable: the buffer is drained
    /// and no suspended sender is waiting to hand off a value. A closed
    /// channel is never `isEmpty` upstream (its receive side is done).
    func isEmptySnapshot() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return !closed && buffer.isEmpty && senderQueue.isEmpty
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

        for entry in pendingSenders {
            switch entry {
            case .suspended(let sender):
                sender.cancelledWakeup = true
                resumeSender(sender)
            case .select(let waiter):
                // Select waiters are offers, not suspended coroutines: drop
                // the registration so a later poll re-parks it instead of
                // completing a clause with a status it did not earn.
                evictSelectWaiter(waiter)
            }
        }
        for entry in pendingReceivers {
            switch entry {
            case .suspended(let receiver):
                receiver.cancelledWakeup = true
                resumeReceiver(receiver)
            case .select(let waiter):
                evictSelectWaiter(waiter)
            }
        }
    }

    /// Runtime tests use this snapshot to synchronize with actual suspension
    /// instead of assuming a background queue has progressed after a fixed delay.
    /// Select-clause waiters are parked offers, not suspended coroutines, so
    /// they are not included in either count.
    func suspendedWaiterCountsSnapshot() -> (senders: Int, receivers: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (
            senderQueue.count { $0.suspended != nil },
            receiverQueue.count { $0.suspended != nil }
        )
    }

    /// Test-facing snapshot of parked select-clause offers — the counterpart
    /// of `suspendedWaiterCountsSnapshot` for `RuntimeSelectWaiter` entries.
    func selectWaiterCountsSnapshot() -> (senders: Int, receivers: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (
            senderQueue.count { $0.selectWaiter != nil },
            receiverQueue.count { $0.selectWaiter != nil }
        )
    }


    /// Runs `body` while holding `runtimeSelectClaimLock`, nested inside the
    /// channel lock — channel → claim is the established order. Every
    /// dequeue/claim helper below is the `Unlocked` variant so real channel
    /// operations take the claim lock for exactly the claim section while
    /// select polls (which already hold it) call them directly.
    private func withSelectClaimLock<T>(_ body: () -> T) -> T {
        runtimeSelectClaimLock.lock()
        defer { runtimeSelectClaimLock.unlock() }
        return body()
    }

    /// Pops the oldest live sender. Suspended entries whose continuation was
    /// already cancelled are dead and skipped. A parked select offer is live
    /// only while its select is undecided: claiming it goes through
    /// `runtimeSelectClaimLock` — the first claimant wins the select — and
    /// deposits `claimStatus`/`claimCause` so the owning clause materializes
    /// the outcome on its next poll.
    /// Caller holds `lock` AND `runtimeSelectClaimLock`.
    private func dequeueLiveSenderUnlocked(
        claimStatus: ChannelOperationStatus = .success,
        claimCause: Int = 0
    ) -> ChannelSenderWaiter? {
        while let entry = senderQueue.dequeue() {
            switch entry {
            case .suspended(let sender):
                if sender.waiter?.stateValue == 2 { continue }
                return entry
            case .select(let waiter):
                if claimSelectWaiterUnlocked(waiter, status: claimStatus, cause: claimCause) {
                    return entry
                }
            }
        }
        return nil
    }

    /// Pops the oldest live receiver — a suspended entry directly, or a
    /// select receive-offer claimed through the select's atomic `trySelect`
    /// with `deliverValue` deposited for its clause.
    /// Caller holds `lock` AND `runtimeSelectClaimLock`.
    private func dequeueLiveReceiverUnlocked(deliverValue: Int) -> ChannelReceiverWaiter? {
        while let entry = receiverQueue.dequeue() {
            switch entry {
            case .suspended:
                return entry
            case .select(let waiter):
                if claimSelectWaiterUnlocked(waiter, status: .success, value: deliverValue) {
                    return entry
                }
            }
        }
        return nil
    }

    /// Claims a parked select waiter through the owning select's atomic
    /// `trySelect`: only one clause of that select can win, so the same
    /// channel rendezvous cannot feed two clauses. The entry is already
    /// dequeued, so the clause is no longer registered either way.
    /// Caller holds `runtimeSelectClaimLock` (and `lock` when the waiter was
    /// just dequeued). Returns `true` when the waiter's clause won its
    /// selection.
    private func claimSelectWaiterUnlocked(
        _ waiter: RuntimeSelectWaiter,
        status: ChannelOperationStatus,
        value: Int = 0,
        cause: Int = 0
    ) -> Bool {
        guard let clause = waiter.clause, let select = clause.select else {
            return false
        }
        clause.waiterRegistered = false
        guard select.trySelectUnlocked(clause) else { return false }
        clause.delivered = true
        clause.deliveredStatus = status.rawValue
        clause.deliveredValue = value
        clause.deliveredCause = cause
        return true
    }

    /// Locking wrapper for claim paths that run after the channel lock was
    /// released (close/cancel drains).
    private func claimSelectWaiter(
        _ waiter: RuntimeSelectWaiter,
        status: ChannelOperationStatus,
        value: Int = 0,
        cause: Int = 0
    ) -> Bool {
        withSelectClaimLock {
            claimSelectWaiterUnlocked(waiter, status: status, value: value, cause: cause)
        }
    }

    /// Drops a select waiter's registration without resolving it — the owning
    /// select's next poll re-parks the offer. Used by `cancelAllWaiters`,
    /// which only targets real suspended coroutines.
    private func evictSelectWaiter(_ waiter: RuntimeSelectWaiter) {
        runtimeSelectClaimLock.lock()
        waiter.clause?.waiterRegistered = false
        runtimeSelectClaimLock.unlock()
    }

    /// Removes a still-queued select waiter (finish/cancellation cleanup).
    /// Already-claimed or dequeued entries are absent from both queues, so
    /// the removal is a harmless no-op. Takes `lock` then the claim lock.
    func removeSelectWaiter(_ waiter: RuntimeSelectWaiter) {
        lock.lock()
        _ = senderQueue.removeFirst { $0.selectWaiter === waiter }
        _ = receiverQueue.removeFirst { $0.selectWaiter === waiter }
        lock.unlock()
        runtimeSelectClaimLock.lock()
        waiter.clause?.waiterRegistered = false
        runtimeSelectClaimLock.unlock()
    }

    /// `select { onReceive }` poll. Mirrors `tryReceive` — buffered elements
    /// and waiting senders are consumed the same way — but the outcome is
    /// committed through the clause's atomic selection: a rendezvous taken by
    /// this poll cannot feed another clause, and when nothing is receivable a
    /// receive waiter is parked for a later `send`/`trySend`/peer select to
    /// claim. Returns a `ChannelResult` box like `__kk_channel_try_receive`.
    /// The lock order is channel `lock` → `runtimeSelectClaimLock`.
    func selectPollReceive(clause: RuntimeSelectClause) -> Int {
        kk_gc_shadow_push()
        let result = selectPollReceiveInFrame(clause: clause)
        runtimePopNativeGCShadowFrame(result, 0)
        return result
    }

    private func selectPollReceiveInFrame(clause: RuntimeSelectClause) -> Int {
        lock.lock()
        runtimeSelectClaimLock.lock()
        var resume: SuspendedSender?
        defer {
            runtimeSelectClaimLock.unlock()
            lock.unlock()
            if let resume {
                resumeSender(resume)
            }
        }
        guard let select = clause.select else {
            return runtimeSelectPollResultBox(status: kChannelResultFailed)
        }
        // A committed outcome materializes verbatim — whether this poll made
        // it or an external claimant delivered it while the clause waited.
        if clause.delivered {
            return runtimeSelectPollResultBox(
                status: clause.deliveredStatus,
                value: clause.deliveredValue,
                cause: clause.deliveredCause
            )
        }
        if select.isDecidedUnlocked {
            return runtimeSelectPollResultBox(status: kSelectResultDecided)
        }
        if let buffered = buffer.dequeue() {
            // Refill the freed slot from the oldest live sender (same as
            // `tryReceive`): suspended senders keep FIFO order; a select
            // offer is already claimed inside `dequeueLiveSenderUnlocked`.
            if let senderEntry = dequeueLiveSenderUnlocked() {
                switch senderEntry {
                case .suspended(let sender):
                    buffer.enqueue(sender.value)
                    sender.delivered = true
                    resume = sender
                case .select(let waiter):
                    buffer.enqueue(waiter.value)
                }
            }
            _ = select.trySelectUnlocked(clause)
            clause.delivered = true
            clause.deliveredStatus = kChannelResultSuccess
            clause.deliveredValue = buffered
            return runtimeSelectPollResultBox(status: kChannelResultSuccess, value: buffered)
        }
        while let senderEntry = dequeueLiveSenderUnlocked() {
            switch senderEntry {
            case .suspended(let sender):
                sender.delivered = true
                resume = sender
                _ = select.trySelectUnlocked(clause)
                clause.delivered = true
                clause.deliveredStatus = kChannelResultSuccess
                clause.deliveredValue = sender.value
                return runtimeSelectPollResultBox(status: kChannelResultSuccess, value: sender.value)
            case .select(let waiter):
                // The peer send-offer was already claimed and committed
                // inside `dequeueLiveSender`; this clause still has to win
                // its own select to consume the element. A lost claim means
                // a sibling clause (e.g. `select { ch.onSend; ch.onReceive }`
                // on this channel) owns the selection — the element stays
                // consumed, matching upstream's atomic-rendezvous rule.
                guard select.trySelectUnlocked(clause) else {
                    return runtimeSelectPollResultBox(status: kSelectResultDecided)
                }
                clause.delivered = true
                clause.deliveredStatus = kChannelResultSuccess
                clause.deliveredValue = waiter.value
                return runtimeSelectPollResultBox(status: kChannelResultSuccess, value: waiter.value)
            }
        }
        if closed {
            _ = select.trySelectUnlocked(clause)
            clause.delivered = true
            clause.deliveredStatus = kChannelResultClosed
            clause.deliveredCause = closeCause
            return runtimeSelectPollResultBox(status: kChannelResultClosed, cause: closeCause)
        }
        if !clause.waiterRegistered {
            let waiter = RuntimeSelectWaiter(clause: clause, value: 0)
            receiverQueue.enqueue(.select(waiter))
            clause.waiterRegistered = true
            select.pendingWaiters.append((channel: self, waiter: waiter))
        }
        return runtimeSelectPollResultBox(status: kChannelResultFailed)
    }

    /// `select { onSend }` poll. Mirrors `trySend` — receivers, buffer slots,
    /// and overflow policies resolve identically — but the outcome is
    /// committed through the clause's atomic selection, and when no delivery
    /// is possible a send waiter carrying the element is parked for a later
    /// `receive`/`tryReceive`/peer select to claim. Returns a bare
    /// `ChannelOperationStatus` (the send result carries no payload) plus the
    /// internal `kSelectResultDecided` marker.
    func selectPollSend(clause: RuntimeSelectClause, value: Int) -> Int {
        lock.lock()
        runtimeSelectClaimLock.lock()
        var resume: SuspendedReceiver?
        defer {
            runtimeSelectClaimLock.unlock()
            lock.unlock()
            if let resume {
                resumeReceiverAsync(resume)
            }
        }
        guard let select = clause.select else {
            return kChannelResultFailed
        }
        if clause.delivered {
            return clause.deliveredStatus
        }
        if select.isDecidedUnlocked {
            return kSelectResultDecided
        }
        if cancelled {
            _ = select.trySelectUnlocked(clause)
            clause.delivered = true
            clause.deliveredStatus = kChannelResultCancelled
            clause.deliveredCause = closeCause
            return kChannelResultCancelled
        }
        if closed {
            _ = select.trySelectUnlocked(clause)
            clause.delivered = true
            clause.deliveredStatus = kChannelResultClosed
            clause.deliveredCause = closeCause
            return kChannelResultClosed
        }
        if let receiverEntry = dequeueLiveReceiverUnlocked(deliverValue: value) {
            if case .suspended(let receiver) = receiverEntry {
                receiver.result = value
                resume = receiver
            }
            // A `.select` counterpart already claimed its offer inside
            // `dequeueLiveReceiver` and took the element. This clause still
            // has to win its own select to complete the send.
            guard select.trySelectUnlocked(clause) else {
                return kSelectResultDecided
            }
            clause.delivered = true
            clause.deliveredStatus = kChannelResultSuccess
            return kChannelResultSuccess
        }
        if capacity > 0, buffer.count < capacity {
            buffer.enqueue(value)
            _ = select.trySelectUnlocked(clause)
            clause.delivered = true
            clause.deliveredStatus = kChannelResultSuccess
            return kChannelResultSuccess
        }
        if capacity > 0, buffer.count >= capacity {
            switch bufferOverflow {
            case .suspend:
                break
            case .dropOldest:
                _ = buffer.dequeue(discard: true)
                buffer.enqueue(value)
                _ = select.trySelectUnlocked(clause)
                clause.delivered = true
                clause.deliveredStatus = kChannelResultSuccess
                return kChannelResultSuccess
            case .dropLatest:
                _ = select.trySelectUnlocked(clause)
                clause.delivered = true
                clause.deliveredStatus = kChannelResultSuccess
                return kChannelResultSuccess
            }
        }
        if !clause.waiterRegistered {
            let waiter = RuntimeSelectWaiter(clause: clause, value: value)
            senderQueue.enqueue(.select(waiter))
            clause.waiterRegistered = true
            select.pendingWaiters.append((channel: self, waiter: waiter))
        }
        return kChannelResultFailed
    }

    func resumeSender(_ sender: SuspendedSender) {
        if let waiter = sender.waiter {
            if sender.delivered {
                waiter.resume(value: kChannelResultSuccess) {}
            } else {
                let status: ChannelOperationStatus = sender.cancelledWakeup ? .cancelled : .closed
                waiter.resume(failure: channelStatusThrowable(
                    status, isReceive: false, channel: self, continuation: sender.continuation
                ))
            }
            return
        }
        if let resumeClosure = sender.resumeClosure {
            DispatchQueue.global().async {
                resumeClosure()
            }
        } else {
            sender.semaphore.signal()
        }
    }

    func resumeReceiver(_ receiver: SuspendedReceiver) {
        if let resumeClosure = receiver.resumeClosure {
            DispatchQueue.global().async {
                resumeClosure()
            }
        } else {
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

    /// Some channel bridges run before a call is lowered to a suspend point.
    /// They use the running coroutine's job when no continuation was supplied.
    private func callingJob(continuation: Int) -> RuntimeJobHandle? {
        if continuation != 0 { return runtimeContinuationState(from: continuation)?.jobHandle }
        return RuntimeJobHandle.current
    }

    private func isCancelled(continuation: Int) -> Bool {
        callingJob(continuation: continuation)?.cancellationSnapshot() ?? false
    }

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
/// 1 DROP_OLDEST, 2 DROP_LATEST).  Negative `Channel.Factory` sentinels keep
/// their kotlinx.coroutines meaning: -1 CONFLATED maps to a one-slot
/// DROP_OLDEST channel, while -2 BUFFERED and -3 OPTIONAL_CHANNEL both expand
/// to the default buffer size (or one slot with a non-suspend policy) —
/// upstream's internal `produceCapacity` maps OPTIONAL_CHANNEL to BUFFERED
/// before a channel is allocated — all resolved inside `RuntimeChannelHandle.init`.
@_cdecl("__kk_channel_create_with_policy")
public func __kk_channel_create_with_policy(_ capacity: Int, _ onBufferOverflow: Int) -> Int {
    let overflow: ChannelBufferOverflow
    switch onBufferOverflow {
    case 1:
        overflow = .dropOldest
    case 2:
        overflow = .dropLatest
    default:
        overflow = .suspend
    }
    let channel = RuntimeChannelHandle(capacity: capacity, bufferOverflow: overflow)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(channel).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

/// KSP-1573: `SendChannel.invokeOnClose(handler)` bridge. `handler` crosses
/// the boundary as an (fnPtr, closureRaw) pair, the same function-value
/// convention `__kk_job_invoke_on_completion` uses. The handler is invoked with
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

/// Channel send ABIs take `(handle, value)` where both sides are the same
/// `Int` slot width; compiled code can reach them with the receiver and the
/// element in either order, so the callee resolves the handle positionally.
func runtimeChannelHandleObject(from raw: Int) -> RuntimeChannelHandle? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
        return nil
    }
    let isRegistered = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isRegistered else {
        return nil
    }
    return tryCast(ptr, to: RuntimeChannelHandle.self)
}

private func runtimeIsRegisteredChannelHandle(_ raw: Int) -> Bool {
    runtimeChannelHandleObject(from: raw) != nil
}

/// KUU-3847: channel-family handles (`RuntimeChannelHandle`,
/// `RuntimeChannelIterator`) are raw runtime objects with no `kk_object_new`
/// nominal tag, so `kk_op_is`/`kk_op_cast` map them to the kotlinx class they
/// answer `is`/`as`/`as?` checks as — a channel handle claims
/// `kotlinx.coroutines.channels.Channel` (upstream declares
/// `interface Channel<E> : SendChannel<E>, ReceiveChannel<E>`), an iterator
/// handle claims `kotlinx.coroutines.channels.ChannelIterator`.
/// Mirrors `runtimeJobFamilyNominalTypeID` (KUU-1386).
func runtimeChannelFamilyNominalTypeID(rawValue: Int) -> Int64? {
    if runtimeChannelHandleObject(from: rawValue) != nil {
        return runtimeStableNominalTypeID(fqName: "kotlinx.coroutines.channels.Channel")
    }
    if resolveRuntimeHandle(rawValue, as: RuntimeChannelIterator.self) != nil {
        return runtimeStableNominalTypeID(fqName: "kotlinx.coroutines.channels.ChannelIterator")
    }
    return nil
}

/// Registers the `Channel -> SendChannel` / `Channel -> ReceiveChannel`
/// supertype edges once (mirrors `registerJobFamilyTypeEdgesOnce`, KUU-1386)
/// so `is`/`as` checks against the channel interfaces match kotlinx's
/// `interface Channel<E> : SendChannel<E>, ReceiveChannel<E>` declaration.
func registerChannelFamilyTypeEdgesOnce() {
    runtimeStorage.withMetadataLock { state in
        if state.channelFamilyTypeEdgesRegistered { return }
        func nominalID(_ fqName: String) -> Int64 { runtimeStableNominalTypeID(fqName: fqName) }
        let channel = nominalID("kotlinx.coroutines.channels.Channel")
        for parent in [
            nominalID("kotlinx.coroutines.channels.SendChannel"),
            nominalID("kotlinx.coroutines.channels.ReceiveChannel"),
        ] {
            state.typeParents[channel, default: []].insert(parent)
        }
        state.channelFamilyTypeEdgesRegistered = true
    }
}

/// KUU-1439: the CoroutineScope a channel handle stands in for. Only channels
/// bound to a `produce`/`channelFlow`/`callbackFlow` producer answer — a plain
/// `Channel()` keeps resolving to nil so the scope bridges keep rejecting it.
func runtimeProducerScopeForChannelHandle(_ raw: Int) -> RuntimeCoroutineScope? {
    runtimeChannelHandleObject(from: raw)?.producerScope
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

/// Maps a terminal channel operation status to the Kotlin throwable the
/// operation raises at the ABI boundary (KUU-1404):
///   - `.closed`  -> `ClosedReceiveChannelException` / `ClosedSendChannelException`
///   - `.cancelled` -> the channel's cancellation cause (a `CancellationException`)
/// Returns 0 for `.success`/`.failed` so `outThrown` is left cleared.
private func channelStatusThrowable(
    _ status: ChannelOperationStatus,
    isReceive: Bool,
    channel: RuntimeChannelHandle,
    continuation: Int
) -> Int {
    switch status {
    case .closed:
        let cause = channel.closeCauseSnapshot()
        if cause != 0, cause != runtimeNullSentinelInt { return cause }
        return isReceive
            ? runtimeAllocateClosedReceiveChannelException(message: "Channel was closed")
            : runtimeAllocateClosedSendChannelException(message: "Channel was closed")
    case .cancelled:
        let job = continuation == 0 ? RuntimeJobHandle.current
            : runtimeContinuationState(from: continuation)?.jobHandle
        if let job, job.cancellationSnapshot() {
            let cause = job.cancellationCauseSnapshot()
            if kk_is_cancellation_exception(cause) != 0 { return cause }
            return runtimeAllocateCancellationException(
                message: job.cancellationMessageSnapshot(forSuspensionPoint: true),
                cause: cause, cancellationJob: job
            )
        }
        return channel.cancellationThrowable()
    case .success, .failed:
        return 0
    }
}

@_cdecl("kk_channel_send")
public func kk_channel_send(
    _ handle: Int,
    _ value: Int,
    _ continuation: Int,
    _ outThrown: UnsafeMutablePointer<Int>? = nil
) -> Int {
    outThrown?.pointee = 0
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
    var suspendedResult = 0
    let status = channel.send(resolvedValue, continuation: continuation, suspendedResult: &suspendedResult)
    if suspendedResult != 0 { return suspendedResult }
    let thrown = channelStatusThrowable(status, isReceive: false, channel: channel, continuation: continuation)
    if thrown != 0 {
        outThrown?.pointee = thrown
    }
    return status.rawValue
}

@_cdecl("kk_channel_try_send")
public func kk_channel_try_send(_ handle: Int, _ value: Int) -> Int {
    let (channel, resolvedValue) = runtimeResolveChannelCall(handle, value)
    return channel.trySend(resolvedValue).rawValue
}

@_cdecl("kk_channel_receive")
public func kk_channel_receive(
    _ handle: Int,
    _ continuation: Int,
    _ outValue: UnsafeMutablePointer<Int>?,
    _ outThrown: UnsafeMutablePointer<Int>? = nil
) -> Int {
    outThrown?.pointee = 0
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_channel_receive received invalid channel handle")
    }
    let channel = Unmanaged<RuntimeChannelHandle>.fromOpaque(ptr).takeUnretainedValue()
    let status: ChannelOperationStatus
    if let outValue {
        status = channel.receive(continuation: continuation, outValue: outValue)
    } else {
        var scratch = 0
        status = channel.receive(continuation: continuation, outValue: &scratch)
    }
    let thrown = channelStatusThrowable(status, isReceive: true, channel: channel, continuation: continuation)
    if thrown != 0 {
        outThrown?.pointee = thrown
    }
    return status.rawValue
}

/// `Channel.cancel()` bridge (KUU-1404): cancels the channel, discards pending
/// elements, and wakes suspended senders/receivers so they report `.cancelled`.
/// Returns 1 if this call cancelled the channel, 0 if it was already closed.
@_cdecl("kk_channel_cancel")
public func kk_channel_cancel(_ handle: Int) -> Int {
    __kk_channel_cancel(handle, 0)
}

@_cdecl("kk_channel_close")
public func kk_channel_close(_ handle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_channel_close received invalid channel handle")
    }
    let channel = Unmanaged<RuntimeChannelHandle>.fromOpaque(ptr).takeUnretainedValue()
    return channel.close() ? 1 : 0
}

@_cdecl("__kk_channel_await_close")
public func __kk_channel_await_close(_ handle: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let job = RuntimeJobHandle.current, job.producerChannel == handle,
          let pointer = UnsafeMutableRawPointer(bitPattern: handle)
    else {
        outThrown?.pointee = runtimeAllocateIllegalStateException(
            message: "awaitClose() can only be invoked from the producer context"
        )
        return 0
    }
    let channel = Unmanaged<RuntimeChannelHandle>.fromOpaque(pointer).takeUnretainedValue()
    let signal = DispatchSemaphore(value: 0)
    guard channel.registerAwaitClose(signal) else {
        outThrown?.pointee = runtimeAllocateIllegalStateException(message: "Another close handler is already registered")
        return 0
    }
    let handlerID = job.addCompletionHandler(onCancelling: true) { _ in signal.signal() }
    defer {
        job.removeCompletionHandler(id: handlerID)
        channel.removeAwaitCloseSignal()
    }
    if job.cancellationSnapshot() { signal.signal() }
    RuntimePendingLaunchQueue.flush()
    runtimeWaitDrainingEventLoop(signal)
    if job.cancellationSnapshot() {
        outThrown?.pointee = runtimeAllocateCancellationException(
            message: job.cancellationMessageSnapshot(), cause: job.cancellationCauseSnapshot()
        )
    }
    return 0
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
public func kk_channel_close_cause(_ handle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_channel_close_cause received invalid channel handle")
    }
    let channel = Unmanaged<RuntimeChannelHandle>.fromOpaque(ptr).takeUnretainedValue()
    return channel.closeCauseSnapshot()
}

/// Close-with-cause bridge for Kotlin's `SendChannel.close(cause:)`.
/// `cause` is a `Throwable` object handle or 0.  Returns 1 the first time the
/// channel actually closes, 0 when it was already closed.
@_cdecl("__kk_channel_close_cause")
public func kk_channel_close_cause(_ handle: Int, _ cause: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_channel_close_cause received invalid channel handle")
    }
    let channel = Unmanaged<RuntimeChannelHandle>.fromOpaque(ptr).takeUnretainedValue()
    return channel.close(cause: cause) ? 1 : 0
}

/// `ReceiveChannel.cancel(cause:)` bridge: closes the channel and discards
/// buffered elements (upstream `cancelInternal`), unlike `close` which keeps
/// them receivable. Suspended waiters wake with `.cancelled`.
@_cdecl("__kk_channel_cancel")
public func __kk_channel_cancel(_ handle: Int, _ cause: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_channel_cancel received invalid channel handle")
    }
    let channel = Unmanaged<RuntimeChannelHandle>.fromOpaque(ptr).takeUnretainedValue()
    let didCancel = channel.cancel(cause: cause)
    // ProducerCoroutine.cancel cancels its Job even when the underlying
    // channel was already closed normally by the producer body.
    channel.producerScope?.cancel(
        message: "ProducerCoroutine was cancelled",
        cause: cause == runtimeNullSentinelInt ? 0 : cause
    )
    return didCancel ? 1 : 0
}

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
    private let valueRoot: RuntimeGCRootedValue
    /// Close cause `Throwable` handle carried by closed/cancelled results
    /// (upstream `Closed.closeCause`), 0 when none.
    private let causeRoot: RuntimeGCRootedValue
    var cause: Int { causeRoot.value }

    func rootedValue() -> Int { valueRoot.rootedValue() }
    func rootedCause() -> Int { causeRoot.rootedValue() }

    init(status: Int, value: Int, cause: Int) {
        self.status = status
        self.valueRoot = RuntimeGCRootedValue(value)
        self.causeRoot = RuntimeGCRootedValue(cause)
    }
}

private func channelResultBoxFromRaw(_ raw: Int) -> RuntimeChannelResultBox? {
    resolveRuntimeHandle(raw, as: RuntimeChannelResultBox.self)
}

private func runtimeChannelResultBox(status: ChannelOperationStatus, value: Int, cause: Int) -> Int {
    registerRuntimeObject(
        RuntimeChannelResultBox(status: status.rawValue, value: value, cause: cause),
        typeID: runtimeStableNominalTypeID(fqName: "kotlinx.coroutines.channels.ChannelResult")
    )
}

/// Result-box factory for select polls, which can also report the internal
/// `kSelectResultDecided` marker — a poll-only status outside
/// `ChannelOperationStatus` that never escapes to Kotlin `ChannelResult`
/// consumers beyond the select clause predicates.
func runtimeSelectPollResultBox(status: Int, value: Int = 0, cause: Int = 0) -> Int {
    let result = registerRuntimeObject(
        RuntimeChannelResultBox(status: status, value: value, cause: cause),
        typeID: runtimeStableNominalTypeID(fqName: "kotlinx.coroutines.channels.ChannelResult")
    )
    let threadID = runtimeGCCurrentThreadID()
    runtimeStorage.withGCLock { state in
        runtimeRecordShadowHandoffLocked(result, threadID: threadID, state: &state)
    }
    return result
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
    kk_gc_shadow_push()
    var result = 0
    defer { runtimePopNativeGCShadowFrame(result, 0) }
    let channel = Unmanaged<RuntimeChannelHandle>.fromOpaque(ptr).takeUnretainedValue()
    var value = 0
    let status = channel.tryReceive(outValue: &value)
    let cause = channelResultReceiveCause(channel: channel, status: status)
    result = runtimeChannelResultBox(status: status, value: value, cause: cause)
    return result
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

/// KSP-1574 `SendChannel.trySendBlocking(element)` bridge: blocking send that
/// reports its outcome as a `ChannelResult` box, with the same send-side
/// cause substitution as `trySend` (`closed(sendException)` upstream).
@_cdecl("__kk_channel_send_blocking")
public func __kk_channel_send_blocking(_ handle: Int, _ value: Int) -> Int {
    let (channel, resolvedValue) = runtimeResolveChannelCall(handle, value)
    let status = channel.send(resolvedValue, continuation: 0)
    let cause = channelResultSendCause(channel: channel, status: status)
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
    kk_gc_shadow_push()
    var result = 0
    defer { runtimePopNativeGCShadowFrame(result, 0) }
    let channel = Unmanaged<RuntimeChannelHandle>.fromOpaque(ptr).takeUnretainedValue()
    var value = 0
    let status = channel.receive(continuation: 0, outValue: &value)
    let cause = channelResultReceiveCause(channel: channel, status: status)
    result = runtimeChannelResultBox(status: status, value: value, cause: cause)
    return result
}

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
    return box.rootedValue()
}

/// Returns the close-cause `Throwable` stored in a `ChannelResult` box, or the
/// null sentinel when the box carries none (non-closed results and
/// `ChannelResult.closed(null)`).
@_cdecl("__kk_channel_result_cause")
public func __kk_channel_result_cause(_ boxRaw: Int) -> Int {
    guard let box = channelResultBoxFromRaw(boxRaw), box.cause != 0 else {
        return runtimeNullSentinelInt
    }
    return box.rootedCause()
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
/// generic failure throws the `IllegalStateException` kotlinx reports
/// (`"... channel closed without a cause"` / `"... non-closed channel"`).
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
        return box.rootedValue()
    case kChannelResultClosed, kChannelResultCancelled:
        if box.cause != 0 {
            outThrown?.pointee = box.rootedCause()
        } else {
            outThrown?.pointee = runtimeAllocateIllegalStateException(
                message: "Trying to call 'getOrThrow' on a channel closed without a cause"
            )
        }
        return 0
    default:
        outThrown?.pointee = runtimeAllocateIllegalStateException(
            message: "Trying to call 'getOrThrow' on a failed result of a non-closed channel"
        )
        return 0
    }
}

//
// A lightweight wrapper that allows channels to participate in the
// `__kk_range_iterator` / `__kk_range_hasNext` / `__kk_range_next` loop protocol.
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
    private var peekedValue: RuntimeGCRootedValue?
    var done: Bool = false
    private let lock = NSLock()

    init(channel: RuntimeChannelHandle) {
        self.channel = channel
    }

    /// Returns the channel status: `.success` with `peekedValue` set, or the
    /// terminal status (`closed` / `cancelled`) so callers can distinguish
    /// normal termination from cancellation (KUU-1404: JVM `hasNext` throws
    /// `CancellationException` on a cancelled channel instead of just
    /// returning `false`).
    func advance(continuation: Int = 0) -> ChannelOperationStatus {
        kk_gc_shadow_push()
        defer { runtimePopNativeGCShadowFrame(0, 0) }
        lock.lock()
        if done {
            lock.unlock()
            return .closed
        }
        lock.unlock()

        var value = 0
        let status = channel.receive(continuation: continuation, outValue: &value)
        lock.lock()
        defer { lock.unlock() }
        if status != .success {
            done = true
            peekedValue = nil
            return status
        }
        peekedValue = RuntimeGCRootedValue(value)
        return .success
    }

    func takeValue() -> Int {
        lock.lock()
        defer { lock.unlock() }
        let v = peekedValue?.rootedValue() ?? 0
        peekedValue = nil
        return v
    }
}

/// The iterator reference is registered in `runtimeStorage` so the GC can
/// track it.
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
///
/// KUU-1404: when the channel was *cancelled* (rather than closed), the
/// terminal status is surfaced through `outThrown` as a `CancellationException`
/// so `for`-loop `hasNext()` propagates it like the JVM instead of silently
/// ending iteration.
///
/// KUU-3847: a channel closed *with a cause* (`close(cause)`) likewise
/// surfaces the retained close cause once the buffer is drained — upstream
/// `ChannelIteratorImpl.hasNext` throws `closeCause` on `CHANNEL_END`, and
/// only a cause-less close ends iteration normally.
@_cdecl("kk_channel_iterator_hasNext")
public func kk_channel_iterator_hasNext(
    _ iterHandle: Int,
    _ outThrown: UnsafeMutablePointer<Int>? = nil
) -> Int {
    outThrown?.pointee = 0
    guard let ptr = UnsafeMutableRawPointer(bitPattern: iterHandle) else {
        return 0
    }
    let iter = Unmanaged<RuntimeChannelIterator>.fromOpaque(ptr).takeUnretainedValue()
    let status = iter.advance()
    switch status {
    case .cancelled:
        outThrown?.pointee = iter.channel.cancellationThrowable()
    case .closed:
        let cause = iter.channel.closeCauseSnapshot()
        if cause != 0, cause != runtimeNullSentinelInt {
            outThrown?.pointee = cause
        }
    default:
        break
    }
    return status == .success ? 1 : 0
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

//
// Bundled `kotlinx.coroutines.channels.ClosedReceiveChannelException` /
// `ClosedSendChannelException` declare these as `@KsSymbolName` constructor
// entry points so `throw ClosedReceiveChannelException("msg")` produces the
// correctly typed `RuntimeThrowableBox` (same pattern as
// `__kk_cancellation_exception_new`).

@_cdecl("__kk_closed_receive_channel_exception_new_message")
public func kk_closed_receive_channel_exception_new_message(_ messageRaw: Int) -> Int {
    let message = (messageRaw == 0 || messageRaw == runtimeNullSentinelInt)
        ? nil
        : extractString(from: UnsafeMutableRawPointer(bitPattern: messageRaw))
    return runtimeAllocateClosedReceiveChannelException(
        message: message,
        messageRaw: messageRaw == runtimeNullSentinelInt ? 0 : messageRaw
    )
}

@_cdecl("__kk_closed_send_channel_exception_new_message")
public func kk_closed_send_channel_exception_new_message(_ messageRaw: Int) -> Int {
    let message = (messageRaw == 0 || messageRaw == runtimeNullSentinelInt)
        ? nil
        : extractString(from: UnsafeMutableRawPointer(bitPattern: messageRaw))
    return runtimeAllocateClosedSendChannelException(
        message: message,
        messageRaw: messageRaw == runtimeNullSentinelInt ? 0 : messageRaw
    )
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
