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
enum LargeStackExecutor {
    /// Virtual allocation only — pages are committed lazily by the kernel.
    private static let stackSize = 64 << 20

    private final class ResultBox<T>: @unchecked Sendable {
        var body: (() throws -> T)?
        var result: Result<T, any Error>?
    }

    static func run<T>(_ body: () throws -> T) throws -> T {
        try withoutActuallyEscaping(body) { escapingBody in
            let box = ResultBox<T>()
            box.body = escapingBody
            let done = DispatchSemaphore(value: 0)
            let thread = Thread {
                // Drop the body reference before signaling so the caller's
                // withoutActuallyEscaping check never observes a live capture.
                if let body = box.body {
                    box.body = nil
                    box.result = Result(catching: body)
                }
                done.signal()
            }
            thread.stackSize = stackSize
            thread.name = "kswiftk.large-stack"
            thread.start()
            done.wait()
            return try box.result!.get()
        }
    }
}
