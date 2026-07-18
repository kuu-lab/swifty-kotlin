#if canImport(Testing)
import Testing
@testable import Runtime

@_cdecl("runtime_runcatching_success_lambda")
private func runtime_runcatching_success_lambda(
    _: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    return 99
}

@_cdecl("runtime_runcatching_failure_lambda")
private func runtime_runcatching_failure_lambda(
    _: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = runtimeAllocateThrowable(message: "runcatching failure")
    return 0
}

@Suite(.serialized)
struct RuntimeRunCatchingTests {
    init() {
        kk_runtime_force_reset()
    }

    @Test
    func testRunCatchingWrapsSuccessAsResult() {
        defer {
            kk_runtime_force_reset()
        }

        var thrown = 0
        let fn = unsafeBitCast(runtime_runcatching_success_lambda as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int, to: Int.self)
        let resultRaw = runtimeResultRunCatching(fn, 0, &thrown)

        #expect(thrown == 0)
        #expect(runtimeResultSuccessFlag(resultRaw) == 1)
        #expect(runtimeResultFailureFlag(resultRaw) == 0)
        #expect(runtimeResultValueOrNull(resultRaw) == 99)
    }

    @Test
    func testRunCatchingWrapsFailureWithoutThrowingOutward() {
        defer {
            kk_runtime_force_reset()
        }

        var thrown = 0
        let fn = unsafeBitCast(runtime_runcatching_failure_lambda as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int, to: Int.self)
        let resultRaw = runtimeResultRunCatching(fn, 0, &thrown)

        #expect(thrown == 0)
        #expect(runtimeResultSuccessFlag(resultRaw) == 0)
        #expect(runtimeResultFailureFlag(resultRaw) == 1)
        #expect(runtimeResultExceptionOrNull(resultRaw) != runtimeNullSentinelInt)
    }
}
#endif
