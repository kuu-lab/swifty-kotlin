import Foundation

/// Per-thread stack of the jobs whose coroutine bursts are currently
/// executing on that thread.
///
/// Every suspend-entry burst (`runSuspendEntryLoopWithContinuation`'s loop
/// body) pushes its job for the duration of the burst and pops it on exit.
/// `RuntimeJobHandle.join()` consults this to detect a join that can never
/// be satisfied by waiting: when the joined job's own body is an ancestor
/// frame on the calling thread, the job cannot reach a terminal state until
/// this very stack unwinds past the join — parking the thread or draining
/// the event loop would deadlock (KUU-4477).
///
/// The classic shape is a synchronous nested wait: a `flow { }` emitter
/// invoked inside a `produce` body parks its caller in
/// `RuntimeEventLoop.run(until:)`, and a `coroutineScope` child-wait resumed
/// underneath that drain then tries to join the very produce job whose burst
/// owns the parked emitter.
final class RuntimeBurstJobStack: @unchecked Sendable {
    static let shared = RuntimeBurstJobStack()

    private static let pthreadKey: pthread_key_t = {
        var key = pthread_key_t()
        pthread_key_create(&key) { ptr in
            Unmanaged<RuntimeBurstJobStack>.fromOpaque(ptr).release()
        }
        return key
    }()

    private let lock = NSLock()
    private var jobs: [RuntimeJobHandle?] = []

    /// The calling thread's stack, created on first burst.
    static var current: RuntimeBurstJobStack {
        if let existing = pthread_getspecific(pthreadKey) {
            return Unmanaged<RuntimeBurstJobStack>.fromOpaque(existing).takeUnretainedValue()
        }
        let stack = RuntimeBurstJobStack()
        pthread_setspecific(pthreadKey, Unmanaged.passRetained(stack).toOpaque())
        return stack
    }

    /// The calling thread's stack if a burst has already run on it, without
    /// allocating one for threads that only ever join.
    private static var existing: RuntimeBurstJobStack? {
        guard let raw = pthread_getspecific(pthreadKey) else { return nil }
        return Unmanaged<RuntimeBurstJobStack>.fromOpaque(raw).takeUnretainedValue()
    }

    func push(_ job: RuntimeJobHandle?) {
        lock.lock()
        jobs.append(job)
        lock.unlock()
    }

    func pop() {
        lock.lock()
        _ = jobs.popLast()
        lock.unlock()
    }

    /// True when `job` has a burst executing on the calling thread, meaning
    /// its completion depends on the current stack unwinding and no amount of
    /// event-loop draining can finish it.
    static func isBurstingOnCurrentThread(_ job: RuntimeJobHandle) -> Bool {
        guard let stack = existing else { return false }
        return stack.contains(job)
    }

    private func contains(_ job: RuntimeJobHandle) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return jobs.contains { $0 === job }
    }
}
