import Dispatch
import Foundation

// MARK: - Native Concurrent ABI (STDLIB-NATIVE-CONCURRENT-ABI-001..003, 005..006)
//
// Implements the runtime entry-points required by the Kotlin/Native
// concurrent standard library:
//
//   ABI-001  Worker.id              — kk_worker_id
//   ABI-002  Future<T>              — kk_future_new / kk_future_complete /
//                                     kk_future_result / kk_future_consume /
//                                     kk_future_is_ready / kk_future_getState /
//                                     kk_future_invoke
//   ABI-003  TransferMode           — kk_transfer_object  (SAFE freezes; UNSAFE is pass-through)
//   ABI-005  Worker.executeAfter    — kk_worker_execute_after
//   ABI-006  Worker receiver helpers — kk_worker_process_queue / kk_worker_park /
//                                      kk_worker_platform_thread_id /
//                                      kk_worker_as_cpointer
//
// Deferred / known limitations:
//   • TransferMode SAFE: full cycle-detection DFS over the managed object graph
//     is not yet implemented.  The current implementation freezes the root
//     object (consistent with Kotlin/Native semantics) but does not recursively
//     walk reachable references.  A future pass can add that once the type-info
//     system exposes field offsets.

// MARK: - ABI-001  Worker.id

/// Global monotonic counter for Worker IDs.
private let workerIDCounter = WorkerIDCounter()

private final class WorkerIDCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var next: Int = 1

    func nextID() -> Int {
        lock.lock()
        defer { lock.unlock() }
        let id = next
        next += 1
        return id
    }
}

/// Per-worker ID registry.  Maps the raw pointer address of a `RuntimeWorkerBox`
/// to its assigned monotonic ID so that repeated calls return a stable value.
private let workerIDRegistry = WorkerIDRegistry()

private final class WorkerIDRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var table: [UInt: Int] = [:]

    func id(for address: UInt) -> Int {
        lock.lock()
        defer { lock.unlock() }
        if let existing = table[address] {
            return existing
        }
        let newID = workerIDCounter.nextID()
        table[address] = newID
        return newID
    }

}

/// Registry of live workers backing `Worker.Companion.activeWorkers` and
/// `Worker.Companion.fromCPointer`. Maps each worker's stable ID (assigned by
/// `workerIDRegistry`) to its runtime handle so the public surface hands back
/// the same `Worker` identity `kk_worker_new` produced. Entries are added when
/// a worker box materializes and removed on `requestTermination`.
private let activeWorkerRegistry = ActiveWorkerRegistry()

private final class ActiveWorkerRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var handleByID: [Int: Int] = [:]

    func register(id: Int, handle: Int) {
        lock.lock()
        defer { lock.unlock() }
        handleByID[id] = handle
    }

    func unregister(id: Int) {
        lock.lock()
        defer { lock.unlock() }
        handleByID.removeValue(forKey: id)
    }

    func handle(forID id: Int) -> Int? {
        lock.lock()
        defer { lock.unlock() }
        return handleByID[id]
    }

    /// Live worker handles ordered by worker ID for a deterministic list.
    func activeHandles() -> [Int] {
        lock.lock()
        defer { lock.unlock() }
        return handleByID.sorted { $0.key < $1.key }.map { $0.value }
    }
}

/// Registers `handle` under the worker ID derived from `workerIDRegistry`.
/// Called by every entry point that materializes a `RuntimeWorkerBox`.
func registerActiveWorker(handle: Int) {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: handle) else { return }
    let workerID = workerIDRegistry.id(for: UInt(bitPattern: pointer))
    activeWorkerRegistry.register(id: workerID, handle: handle)
}

/// Removes `handle` from the active-worker registry after termination.
func unregisterActiveWorker(handle: Int) {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: handle) else { return }
    let workerID = workerIDRegistry.id(for: UInt(bitPattern: pointer))
    activeWorkerRegistry.unregister(id: workerID)
}

/// Returns the monotonic integer ID for a Worker.
///
/// - Parameter workerHandle: opaque handle produced by `kk_worker_new`.
/// - Returns: A positive integer (≥ 1) that is stable across calls, or −1 for an invalid handle.
@_cdecl("kk_worker_id")
public func kk_worker_id(_ workerHandle: Int) -> Int {
    guard workerHandle != 0,
          let ptr = UnsafeMutableRawPointer(bitPattern: workerHandle)
    else {
        return -1
    }
    // Confirm the handle actually points to a RuntimeWorkerBox.
    guard tryCast(ptr, to: RuntimeWorkerBox.self) != nil else {
        return -1
    }
    return workerIDRegistry.id(for: UInt(bitPattern: ptr))
}

// MARK: - ABI-002  Future<T>

/// Runtime backing for `kotlin.native.concurrent.Future<T>`.
///
/// A Future is a single-assignment promise: one producer calls `complete`,
/// after which any number of consumers may call `result` (blocking until ready)
/// or `consume` (one-shot retrieval that nulls out the stored value).
final class RuntimeFutureBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _resultRaw: Int = 0
    private var _ready: Bool = false
    private var _consumed: Bool = false
    /// Semaphores of threads blocked on this future: one per `blockUntilReady`
    /// caller and one shared signal per `wait_for_multiple_futures` call.
    /// `complete` signals each once, then clears the list.
    private var waitSignals: [DispatchSemaphore] = []

    /// Blocks until the future is ready or `timeoutNs` elapses.  The caller
    /// parks on its own semaphore instead of polling `_ready`.
    func blockUntilReady(timeoutNs: Int = 5_000_000_000) {
        let signal = DispatchSemaphore(value: 0)
        lock.lock()
        if _ready {
            lock.unlock()
            return
        }
        waitSignals.append(signal)
        lock.unlock()

        _ = signal.wait(timeout: DispatchTime.now() + .nanoseconds(timeoutNs))

        removeWaitSignal(signal)
    }

    /// Registers `signal` to be signalled once this future completes.  When the
    /// future is already completed and still consumable, signals immediately so
    /// a multi-future waiter cannot miss a completion that raced registration.
    func addWaitSignal(_ signal: DispatchSemaphore) {
        lock.lock()
        defer { lock.unlock() }
        guard !_ready else {
            if !_consumed {
                signal.signal()
            }
            return
        }
        waitSignals.append(signal)
    }

    /// Removes `signal` if it is still registered (no-op after `complete`
    /// cleared the list).
    func removeWaitSignal(_ signal: DispatchSemaphore) {
        lock.lock()
        defer { lock.unlock() }
        waitSignals.removeAll { $0 === signal }
    }

    func complete(valueRaw: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard !_ready else { return } // single-assignment
        _resultRaw = valueRaw
        _ready = true
        for signal in waitSignals {
            signal.signal()
        }
        waitSignals.removeAll()
    }

    var isReady: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _ready
    }

    var isAvailableForConsumption: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _ready && !_consumed
    }

    var stateRaw: Int {
        lock.lock()
        defer { lock.unlock() }
        if _consumed { return 0 } // FutureState.INVALID
        return _ready ? 2 : 1 // FutureState.COMPUTED : FutureState.SCHEDULED
    }

    /// Non-consuming read.  Blocks until a value is available.
    func result() -> Int {
        blockUntilReady()
        lock.lock()
        defer { lock.unlock() }
        return _ready ? _resultRaw : 0
    }

    /// One-shot retrieval.  Returns the value and zeroes the stored reference.
    func consume() -> Int {
        blockUntilReady()
        lock.lock()
        defer { lock.unlock() }
        guard _ready, !_consumed else { return 0 }
        _consumed = true
        let v = _resultRaw
        _resultRaw = 0
        return v
    }
}

/// Allocate a new, unresolved Future.
@_cdecl("kk_future_new")
public func kk_future_new() -> Int {
    return registerRuntimeObject(RuntimeFutureBox())
}

/// Resolve the Future with `valueRaw`.  Must be called exactly once.
@discardableResult
@_cdecl("kk_future_complete")
public func kk_future_complete(_ futureHandle: Int, _ valueRaw: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: futureHandle),
          let box = tryCast(ptr, to: RuntimeFutureBox.self)
    else {
        return 0
    }
    box.complete(valueRaw: valueRaw)
    return 0
}

/// Returns 1 if the Future has been resolved, 0 otherwise.
@_cdecl("kk_future_is_ready")
public func kk_future_is_ready(_ futureHandle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: futureHandle),
          let box = tryCast(ptr, to: RuntimeFutureBox.self)
    else {
        return 0
    }
    return box.isReady ? 1 : 0
}

/// Returns the FutureState ordinal for a valid runtime Future handle.
@_cdecl("kk_future_getState")
public func kk_future_getState(_ futureHandle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: futureHandle),
          let box = tryCast(ptr, to: RuntimeFutureBox.self)
    else {
        return 0 // FutureState.INVALID
    }
    return box.stateRaw
}

/// Invoke a Future.consume callback through the function-value ABI.
@_cdecl("kk_future_invoke")
public func kk_future_invoke(
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ valueRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeInvokeCollectionLambda1(
        fnPtr: fnPtr,
        closureRaw: closureRaw,
        value: valueRaw,
        outThrown: outThrown
    )
}

/// Blocking, non-consuming read of the resolved value.
@_cdecl("kk_future_result")
public func kk_future_result(_ futureHandle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: futureHandle),
          let box = tryCast(ptr, to: RuntimeFutureBox.self)
    else {
        return 0
    }
    return box.result()
}

/// Blocking, one-shot consume.  Second call returns 0.
@_cdecl("kk_future_consume")
public func kk_future_consume(_ futureHandle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: futureHandle),
          let box = tryCast(ptr, to: RuntimeFutureBox.self)
    else {
        return 0
    }
    return box.consume()
}

// MARK: - KSP-1216 package-level bridges

/// The modern memory manager no longer detaches object graphs. Keep the raw
/// managed reference as the opaque NativePtr token consumed by attach.
@_cdecl("__kk_native_concurrent_detach_object_graph")
public func __kk_native_concurrent_detach_object_graph(_ modeRaw: Int, _ valueRaw: Int) -> Int {
    _ = modeRaw
    return valueRaw
}

/// Reattaches the opaque token produced by detachObjectGraphInternal.
@_cdecl("__kk_native_concurrent_attach_object_graph")
public func __kk_native_concurrent_attach_object_graph(_ stableRaw: Int) -> Int {
    stableRaw
}

/// Consumes a Future through the source-backed package helper.
@_cdecl("__kk_native_concurrent_consume_future")
public func __kk_native_concurrent_consume_future(_ futureHandle: Int) -> Int {
    kk_future_consume(futureHandle)
}

/// Runtime-owned thread scheduling for the source-backed executeImpl wrapper.
@_cdecl("__kk_native_concurrent_execute_impl")
public func __kk_native_concurrent_execute_impl(
    _ workerHandle: Int,
    _ modeRaw: Int,
    _ jobArgumentRaw: Int,
    _ jobPointerHandle: Int
) -> Int {
    _ = modeRaw
    guard workerHandle != 0,
          let workerPointer = UnsafeMutableRawPointer(bitPattern: workerHandle),
          let worker = tryCast(workerPointer, to: RuntimeWorkerBox.self)
    else {
        return 0
    }

    let jobAddress: UInt
    if let pointerBox = resolveCPointerBox(from: jobPointerHandle) {
        jobAddress = pointerBox.address
    } else {
        jobAddress = UInt(bitPattern: jobPointerHandle)
    }
    guard jobAddress != 0,
          let jobPointer = UnsafeRawPointer(bitPattern: jobAddress)
    else {
        return 0
    }

    typealias JobFunction = @convention(c) (Int) -> Int
    let job = unsafeBitCast(jobPointer, to: JobFunction.self)
    let futureHandle = kk_future_new()
    let submitted = worker.execute {
        _ = kk_future_complete(futureHandle, job(jobArgumentRaw))
    }
    return submitted ? futureHandle : 0
}

/// Returns the handles of futures ready for consumption, and registers
/// `signal` on every still-pending future not already in `registered` so that
/// the next `kk_future_complete` wakes the waiter for a re-scan.
private func nativeConcurrentReadyFutureHandles(
    _ futuresHandle: Int,
    signal: DispatchSemaphore,
    registered: inout Set<Int>
) -> [Int] {
    guard let futures = runtimeCollectionElements(from: futuresHandle) else {
        return []
    }
    var ready: [Int] = []
    for futureHandle in futures {
        guard let pointer = UnsafeMutableRawPointer(bitPattern: futureHandle),
              let future = tryCast(pointer, to: RuntimeFutureBox.self)
        else {
            continue
        }
        if future.isAvailableForConsumption {
            ready.append(futureHandle)
        } else if registered.insert(futureHandle).inserted {
            future.addWaitSignal(signal)
        }
    }
    return ready
}

/// Waits until at least one Future can be consumed or the timeout expires.
@_cdecl("__kk_native_concurrent_wait_for_multiple_futures")
public func __kk_native_concurrent_wait_for_multiple_futures(
    _ futuresHandle: Int,
    _ timeoutMillis: Int
) -> Int {
    let deadline = timeoutMillis >= 0
        ? DispatchTime.now() + .milliseconds(timeoutMillis)
        : nil
    // One signal shared by every pending future in the set: `complete` wakes
    // this wait exactly once per completion, and each wakeup re-scans.
    let signal = DispatchSemaphore(value: 0)
    var registered = Set<Int>()
    defer {
        for futureHandle in registered {
            guard let pointer = UnsafeMutableRawPointer(bitPattern: futureHandle),
                  let future = tryCast(pointer, to: RuntimeFutureBox.self)
            else {
                continue
            }
            future.removeWaitSignal(signal)
        }
    }
    while true {
        let ready = nativeConcurrentReadyFutureHandles(
            futuresHandle,
            signal: signal,
            registered: &registered
        )
        if !ready.isEmpty {
            return registerRuntimeObject(RuntimeSetBox(elements: ready))
        }
        if let deadline {
            if DispatchTime.now() >= deadline {
                return registerRuntimeObject(RuntimeSetBox(elements: []))
            }
            _ = signal.wait(timeout: deadline)
        } else {
            signal.wait()
        }
    }
}

/// Starts a worker without exposing the adjacent Worker.Companion API surface.
@_cdecl("__kk_native_concurrent_start_worker")
public func __kk_native_concurrent_start_worker(_ errorReportingRaw: Int, _ nameRaw: Int) -> Int {
    _ = errorReportingRaw
    return kk_worker_new(nameRaw)
}

/// Terminates and joins a worker used by withWorker.
@_cdecl("__kk_native_concurrent_terminate_worker")
public func __kk_native_concurrent_terminate_worker(_ workerHandle: Int) -> Int {
    let futureHandle = kk_worker_request_termination(workerHandle, 1)
    if futureHandle != 0 {
        _ = kk_future_result(futureHandle)
    }
    return 0
}

/// Blocks until a previously requested worker termination becomes visible.
@_cdecl("__kk_native_concurrent_wait_worker_termination")
public func __kk_native_concurrent_wait_worker_termination(_ workerHandle: Int) -> Int {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: workerHandle),
          let worker = tryCast(pointer, to: RuntimeWorkerBox.self)
    else {
        return 0
    }
    worker.waitForTermination()
    return 0
}

/// Returns the worker bound to the calling thread. Backs both
/// `WorkerBoundReference.worker` (KSP-1253) and the public
/// `Worker.Companion.current` surface (KSP-1251).
@_cdecl("__kk_native_concurrent_current_worker")
public func __kk_native_concurrent_current_worker() -> Int {
    runtimeCurrentWorkerHandle()
}

/// Returns the live workers tracked by `activeWorkerRegistry`, ordered by
/// worker ID for a deterministic list. Backs `Worker.Companion.activeWorkers`
/// (KSP-1251). The calling thread's worker is resolved first so the lazily
/// materialized main worker is always listed, matching the upstream contract
/// that `activeWorkers` covers the current worker.
@_cdecl("__kk_native_concurrent_active_workers")
public func __kk_native_concurrent_active_workers() -> Int {
    _ = runtimeCurrentWorkerHandle()
    return registerRuntimeObject(RuntimeListBox(elements: activeWorkerRegistry.activeHandles()))
}

/// Resolves a `COpaquePointer` produced by `kk_worker_as_cpointer` (whose
/// address is the worker's stable ID) back into the live worker handle.
/// Backs `Worker.Companion.fromCPointer` (KSP-1251). Returns 0 for invalid
/// pointers or IDs of workers that already terminated.
@_cdecl("__kk_native_concurrent_worker_from_cpointer")
public func __kk_native_concurrent_worker_from_cpointer(_ pointerHandle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: pointerHandle) else {
        return 0
    }
    let address: UInt
    if let box = tryCast(ptr, to: RuntimeCOpaquePointerBox.self) {
        address = box.address
    } else if let box = tryCast(ptr, to: RuntimeCPointerBox.self) {
        address = box.address
    } else {
        return 0
    }
    return activeWorkerRegistry.handle(forID: Int(bitPattern: address)) ?? 0
}

// MARK: - ABI-003  TransferMode

// TransferMode raw values (mirrors Kotlin/Native enum ordinal):
//   SAFE   = 0  — freeze the object before transfer; enforce immutability
//   UNSAFE = 1  — skip freeze; caller takes responsibility for thread safety

/// Transfer `objectRaw` to another thread under the specified `TransferMode`.
///
/// SAFE mode: freezes the object so it becomes safely shareable.
/// UNSAFE mode: passes the handle through without modification.
///
/// - Returns: the original `objectRaw` handle, or 0 for a null handle.
@discardableResult
@_cdecl("kk_transfer_object")
public func kk_transfer_object(_ objectRaw: Int, _ modeRaw: Int) -> Int {
    guard objectRaw != 0 else {
        return 0
    }
    if modeRaw == 0 {
        // SAFE: freeze before handing off.
        _ = kk_freeze_object(objectRaw)
    }
    // UNSAFE: pass through — caller is responsible for safety.
    return objectRaw
}

// MARK: - Worker receiver helpers

/// Process jobs already queued for a Worker.
@_cdecl("kk_worker_process_queue")
public func kk_worker_process_queue(_ workerHandle: Int) -> Int {
    guard workerHandle != 0,
          let ptr = UnsafeMutableRawPointer(bitPattern: workerHandle),
          let worker = tryCast(ptr, to: RuntimeWorkerBox.self)
    else {
        return 0
    }
    return worker.processQueue() ? 1 : 0
}

/// Park the current Worker thread for a timeout in microseconds.
@_cdecl("kk_worker_park")
public func kk_worker_park(
    _ workerHandle: Int,
    _ timeoutMicroseconds: Int,
    _ processRaw: Int
) -> Int {
    guard workerHandle != 0,
          let ptr = UnsafeMutableRawPointer(bitPattern: workerHandle),
          let worker = tryCast(ptr, to: RuntimeWorkerBox.self)
    else {
        return 0
    }
    return worker.park(
        timeoutMicroseconds: timeoutMicroseconds,
        process: processRaw != 0
    ) ? 1 : 0
}

/// Return the platform thread ID servicing the Worker queue.
@_cdecl("kk_worker_platform_thread_id")
public func kk_worker_platform_thread_id(_ workerHandle: Int) -> Int {
    guard workerHandle != 0,
          let ptr = UnsafeMutableRawPointer(bitPattern: workerHandle),
          let worker = tryCast(ptr, to: RuntimeWorkerBox.self)
    else {
        return 0
    }
    return Int(truncatingIfNeeded: worker.platformThreadID())
}

/// Return a COpaquePointer whose address is the Worker's stable ID.
@_cdecl("kk_worker_as_cpointer")
public func kk_worker_as_cpointer(_ workerHandle: Int) -> Int {
    let workerID = kk_worker_id(workerHandle)
    guard workerID > 0 else {
        return 0
    }
    return kk_copaque_pointer_new(workerID)
}

// MARK: - ABI-006  Worker.executeAfter(afterMicroseconds, operation)

/// Schedule a closure to run on a Worker after `afterMicroseconds` microseconds.
///
/// Uses `DispatchQueue.asyncAfter` on the Worker's underlying serial queue.
/// The closure is represented by the standard closure-thunk `(fnPtr, closureRaw)`
/// ABI (`KKClosureThunkEntryPoint`): `fnPtr` takes `(closureRaw, outThrown)` and
/// returns an (unused, for a `Unit`-returning operation) `Int`.
///
/// - Parameters:
///   - workerHandle: handle produced by `kk_worker_new`.
///   - afterMicroseconds: delay in microseconds (0 means "as soon as possible").
///   - fnPtr:        C function pointer for the closure body.
///   - closureRaw:   opaque closure capture handle passed to `fnPtr`.
/// - Returns: 1 if scheduled, 0 if the worker is terminated or `fnPtr` is null.
@_cdecl("kk_worker_execute_after")
public func kk_worker_execute_after(
    _ workerHandle: Int,
    _ afterMicroseconds: Int,
    _ fnPtr: Int,
    _ closureRaw: Int
) -> Int {
    guard workerHandle != 0,
          let ptr = UnsafeMutableRawPointer(bitPattern: workerHandle),
          let worker = tryCast(ptr, to: RuntimeWorkerBox.self)
    else {
        return 0
    }
    guard !worker.isTerminated else {
        return 0
    }
    guard fnPtr != 0 else {
        return 0
    }
    guard afterMicroseconds >= 0 else {
        return 0
    }
    // `fnPtr`/`closureRaw` could in principle arrive as a
    // `kk_function_create_0`-wrapped function-value handle rather than a raw
    // (fnPtr, closureRaw) pair — see `resolveFunctionValuePair`. Resolve on
    // the calling thread so the deferred closure below only ever captures a
    // raw pair.
    let resolved = resolveFunctionValuePair(fnPtr: fnPtr, closureRaw: closureRaw)
    // A compiled Kotlin closure body always follows the standard
    // KKClosureThunkEntryPoint convention — (closureRaw, outThrown) -> Int,
    // matching runtimeInvokeClosureThunk elsewhere in this file — never the
    // 1-argument `(Int) -> Int` this used to declare here. Calling a 2-arg
    // callee as if it took 1 arg leaves its `outThrown` parameter register
    // holding whatever the caller last put there, so `operation`'s generated
    // adapter (which unconditionally writes `outThrown?.pointee = 0` on the
    // no-exception path) stores through that garbage address and crashes.
    let fn = unsafeBitCast(UnsafeRawPointer(bitPattern: resolved.fnPtr)!, to: KKClosureThunkEntryPoint.self)
    let captured = resolved.closureRaw
    let deadline: DispatchTime = afterMicroseconds > 0
        ? DispatchTime.now() + .microseconds(afterMicroseconds)
        : .now()
    let submitted = worker.executeAfter(deadline: deadline) {
        // Fire-and-forget: executeAfter's Kotlin signature returns Unit with
        // no Future, so there is nothing to report a thrown exception to.
        var thrown = 0
        _ = fn(captured, &thrown)
    }
    return submitted ? 1 : 0
}
