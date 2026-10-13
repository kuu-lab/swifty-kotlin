import Dispatch

/// Executes a bounded number of large-stack workers. Every task is joined,
/// including after failures; results and the first error follow input order.
enum SemaPerFileExecutor {
    static func collect<Output: Sendable>(
        count: Int,
        jobs: Int,
        task: @escaping @Sendable (Int) throws -> Output
    ) throws -> [Output] {
        guard count > 0 else { return [] }
        let workers = min(count, max(1, jobs))
        let results = LockedIndexedResults<Result<Output, any Error>>(count: count)
        DispatchQueue.concurrentPerform(iterations: workers) { worker in
            let outcome = Result {
                try LargeStackExecutor.run {
                    for index in stride(from: worker, to: count, by: workers) {
                        results.store(Result { try task(index) }, at: index)
                    }
                }
            }
            if case let .failure(error) = outcome {
                for index in stride(from: worker, to: count, by: workers) {
                    results.store(.failure(error), at: index)
                }
            }
        }
        return try results.orderedResults().map { try $0.get() }
    }
}
