@testable import Runtime
import XCTest

// STDLIB-257: Regression tests for precondition lazy message failure path distinction.
//
// When require(false) { ... } or check(false) { ... } is called and the lazy message
// lambda itself throws, the runtime must still report the precondition failure
// (IllegalArgumentException / IllegalStateException) as the primary exception, with
// the lambda's exception attached as the cause.

// A closure thunk that returns a string message successfully.
private let lazyMessageReturnsString: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { _, outThrown in
    outThrown?.pointee = 0
    // Allocate a runtime string "custom message"
    let message = "custom message"
    return message.withCString { cstr in
        cstr.withMemoryRebound(to: UInt8.self, capacity: message.utf8.count) { pointer in
            Int(bitPattern: kk_string_from_utf8(pointer, Int32(message.utf8.count)))
        }
    }
}

// A closure thunk that throws an exception during evaluation.
private let lazyMessageThrows: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { _, outThrown in
    outThrown?.pointee = runtimeAllocateThrowable(message: "LazyEvalError: lambda threw")
    return 0
}

final class RuntimePreconditionLazyTests: IsolatedRuntimeXCTestCase {

    // MARK: - kk_require (non-lazy)

    func testRequirePassingConditionDoesNotThrow() {
        var outThrown = 0
        _ = kk_require(1, &outThrown)
        XCTAssertEqual(outThrown, 0, "require(true) should not throw")
    }

    func testRequireFailingConditionThrowsIllegalArgument() {
        var outThrown = 0
        _ = kk_require(0, &outThrown)
        XCTAssertNotEqual(outThrown, 0, "require(false) should throw")
        let box = throwableBox(from: outThrown)
        XCTAssertNotNil(box)
        XCTAssertTrue(box?.message.contains("IllegalArgumentException") == true)
    }

    // MARK: - kk_check (non-lazy)

    func testCheckPassingConditionDoesNotThrow() {
        var outThrown = 0
        _ = kk_check(1, &outThrown)
        XCTAssertEqual(outThrown, 0, "check(true) should not throw")
    }

    func testCheckFailingConditionThrowsIllegalState() {
        var outThrown = 0
        _ = kk_check(0, &outThrown)
        XCTAssertNotEqual(outThrown, 0, "check(false) should throw")
        let box = throwableBox(from: outThrown)
        XCTAssertNotNil(box)
        XCTAssertTrue(box?.message.contains("IllegalStateException") == true)
    }

    // MARK: - kk_require_lazy: condition passes

    func testRequireLazyPassingConditionDoesNotThrow() {
        var outThrown = 0
        let fnPtr = unsafeBitCast(lazyMessageReturnsString, to: Int.self)
        _ = kk_require_lazy(1, fnPtr, 0, &outThrown)
        XCTAssertEqual(outThrown, 0, "require(true) { ... } should not throw")
    }

    // MARK: - kk_require_lazy: condition fails, lazy message succeeds

    func testRequireLazyFailsWithCustomMessage() {
        var outThrown = 0
        let fnPtr = unsafeBitCast(lazyMessageReturnsString, to: Int.self)
        _ = kk_require_lazy(0, fnPtr, 0, &outThrown)
        XCTAssertNotEqual(outThrown, 0, "require(false) { ... } should throw")
        let box = throwableBox(from: outThrown)
        XCTAssertNotNil(box)
        XCTAssertTrue(
            box?.message.contains("custom message") == true,
            "Should contain the lazy message, got: \(box?.message ?? "nil")"
        )
    }

    // MARK: - kk_require_lazy: condition fails, lazy message throws (STDLIB-257 core case)

    func testRequireLazyMessageThrowsReportsPreconditionFailureWithCause() {
        var outThrown = 0
        let fnPtr = unsafeBitCast(lazyMessageThrows, to: Int.self)
        _ = kk_require_lazy(0, fnPtr, 0, &outThrown)

        XCTAssertNotEqual(outThrown, 0, "Should throw when condition is false")

        // The primary exception must be the precondition failure, not the lambda's exception.
        let box = throwableBox(from: outThrown)
        XCTAssertNotNil(box, "outThrown should be a RuntimeThrowableBox")
        XCTAssertTrue(
            box?.message.contains("IllegalArgumentException") == true,
            "Primary exception must be IllegalArgumentException, got: \(box?.message ?? "nil")"
        )

        // The lambda's exception must be attached as the cause.
        XCTAssertNotEqual(box?.cause, 0, "cause must be set when lazy message threw")
        let causeBox = throwableBox(from: box?.cause ?? 0)
        XCTAssertNotNil(causeBox, "cause should be a RuntimeThrowableBox")
        XCTAssertTrue(
            causeBox?.message.contains("LazyEvalError") == true,
            "cause should contain the lambda's exception message, got: \(causeBox?.message ?? "nil")"
        )
    }

    // MARK: - kk_check_lazy: condition fails, lazy message throws (STDLIB-257 core case)

    func testCheckLazyMessageThrowsReportsPreconditionFailureWithCause() {
        var outThrown = 0
        let fnPtr = unsafeBitCast(lazyMessageThrows, to: Int.self)
        _ = kk_check_lazy(0, fnPtr, 0, &outThrown)

        XCTAssertNotEqual(outThrown, 0, "Should throw when condition is false")

        // The primary exception must be the precondition failure, not the lambda's exception.
        let box = throwableBox(from: outThrown)
        XCTAssertNotNil(box, "outThrown should be a RuntimeThrowableBox")
        XCTAssertTrue(
            box?.message.contains("IllegalStateException") == true,
            "Primary exception must be IllegalStateException, got: \(box?.message ?? "nil")"
        )

        // The lambda's exception must be attached as the cause.
        XCTAssertNotEqual(box?.cause, 0, "cause must be set when lazy message threw")
        let causeBox = throwableBox(from: box?.cause ?? 0)
        XCTAssertNotNil(causeBox, "cause should be a RuntimeThrowableBox")
        XCTAssertTrue(
            causeBox?.message.contains("LazyEvalError") == true,
            "cause should contain the lambda's exception message, got: \(causeBox?.message ?? "nil")"
        )
    }

    // MARK: - kk_require_lazy: no lambda provided (fnPtr == 0) falls back to default

    func testRequireLazyNoLambdaUsesDefaultMessage() {
        var outThrown = 0
        _ = kk_require_lazy(0, 0, 0, &outThrown)
        XCTAssertNotEqual(outThrown, 0)
        let box = throwableBox(from: outThrown)
        XCTAssertTrue(
            box?.message.contains("IllegalArgumentException") == true,
            "Should use default IllegalArgumentException message"
        )
        XCTAssertEqual(box?.cause, 0, "No cause when lambda is absent")
    }

    // MARK: - kk_check_lazy: no lambda provided (fnPtr == 0) falls back to default

    func testCheckLazyNoLambdaUsesDefaultMessage() {
        var outThrown = 0
        _ = kk_check_lazy(0, 0, 0, &outThrown)
        XCTAssertNotEqual(outThrown, 0)
        let box = throwableBox(from: outThrown)
        XCTAssertTrue(
            box?.message.contains("IllegalStateException") == true,
            "Should use default IllegalStateException message"
        )
        XCTAssertEqual(box?.cause, 0, "No cause when lambda is absent")
    }

    // MARK: - kk_check_lazy: condition passes with lazy message

    func testCheckLazyPassingConditionDoesNotThrow() {
        var outThrown = 0
        let fnPtr = unsafeBitCast(lazyMessageReturnsString, to: Int.self)
        _ = kk_check_lazy(1, fnPtr, 0, &outThrown)
        XCTAssertEqual(outThrown, 0, "check(true) { ... } should not throw")
    }

    // MARK: - kk_check_lazy: condition fails, lazy message succeeds

    func testCheckLazyFailsWithCustomMessage() {
        var outThrown = 0
        let fnPtr = unsafeBitCast(lazyMessageReturnsString, to: Int.self)
        _ = kk_check_lazy(0, fnPtr, 0, &outThrown)
        XCTAssertNotEqual(outThrown, 0, "check(false) { ... } should throw")
        let box = throwableBox(from: outThrown)
        XCTAssertNotNil(box)
        XCTAssertTrue(
            box?.message.contains("custom message") == true,
            "Should contain the lazy message, got: \(box?.message ?? "nil")"
        )
    }

    // MARK: - Helpers

    private func throwableBox(from handle: Int) -> RuntimeThrowableBox? {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
            return nil
        }
        return tryCast(ptr, to: RuntimeThrowableBox.self)
    }
}
