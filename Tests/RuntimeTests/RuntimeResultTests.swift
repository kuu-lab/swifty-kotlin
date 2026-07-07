@testable import Runtime
import XCTest

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

@_cdecl("runtime_result_transform_lambda")
private func runtime_result_transform_lambda(
    _: Int,
    _: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    return 1
}

final class RuntimeResultTests: XCTestCase {
    override func setUp() {
        super.setUp()
        kk_runtime_force_reset()
    }

    override func tearDown() {
        kk_runtime_force_reset()
        super.tearDown()
    }

    func testResultSuccessStateAndGetOrThrow() {
        var thrown = 0
        let fn = unsafeBitCast(runtime_result_success_lambda as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int, to: Int.self)
        let resultRaw = runtimeResultRunCatching(fn, 0, &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(runtimeResultSuccessFlag(resultRaw), 1)
        XCTAssertEqual(runtimeResultFailureFlag(resultRaw), 0)
        XCTAssertEqual(runtimeResultGetOrThrow(resultRaw, &thrown), 42)
        XCTAssertEqual(thrown, 0)
    }

    func testRunCatchingAcceptsBoxedFunctionValue() {
        var thrown = 0
        let fn = unsafeBitCast(runtime_result_success_lambda as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int, to: Int.self)
        let boxedFn = kk_function_create_0(fn, 0, &thrown)
        XCTAssertEqual(thrown, 0)

        let resultRaw = runtimeResultRunCatching(boxedFn, 0, &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(runtimeResultSuccessFlag(resultRaw), 1)
        XCTAssertEqual(runtimeResultGetOrThrow(resultRaw, &thrown), 42)
        XCTAssertEqual(thrown, 0)
    }

    func testResultFailureStateAndGetOrThrowRethrows() {
        var thrown = 0
        let fn = unsafeBitCast(runtime_result_failure_lambda as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int, to: Int.self)
        let resultRaw = runtimeResultRunCatching(fn, 0, &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(runtimeResultSuccessFlag(resultRaw), 0)
        XCTAssertEqual(runtimeResultFailureFlag(resultRaw), 1)
        _ = runtimeResultGetOrThrow(resultRaw, &thrown)
        XCTAssertNotEqual(thrown, 0)
    }

    func testResultGetOrElseUsesFailureTransform() {
        var thrown = 0
        let failureFn = unsafeBitCast(runtime_result_failure_lambda as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int, to: Int.self)
        let transformFn = unsafeBitCast(runtime_result_transform_lambda as @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int, to: Int.self)

        let resultRaw = runtimeResultRunCatching(failureFn, 0, &thrown)
        XCTAssertEqual(thrown, 0)

        let fallbackValue = runtimeResultGetOrElse(resultRaw, transformFn, 0, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(fallbackValue, 1)
    }

    func testResultGetOrElseAcceptsBoxedFunctionValue() {
        var thrown = 0
        let failureFn = unsafeBitCast(runtime_result_failure_lambda as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int, to: Int.self)
        let transformFn = unsafeBitCast(runtime_result_transform_lambda as @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int, to: Int.self)
        let boxedTransform = kk_function_create_1(transformFn, 0, &thrown)
        XCTAssertEqual(thrown, 0)

        let resultRaw = runtimeResultRunCatching(failureFn, 0, &thrown)
        XCTAssertEqual(thrown, 0)

        let fallbackValue = runtimeResultGetOrElse(resultRaw, boxedTransform, 0, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(fallbackValue, 1)
    }
    func testResultComponentsExposeValueAndExceptionSlots() {
        var thrown = 0
        let successFn = unsafeBitCast(runtime_result_success_lambda as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int, to: Int.self)
        let failureFn = unsafeBitCast(runtime_result_failure_lambda as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int, to: Int.self)

        let successRaw = runtimeResultRunCatching(successFn, 0, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(runtimeResultValueOrNull(successRaw), 42)
        XCTAssertEqual(runtimeResultExceptionOrNull(successRaw), runtimeNullSentinelInt)

        let failureRaw = runtimeResultRunCatching(failureFn, 0, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(runtimeResultValueOrNull(failureRaw), runtimeNullSentinelInt)
        XCTAssertNotEqual(runtimeResultExceptionOrNull(failureRaw), runtimeNullSentinelInt)

        XCTAssertEqual(runtimeResultValueOrNull(runtimeNullSentinelInt), runtimeNullSentinelInt)
        XCTAssertEqual(runtimeResultExceptionOrNull(runtimeNullSentinelInt), runtimeNullSentinelInt)
        XCTAssertEqual(runtimeResultSuccessFlag(runtimeNullSentinelInt), 0)
        XCTAssertEqual(runtimeResultFailureFlag(runtimeNullSentinelInt), 1)
        XCTAssertEqual(runtimeResultValueOrNull(runtimeNullSentinelInt), runtimeNullSentinelInt)
        XCTAssertEqual(runtimeResultValueOrDefault(runtimeNullSentinelInt, 7), 7)
    }
}
