#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc

// glibc's `pthread_getattr_np` is a GNU extension that the Glibc module does not
// re-export, so declare it directly.
@_silgen_name("pthread_getattr_np")
private func kswiftk_pthread_getattr_np(
    _ thread: pthread_t,
    _ attributes: UnsafeMutablePointer<pthread_attr_t>
) -> Int32
#endif

/// Reports whether the current thread still has native stack left for another
/// round of deeply recursive work.
///
/// Recursive compiler phases cap their nesting depth (`maxRecursionDepth`,
/// `maxStructuralRecursionDepth`) to stay clear of the stack, but the caps are
/// sized for a generous stack while the same code also runs on 512 KiB threads:
/// the Swift Concurrency cooperative pool (Swift Testing), the Dispatch workers
/// used by the parallel per-file frontend passes, and LSP request threads. There
/// the fixed cap is only reached long after the stack is gone, so the guard
/// crashes (SIGBUS / SIGSEGV) instead of producing its diagnostic. Probing the
/// remaining stack makes those guards effective regardless of the caller's
/// stack size, while leaving the depth cap as the deterministic limit on
/// threads that do have room for it.
enum StackHeadroom {
    /// Stop recursing while at least this much stack is still available.
    ///
    /// A single structural recursion level costs roughly 4 KiB in a debug
    /// build, and the guards below re-probe on every level, so this leaves room
    /// for the current level plus the non-recursive helpers it calls.
    static let defaultReserveBytes = 128 << 10

    /// Depth below which probing is skipped entirely; shallow recursion cannot
    /// exhaust even the smallest stack we run on, so the common case stays free.
    static let probeDepthThreshold = 32

    /// Returns `true` once the current thread has less than `reserveBytes` of
    /// stack left. Returns `false` when the bounds cannot be determined, which
    /// leaves the plain depth cap in charge.
    static func isExhausted(reserveBytes: Int = defaultReserveBytes) -> Bool {
        guard let lowBound = currentThreadStackLowBound() else { return false }
        var probe = 0
        let stackPointer = withUnsafeMutablePointer(to: &probe) { UInt(bitPattern: $0) }
        return stackPointer < lowBound &+ UInt(reserveBytes)
    }

    /// Returns `true` when recursion at `depth` should stop because the stack is
    /// nearly exhausted.
    static func isExhausted(atDepth depth: Int) -> Bool {
        depth >= probeDepthThreshold && isExhausted()
    }

    // MARK: - Per-thread stack bounds

    private static let lowBoundKey: pthread_key_t = {
        var key = pthread_key_t()
        pthread_key_create(&key, nil)
        return key
    }()

    private static func currentThreadStackLowBound() -> UInt? {
        if let cached = pthread_getspecific(lowBoundKey) {
            return UInt(bitPattern: cached)
        }
        guard let lowBound = computeStackLowBound(),
              let cacheable = UnsafeMutableRawPointer(bitPattern: lowBound)
        else {
            return nil
        }
        pthread_setspecific(lowBoundKey, cacheable)
        return lowBound
    }

    private static func computeStackLowBound() -> UInt? {
        #if canImport(Darwin)
        // `pthread_get_stackaddr_np` returns the high (starting) address.
        let highBound = UInt(bitPattern: pthread_get_stackaddr_np(pthread_self()))
        let size = UInt(pthread_get_stacksize_np(pthread_self()))
        guard size > 0, highBound > size else { return nil }
        return highBound - size
        #elseif canImport(Glibc)
        var attributes = pthread_attr_t()
        guard kswiftk_pthread_getattr_np(pthread_self(), &attributes) == 0 else { return nil }
        defer { pthread_attr_destroy(&attributes) }
        var base: UnsafeMutableRawPointer?
        var size = 0
        guard pthread_attr_getstack(&attributes, &base, &size) == 0, let base, size > 0 else {
            return nil
        }
        return UInt(bitPattern: base)
        #else
        return nil
        #endif
    }
}
