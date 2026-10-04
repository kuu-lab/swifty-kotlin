import Foundation

/// A cancellable task returned by an LSP debounce scheduler.
protocol LSPScheduledTask: AnyObject, Sendable {
    func cancel()
}

/// Schedules work after a delay. The abstraction keeps debounce tests
/// deterministic without relying on wall-clock sleeps.
protocol LSPDebounceScheduler: AnyObject, Sendable {
    func schedule(
        after delay: DispatchTimeInterval,
        operation: @escaping @Sendable () -> Void
    ) -> any LSPScheduledTask
}

/// Production scheduler backed by a serial GCD queue.
final class DispatchLSPDebounceScheduler: LSPDebounceScheduler, @unchecked Sendable {
    private let queue: DispatchQueue

    init(queue: DispatchQueue = DispatchQueue(
        label: "kswiftk.lsp.debounce",
        qos: .userInitiated
    )) {
        self.queue = queue
    }

    func schedule(
        after delay: DispatchTimeInterval,
        operation: @escaping @Sendable () -> Void
    ) -> any LSPScheduledTask {
        let workItem = DispatchWorkItem(block: operation)
        queue.asyncAfter(deadline: .now() + delay, execute: workItem)
        return DispatchLSPScheduledTask(workItem: workItem)
    }
}

private final class DispatchLSPScheduledTask: LSPScheduledTask, @unchecked Sendable {
    private let workItem: DispatchWorkItem

    init(workItem: DispatchWorkItem) {
        self.workItem = workItem
    }

    func cancel() {
        workItem.cancel()
    }
}
