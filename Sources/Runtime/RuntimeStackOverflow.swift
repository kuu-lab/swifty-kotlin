import Foundation
import RuntimeCAtomics

// Generated function prologues call `kk_stack_overflow_check` once with a
// marker address inside their own stack frame. While the marker stays above
// the current thread's overflow bound the check returns 0; once it drops below
// the bound it returns a freshly allocated `kotlin.StackOverflowError` handle,
// which the prologue propagates through the ordinary `outThrown` channel —
// turning a native stack exhaustion SIGSEGV into a catchable exception.
//
// The bound is the thread's lowest usable stack address plus a reserve, found
// lazily per thread (compiled code also runs on DispatchQueue.global() worker
// threads, which have their own smaller stacks) and cached in a pthread TLS
// slot so the per-frame check is just one TLS read and a compare.

private let runtimeStackOverflowMinReserve = 64 * 1024
private let runtimeStackOverflowMaxReserve = 256 * 1024
private let runtimeStackOverflowReserveDivisor = 8

private let runtimeStackBoundTLSKey: pthread_key_t = {
    var key = pthread_key_t()
    pthread_key_create(&key, nil)
    return key
}()

private func runtimeStackOverflowReserve(forStackSize size: Int) -> Int {
    min(
        max(size / runtimeStackOverflowReserveDivisor, runtimeStackOverflowMinReserve),
        runtimeStackOverflowMaxReserve
    )
}

private func runtimeComputeCurrentThreadStackLowBound() -> Int {
    var size: UInt = 0
    let low = Int(kkrt_thread_stack_low_address(&size))
    guard low > 0, size > 0 else {
        return 0
    }
    return low + runtimeStackOverflowReserve(forStackSize: Int(size))
}

private func runtimeCurrentThreadStackLowBound() -> Int {
    if let cached = pthread_getspecific(runtimeStackBoundTLSKey) {
        return Int(bitPattern: cached)
    }
    let bound = runtimeComputeCurrentThreadStackLowBound()
    pthread_setspecific(runtimeStackBoundTLSKey, UnsafeMutableRawPointer(bitPattern: bound))
    return bound
}

@_cdecl("kk_stack_overflow_check")
public func kk_stack_overflow_check(_ marker: Int) -> Int {
    let bound = runtimeCurrentThreadStackLowBound()
    guard bound > 0, marker < bound else {
        return 0
    }
    return runtimeAllocateStackOverflowError(message: nil)
}
