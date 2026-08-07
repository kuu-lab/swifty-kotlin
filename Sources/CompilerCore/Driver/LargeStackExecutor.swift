import Foundation

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

    private final class ResultBox<T>: @unchecked Sendable {
        var result: Result<T, any Error>?
    }

    static func run<T>(
        _ body: @escaping @Sendable () throws -> T
    ) throws -> T {
        let box = ResultBox<T>()
        let done = DispatchSemaphore(value: 0)
        let thread = Thread {
            box.result = Result(catching: body)
            done.signal()
        }
        thread.stackSize = stackSize
        thread.name = "kswiftk.large-stack"
        thread.start()
        done.wait()
        return try box.result!.get()
    }
}
