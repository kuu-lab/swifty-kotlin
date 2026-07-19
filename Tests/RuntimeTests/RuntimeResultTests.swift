#if canImport(Testing)
@testable import Runtime
import Testing

@_cdecl("runtime_result_success_lambda")
private func runtime_result_success_lambda(
    _: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    return 42
}

@_cdecl("runtime_result_failure_lambda")
private func runtime_result_failure_lambda(
    _: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = runtimeAllocateThrowable(message: "boom")
    return 0
}

@Suite
struct RuntimeResultTests {
    @Test
    func testResultSuccessStateAndGetOrThrow() {
        var thrown = 0
        let fn = unsafeBitCast(runtime_result_success_lambda as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int, to: Int.self)
        let resultRaw = runtimeResultRunCatching(fn, 0, &thrown)

        #expect(thrown == 0)
        #expect(runtimeResultSuccessFlag(resultRaw) == 1)
        #expect(runtimeResultFailureFlag(resultRaw) == 0)
        #expect(runtimeResultGetOrThrow(resultRaw, &thrown) == 42)
        #expect(thrown == 0)
    }

    @Test
    func testResultFailureStateAndGetOrThrowRethrows() {
        var thrown = 0
        let fn = unsafeBitCast(runtime_result_failure_lambda as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int, to: Int.self)
        let resultRaw = runtimeResultRunCatching(fn, 0, &thrown)

        #expect(thrown == 0)
        #expect(runtimeResultSuccessFlag(resultRaw) == 0)
        #expect(runtimeResultFailureFlag(resultRaw) == 1)
        _ = runtimeResultGetOrThrow(resultRaw, &thrown)
        #expect(thrown != 0)
    }

    @Test
    func testResultComponentsExposeValueAndExceptionSlots() {
        var thrown = 0
        let successFn = unsafeBitCast(runtime_result_success_lambda as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int, to: Int.self)
        let failureFn = unsafeBitCast(runtime_result_failure_lambda as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int, to: Int.self)

        let successRaw = runtimeResultRunCatching(successFn, 0, &thrown)
        #expect(thrown == 0)
        #expect(runtimeResultValueOrNull(successRaw) == 42)
        #expect(runtimeResultExceptionOrNull(successRaw) == runtimeNullSentinelInt)

        let failureRaw = runtimeResultRunCatching(failureFn, 0, &thrown)
        #expect(thrown == 0)
        #expect(runtimeResultValueOrNull(failureRaw) == runtimeNullSentinelInt)
        #expect(runtimeResultExceptionOrNull(failureRaw) != runtimeNullSentinelInt)

        #expect(runtimeResultValueOrNull(runtimeNullSentinelInt) == runtimeNullSentinelInt)
        #expect(runtimeResultExceptionOrNull(runtimeNullSentinelInt) == runtimeNullSentinelInt)
        #expect(runtimeResultSuccessFlag(runtimeNullSentinelInt) == 0)
        #expect(runtimeResultFailureFlag(runtimeNullSentinelInt) == 1)
        #expect(runtimeResultValueOrNull(runtimeNullSentinelInt) == runtimeNullSentinelInt)
        #expect(runtimeResultValueOrDefault(runtimeNullSentinelInt, 7) == 7)
    }
}
#endif
