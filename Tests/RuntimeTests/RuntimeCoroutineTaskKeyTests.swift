import Dispatch
import Foundation
@testable import Runtime
import Testing

/// Regression coverage for the coroutine task-key aliasing race: task keys used
/// to be `ObjectIdentifier`s of a per-invocation token object, so the allocator
/// reusing a freed token's address aliased two unrelated suspend-entry-loop
/// invocations and made `RuntimeContinuationState.current` /
/// `RuntimeCoroutineScope.current` resolve to another coroutine's state.
@Suite("Runtime coroutine task keys")
struct RuntimeCoroutineTaskKeyTests {
    @Test("installFreshKey never reuses a key across install/remove cycles")
    func freshKeysAreUnique() {
        var seen = Set<RuntimeTaskKey>()
        for _ in 0..<1000 {
            let key = RuntimeCoroutineScopeTaskKey.installFreshKey()
            #expect(seen.insert(key).inserted)
            RuntimeCoroutineScopeTaskKey.removeKey()
        }
    }

    @Test("state installed for a retired task key is not visible to a later task")
    func retiredKeyDoesNotAliasLaterTask() {
        let state = RuntimeContinuationState(functionID: 1)
        let retiredKey = RuntimeCoroutineScopeTaskKey.installFreshKey()
        RuntimeContinuationState.installState(state, forTask: retiredKey)
        // Mirrors the async path of `runSuspendEntryLoopWithContinuation`: the
        // thread drops its key while the map entry stays alive for the
        // resume-continuation chain.
        RuntimeCoroutineScopeTaskKey.removeKey()

        for _ in 0..<1000 {
            _ = RuntimeCoroutineScopeTaskKey.installFreshKey()
            #expect(RuntimeContinuationState.current == nil)
            RuntimeCoroutineScopeTaskKey.removeKey()
        }

        RuntimeContinuationState.removeState(forTask: retiredKey)
    }

    @Test("keys are unique across threads")
    func keysAreUniqueAcrossThreads() {
        let lock = NSLock()
        nonisolated(unsafe) var seen = Set<RuntimeTaskKey>()
        nonisolated(unsafe) var duplicates = 0
        DispatchQueue.concurrentPerform(iterations: 64) { _ in
            for _ in 0..<50 {
                let key = RuntimeCoroutineScopeTaskKey.installFreshKey()
                lock.lock()
                if !seen.insert(key).inserted { duplicates += 1 }
                lock.unlock()
                RuntimeCoroutineScopeTaskKey.removeKey()
            }
        }
        #expect(duplicates == 0)
    }
}
