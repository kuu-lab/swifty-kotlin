import Dispatch
import Foundation

// KUU-1732: private syscall/memory/GC kernels for the source-owned atomicfu API.
// Ordinary Kotlin wrappers keep these registered objects in GC-traced Any fields.
// This kernel never accepts an ordinary wrapper as a coroutine Mutex handle.

private final class AtomicfuThreadIdentity {
    let value = RuntimeTaskKey.makeUnique().rawValue
}
private let atomicfuThreadIdentityKey = makePthreadKey()
private func atomicfuThreadIdentity() -> UInt64 {
    if let existing: AtomicfuThreadIdentity = pthreadGetValue(atomicfuThreadIdentityKey) {
        return existing.value
    }
    let value = AtomicfuThreadIdentity()
    pthreadSetValue(atomicfuThreadIdentityKey, value)
    return value.value
}

// DispatchTime uses a monotonic clock. Saturation avoids overflow for very large
// finite Kotlin Duration values. -1 alone is the private infinite-wait sentinel.
private func atomicfuDeadline(_ nanos: Int) -> DispatchTime {
    if nanos == -1 { return .distantFuture }
    let now = DispatchTime.now().uptimeNanoseconds
    let delta = UInt64(max(0, nanos))
    let sum = now.addingReportingOverflow(delta)
    return DispatchTime(uptimeNanoseconds: sum.overflow ? UInt64.max : sum.partialValue)
}

final class RuntimeAtomicfuRecursiveLock: @unchecked Sendable {
    private final class Waiter {
        let owner: UInt64
        let wake = DispatchSemaphore(value: 0)
        var granted = false // only accessed with stateLock held
        init(owner: UInt64) { self.owner = owner }
    }
    let ownerErrorIsArgument: Bool
    init(ownerErrorIsArgument: Bool = false) { self.ownerErrorIsArgument = ownerErrorIsArgument }
    private let stateLock = NSLock()
    private var owner: UInt64?
    private var depth = 0
    private var waiters: [Waiter] = []

    func acquire(timeoutNanos: Int) -> Bool {
        let selfID = atomicfuThreadIdentity()
        let deadline = atomicfuDeadline(timeoutNanos)
        stateLock.lock()
        if owner == selfID {
            depth += 1
            stateLock.unlock()
            return true
        }
        if owner == nil && waiters.isEmpty {
            owner = selfID
            depth = 1
            stateLock.unlock()
            return true
        }
        if timeoutNanos == 0 {
            stateLock.unlock()
            return false
        }
        let waiter = Waiter(owner: selfID)
        waiters.append(waiter)
        stateLock.unlock()
        _ = waiter.wake.wait(timeout: deadline)
        stateLock.lock()
        defer { stateLock.unlock() }
        // A grant racing a timeout transfers actual ownership; the awakened
        // thread must accept it, rather than leaking a lock assigned to it.
        if waiter.granted { return true }
        waiters.removeAll { $0 === waiter }
        return false
    }

    func release() -> Bool {
        let selfID = atomicfuThreadIdentity()
        stateLock.lock()
        defer { stateLock.unlock() }
        guard owner == selfID, depth > 0 else { return false }
        depth -= 1
        if depth != 0 { return true }
        owner = nil
        if !waiters.isEmpty {
            let waiter = waiters.removeFirst()
            owner = waiter.owner
            depth = 1
            waiter.granted = true
            waiter.wake.signal()
        }
        return true
    }

    // Used by deterministic direct Runtime tests, not exported through the ABI.
    var queuedWaiterCount: Int {
        stateLock.lock()
        defer { stateLock.unlock() }
        return waiters.count
    }
}

final class RuntimeAtomicfuParker: @unchecked Sendable {
    private final class Waiter {
        let wake = DispatchSemaphore(value: 0)
    }
    private let owner = atomicfuThreadIdentity()
    private let stateLock = NSLock()
    private var permit = false
    private var waiter: Waiter?

    // false means a wrong-thread or already-parked misuse, not a timeout.
    // The optional internal hook pauses the owner after wake for deterministic
    // handoff tests. It runs outside stateLock and is nil at all Runtime ABI calls.
    func park(timeoutNanos: Int, afterWaitBeforeCleanup: (() -> Void)? = nil) -> Bool {
        guard owner == atomicfuThreadIdentity() else { return false }
        stateLock.lock()
        guard waiter == nil else {
            stateLock.unlock()
            return false
        }
        if permit {
            permit = false
            stateLock.unlock()
            return true
        }
        let current = Waiter()
        waiter = current
        stateLock.unlock()
        _ = current.wake.wait(timeout: atomicfuDeadline(timeoutNanos))
        afterWaitBeforeCleanup?()
        stateLock.lock()
        // A completed unpark detached this waiter. A subsequent unpark may
        // have installed a new permit; old owner cleanup must preserve it.
        if waiter === current { waiter = nil }
        stateLock.unlock()
        return true
    }

    var hasWaitingOwner: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return waiter != nil
    }

    func unpark() {
        stateLock.lock()
        defer { stateLock.unlock() }
        if let current = waiter {
            // Complete the wake handoff before returning, matching Native
            // Parked -> Unparking -> Free. Later unpark must become a permit.
            waiter = nil
            current.wake.signal()
        } else {
            permit = true // one bit: repeated pre-unpark calls coalesce
        }
    }
}

private final class AtomicfuParkingRoot {
    let value: Int
    let generation: UInt64
    private let root: UnsafeMutablePointer<UnsafeMutableRawPointer?>
    init(value: Int, generation: UInt64) {
        self.value = value
        self.generation = generation
        root = .allocate(capacity: 1)
        root.initialize(to: UnsafeMutableRawPointer(bitPattern: value))
        kk_register_global_root(root)
    }
    deinit {
        kk_unregister_global_root(root)
        root.deinitialize(count: 1)
        root.deallocate()
    }
}
private let atomicfuParkingRootKey = makePthreadKey()
private let atomicfuGenerationLock = NSLock()
nonisolated(unsafe) private var atomicfuParkingGeneration: UInt64 = 0
private func atomicfuCurrentGeneration() -> UInt64 {
    atomicfuGenerationLock.lock()
    defer { atomicfuGenerationLock.unlock() }
    return atomicfuParkingGeneration
}

// Test-only force-reset invalidates cached ordinary Kotlin wrapper allocations.
// Production GC retains registered TLS roots. Resets require runtime isolation,
// with worker jobs joined before heap reset (the existing reset contract).
func runtimeResetAtomicfuParkingCaches() {
    atomicfuGenerationLock.lock()
    atomicfuParkingGeneration &+= 1
    atomicfuGenerationLock.unlock()
    pthreadSetValue(atomicfuParkingRootKey, Optional<AtomicfuParkingRoot>.none)
}

private func atomicfuThrow(_ thrown: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    if let outThrown {
        outThrown.pointee = thrown
        return runtimeExceptionCaughtSentinel
    }
    fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: uncaught atomicfu synchronization exception")
}
private func atomicfuInvalidHandle(_ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    atomicfuThrow(runtimeAllocateIllegalArgumentException(message: "Invalid atomicfu kernel handle"), outThrown)
}

@_cdecl("__kk_atomicfu_lock_new")
public func __kk_atomicfu_lock_new(_ ownerErrorKind: Int) -> Int {
    registerRuntimeObject(RuntimeAtomicfuRecursiveLock(ownerErrorIsArgument: ownerErrorKind != 0))
}
@_cdecl("__kk_atomicfu_lock_lock")
public func __kk_atomicfu_lock_lock(_ kernel: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let lock = resolveRuntimeHandle(kernel, as: RuntimeAtomicfuRecursiveLock.self) else {
        return atomicfuInvalidHandle(outThrown)
    }
    _ = lock.acquire(timeoutNanos: -1)
    return 0
}
@_cdecl("__kk_atomicfu_lock_try_lock")
public func __kk_atomicfu_lock_try_lock(_ kernel: Int, _ timeoutNanos: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let lock = resolveRuntimeHandle(kernel, as: RuntimeAtomicfuRecursiveLock.self) else {
        return atomicfuInvalidHandle(outThrown)
    }
    return lock.acquire(timeoutNanos: timeoutNanos == -1 ? -1 : max(0, timeoutNanos)) ? 1 : 0
}
@_cdecl("__kk_atomicfu_lock_unlock")
public func __kk_atomicfu_lock_unlock(_ kernel: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let lock = resolveRuntimeHandle(kernel, as: RuntimeAtomicfuRecursiveLock.self) else {
        return atomicfuInvalidHandle(outThrown)
    }
    guard lock.release() else {
        let error = lock.ownerErrorIsArgument
            ? runtimeAllocateIllegalArgumentException(message: "Thread is not holding the lock")
            : runtimeAllocateIllegalStateException(message: "Thread is not holding the lock")
        return atomicfuThrow(error, outThrown)
    }
    return 0
}
@_cdecl("__kk_atomicfu_parker_new")
public func __kk_atomicfu_parker_new() -> Int {
    registerRuntimeObject(RuntimeAtomicfuParker())
}
@_cdecl("__kk_atomicfu_parker_wait")
public func __kk_atomicfu_parker_wait(_ kernel: Int, _ timeoutNanos: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let parker = resolveRuntimeHandle(kernel, as: RuntimeAtomicfuParker.self) else {
        return atomicfuInvalidHandle(outThrown)
    }
    guard parker.park(timeoutNanos: timeoutNanos == -1 ? -1 : max(0, timeoutNanos)) else {
        return atomicfuThrow(runtimeAllocateIllegalStateException(message: "Thread cannot park this handle"), outThrown)
    }
    return 0
}
@_cdecl("__kk_atomicfu_parker_unpark")
public func __kk_atomicfu_parker_unpark(_ kernel: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let parker = resolveRuntimeHandle(kernel, as: RuntimeAtomicfuParker.self) else {
        return atomicfuInvalidHandle(outThrown)
    }
    parker.unpark()
    return 0
}
@_cdecl("__kk_atomicfu_current_parking_handle")
public func __kk_atomicfu_current_parking_handle(_ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let generation = atomicfuCurrentGeneration()
    if let cached: AtomicfuParkingRoot = pthreadGetValue(atomicfuParkingRootKey), cached.generation == generation {
        return cached.value
    }
    var thrown = 0
    let result = runtimeInvokeClosureThunk(fnPtr: fnPtr, closureRaw: closureRaw, outThrown: &thrown)
    if thrown != 0 { return atomicfuThrow(thrown, outThrown) }
    guard resolveRuntimeObjectHandle(result) != nil else { return atomicfuInvalidHandle(outThrown) }
    pthreadSetValue(atomicfuParkingRootKey, AtomicfuParkingRoot(value: result, generation: generation))
    return result
}
