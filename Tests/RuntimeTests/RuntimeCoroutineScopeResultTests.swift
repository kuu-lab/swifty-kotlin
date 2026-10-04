import Dispatch
import Foundation
@testable import Runtime
import Testing

// MARK: - C-callable helpers for coroutineScope { async { ... } } result tests

private let coroutineScopeSumFunctionID = 9500
private let coroutineScopeAsync10FunctionID = 9501
private let coroutineScopeAsync20FunctionID = 9502

@_cdecl("runtime_test_coroutine_scope_async10")
func runtime_test_coroutine_scope_async10(_ continuation: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    return kk_coroutine_state_exit(continuation, 10)
}

@_cdecl("runtime_test_coroutine_scope_async20")
func runtime_test_coroutine_scope_async20(_ continuation: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    return kk_coroutine_state_exit(continuation, 20)
}

/// Deterministic runtime-level regression for `coroutineScope { async { 10 }; async { 20 } }`.
/// Uses the public C ABI for scope/async/await, mirroring the Kotlin diff case
/// `Scripts/diff_cases/coroutine_scope.kt` without relying on the compiler or JVM.
@_cdecl("runtime_test_coroutine_scope_sum")
func runtime_test_coroutine_scope_sum(_ continuation: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    let scope = kk_coroutine_scope_new()

    let entry10 = unsafeBitCast(
        runtime_test_coroutine_scope_async10 as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int,
        to: Int.self
    )
    let entry20 = unsafeBitCast(
        runtime_test_coroutine_scope_async20 as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int,
        to: Int.self
    )

    let deferred10 = kk_kxmini_async(entry10, coroutineScopeAsync10FunctionID)
    let deferred20 = kk_kxmini_async(entry20, coroutineScopeAsync20FunctionID)

    // Use the blocking await path (continuation == 0) so the test entry point
    // stays a simple synchronous suspend function and we still exercise the
    // scope -> async -> await result flow end-to-end.
    let a = kk_kxmini_async_await(deferred10, 0)
    let b = kk_kxmini_async_await(deferred20, 0)

    let failure = kk_coroutine_scope_wait(scope)
    guard failure == runtimeNullSentinelInt else {
        outThrown?.pointee = failure
        return kk_coroutine_state_exit(continuation, 0)
    }

    outThrown?.pointee = 0
    return kk_coroutine_state_exit(continuation, a + b)
}

// MARK: - Tests

@Suite("Runtime coroutineScope async result ordering")
struct RuntimeCoroutineScopeResultTests {
    @Test("coroutineScope { async { 10 }; async { 20 } } returns 30")
    func coroutineScopeAsyncSumReturns30() {
        typealias SuspendEntry = @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int
        let entryRaw = unsafeBitCast(
            runtime_test_coroutine_scope_sum as SuspendEntry,
            to: Int.self
        )
        var thrown = 0
        let result = kk_kxmini_run_blocking(entryRaw, coroutineScopeSumFunctionID, &thrown)
        #expect(thrown == 0, "coroutineScope must not fail")
        #expect(result == 30, "async results must be collected in order: 10 + 20 = 30")
    }
}
