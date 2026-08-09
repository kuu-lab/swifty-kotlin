import Foundation
@testable import Runtime
import Testing

/// Regression coverage for stale coroutine handle resolution: continuation /
/// scope / job / task handles used to be resolved with an unchecked cast, so a
/// handle whose object had already been released either read dangling memory or
/// resolved to whatever object later reused the address.
@Suite("Runtime live coroutine handles")
struct RuntimeLiveHandleRegistryTests {
    @Test("a released continuation handle no longer resolves")
    func releasedContinuationDoesNotResolve() {
        let continuation = kk_coroutine_continuation_new(7)
        #expect(runtimeContinuationState(from: continuation) != nil)

        _ = kk_coroutine_state_exit(continuation, 0)

        #expect(runtimeContinuationState(from: continuation) == nil)
    }

    @Test("released continuation handles never resolve to a freed state")
    func releasedContinuationsNeverResolveAfterFree() {
        // Repeated allocate/release cycles reuse addresses aggressively; a stale
        // handle must never resolve while its object is gone.
        var stale: [Int] = []
        for _ in 0..<256 {
            let continuation = kk_coroutine_continuation_new(1)
            _ = kk_coroutine_launcher_arg_set(continuation, 0, 111)
            _ = kk_coroutine_state_exit(continuation, 0)
            for handle in stale {
                // Either freed (nil) or recycled into a live state, but never a
                // resolution of deallocated memory.
                if let state = runtimeContinuationState(from: handle) {
                    #expect(state.launcherArgs[0] == nil || state.launcherArgs[0] == 111)
                }
            }
            stale.append(continuation)
        }
    }

    @Test("a continuation kept alive after state exit still resolves")
    func continuationAliveAfterExitStillResolves() {
        let raw = kk_coroutine_continuation_new(3)
        // Mirrors the suspend-entry loop, which keeps using its `contState`
        // after `kk_coroutine_state_exit` dropped the runtime's own reference.
        let state = runtimeContinuationState(from: raw)
        #expect(state != nil)
        _ = kk_coroutine_state_exit(raw, 0)
        #expect(runtimeContinuationState(from: raw) === state)
    }

    @Test("scope, job and task handles resolve only while live")
    func coroutineHandlesResolveOnlyWhileLive() {
        var scopeRaw = 0
        var jobRaw = 0
        var taskRaw = 0
        do {
            let scope = RuntimeCoroutineScope()
            let job = RuntimeJobHandle()
            let task = RuntimeAsyncTask()
            scopeRaw = Int(bitPattern: Unmanaged.passUnretained(scope).toOpaque())
            jobRaw = Int(bitPattern: Unmanaged.passUnretained(job).toOpaque())
            taskRaw = Int(bitPattern: Unmanaged.passUnretained(task).toOpaque())
            #expect(runtimeCoroutineScope(from: scopeRaw) === scope)
            #expect(runtimeJobHandle(from: jobRaw) === job)
            #expect(runtimeAsyncTask(from: taskRaw) === task)
        }
        #expect(runtimeCoroutineScope(from: scopeRaw) == nil)
        #expect(runtimeJobHandle(from: jobRaw) == nil)
        #expect(runtimeAsyncTask(from: taskRaw) == nil)
    }

    @Test("handles of a different live type do not resolve")
    func mismatchedTypeDoesNotResolve() {
        let scope = RuntimeCoroutineScope()
        let raw = Int(bitPattern: Unmanaged.passUnretained(scope).toOpaque())
        #expect(runtimeContinuationState(from: raw) == nil)
        #expect(runtimeJobHandle(from: raw) == nil)
        #expect(runtimeAsyncTask(from: raw) == nil)
        #expect(runtimeCoroutineScope(from: raw) === scope)
    }

    @Test("zero and unmapped handles resolve to nil")
    func invalidHandlesResolveToNil() {
        #expect(runtimeContinuationState(from: 0) == nil)
        #expect(runtimeCoroutineScope(from: 0) == nil)
        #expect(runtimeJobHandle(from: 0) == nil)
        #expect(runtimeAsyncTask(from: 0) == nil)
    }
}
