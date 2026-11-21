import Dispatch
import Foundation

/// Every task is joined, including after failures; results and the first error
/// follow input order. With `cancelOnFirstError`, workers skip indices once
/// another index has failed; each worker's first index always runs, and the
/// lowest-index failure among executed tasks is still thrown.
enum SemaPerFileExecutor {
    private struct CancelledIndex: Error {}

    private final class FailureFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var flag = false
        var isSet: Bool {
            lock.lock()
            defer { lock.unlock() }
            return flag
        }
        func set() {
            lock.lock()
            flag = true
            lock.unlock()
        }
    }

    static func collect<Output: Sendable>(
        count: Int,
        jobs: Int,
        cancelOnFirstError: Bool = false,
        task: @escaping @Sendable (Int) throws -> Output
    ) throws -> [Output] {
        guard count > 0 else { return [] }
        let workers = min(count, max(1, jobs))
        let results = LockedIndexedResults<Result<Output, any Error>>(count: count)
        let failed = cancelOnFirstError ? FailureFlag() : nil
        DispatchQueue.concurrentPerform(iterations: workers) { worker in
            let outcome = Result {
                try LargeStackExecutor.run {
                    var firstIndex = true
                    for index in stride(from: worker, to: count, by: workers) {
                        let cancelled = !firstIndex && failed?.isSet == true
                        firstIndex = false
                        if cancelled {
                            results.store(.failure(CancelledIndex()), at: index)
                            continue
                        }
                        let result = Result { try task(index) }
                        if case .failure = result { failed?.set() }
                        results.store(result, at: index)
                    }
                }
            }
            if case let .failure(error) = outcome {
                failed?.set()
                for index in stride(from: worker, to: count, by: workers) {
                    results.store(.failure(error), at: index)
                }
            }
        }
        let ordered = results.orderedResults()
        if cancelOnFirstError {
            for result in ordered {
                if case let .failure(error) = result, !(error is CancelledIndex) {
                    throw error
                }
            }
        }
        return try ordered.map { try $0.get() }
    }
}
