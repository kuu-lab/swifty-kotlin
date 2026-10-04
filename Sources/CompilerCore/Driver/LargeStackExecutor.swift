import Foundation
#if canImport(Darwin)
import Dispatch
#elseif canImport(Glibc)
import Glibc
#endif

/// Holds the closure and the captured result. Marked `@unchecked Sendable`
/// because the result is produced on the spawned thread and consumed on the
/// caller thread; the join back to the caller thread (a semaphore wait on
/// Darwin, `pthread_join` elsewhere) provides the synchronization that makes
/// this safe.
private final class LargeStackWorkBox: @unchecked Sendable {
    let body: () throws -> Any
    var result: Result<Any, any Error>?

    init(body: @escaping () throws -> Any) {
        self.body = body
    }

    func run() {
        result = Result(catching: body)
    }
}

#if !canImport(Darwin)
private func largeStackThreadEntry(_ arg: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    let box = Unmanaged<LargeStackWorkBox>.fromOpaque(arg!).takeUnretainedValue()
    box.run()
    return nil
}
#endif

/// Runs work synchronously on a dedicated thread with an explicitly sized stack.
///
/// Recursive compiler phases (notably KIR expression lowering, whose frames are
/// large) can overflow small thread stacks. Swift Testing executes tests as tasks
/// on the Swift Concurrency cooperative pool, whose threads have 512 KiB stacks,
/// so lowering even moderately nested expressions there crashes with SIGBUS
/// (signal 10). Hopping to a thread with a large fixed stack makes recursion
/// headroom independent of the calling thread.
///
/// The caller blocks until the work completes, so a cooperative-pool thread is
/// occupied for exactly as long as it would have been running the work inline —
/// the hop trades no parallelism for the larger stack.
///
/// Callers must pass a `@Sendable` escaping closure. Non-`Sendable` inputs can be
/// wrapped in a private `@unchecked Sendable` work object and invoked from the
/// closure, which keeps the cross-thread capture explicit and avoids relying on
/// `withoutActuallyEscaping` for thread hops.
enum LargeStackExecutor {
    /// Virtual allocation only — pages are committed lazily by the kernel.
    private static let stackSize = 64 << 20

    static func run<T>(
        _ body: @escaping @Sendable () throws -> T
    ) throws -> T {
        let box = LargeStackWorkBox { try body() as Any }

        #if canImport(Darwin)
        // `pthread_t` has no zero-argument initializer on current Darwin SDKs
        // (it's a bare `UnsafeMutablePointer`, unlike Glibc's integer typedef).
        // A `var thread: pthread_t?` + `pthread_create(&thread, ...)` shape
        // type-checks, but on this toolchain (Swift 6.3.3 / SDK MacOSX26.5)
        // `swift-frontend` reliably crashes (SIGABRT) in the SIL
        // `SendNonSendable` region-isolation pass when lowering that exact
        // call pattern here -- reproduced across several refactorings of the
        // surrounding code (BUG-192). `Foundation.Thread` honors `stackSize`
        // on Darwin, so it sidesteps raw pthreads entirely rather than
        // chasing `pthread_create`'s SDK-specific signature.
        let done = DispatchSemaphore(value: 0)
        let thread = Thread {
            box.run()
            done.signal()
        }
        thread.stackSize = stackSize
        thread.start()
        done.wait()
        #else
        var attr = pthread_attr_t()
        guard pthread_attr_init(&attr) == 0 else {
            // If we cannot configure a large stack, run the work on the caller
            // thread as a last resort. This may overflow on tiny cooperative-pool
            // stacks, but it is better than silently hanging or losing the result.
            box.run()
            return try box.result!.get() as! T
        }
        defer { _ = pthread_attr_destroy(&attr) }

        _ = pthread_attr_setstacksize(&attr, stackSize)

        var thread = pthread_t()
        let boxPtr = Unmanaged.passUnretained(box).toOpaque()

        guard pthread_create(&thread, &attr, largeStackThreadEntry, boxPtr) == 0 else {
            box.run()
            return try box.result!.get() as! T
        }

        _ = pthread_join(thread, nil)
        #endif
        return try box.result!.get() as! T
    }
}
