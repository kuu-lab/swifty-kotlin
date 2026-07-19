import Foundation
@testable import Runtime
import Testing

private let lazyMessageReturnsString: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { _, outThrown in
    outThrown?.pointee = 0
    let message = "custom assert message"
    return message.withCString { cstr in
        cstr.withMemoryRebound(to: UInt8.self, capacity: message.utf8.count) { pointer in
            Int(bitPattern: kk_string_from_utf8(pointer, Int32(message.utf8.count)))
        }
    }
}

private let assertLazyMessageEvaluationsLock = NSLock()
nonisolated(unsafe) private var _assertLazyMessageEvaluations = 0

nonisolated(unsafe) private var assertLazyMessageEvaluations: Int {
    get {
        assertLazyMessageEvaluationsLock.lock()
        defer { assertLazyMessageEvaluationsLock.unlock() }
        return _assertLazyMessageEvaluations
    }
    set {
        assertLazyMessageEvaluationsLock.lock()
        defer { assertLazyMessageEvaluationsLock.unlock() }
        _assertLazyMessageEvaluations = newValue
    }
}

private let lazyMessageCountsEvaluation: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { _, outThrown in
    outThrown?.pointee = 0
    assertLazyMessageEvaluations += 1
    return runtimeNullSentinelInt
}

private func fnPtrInt(_ fn: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int) -> Int {
    Int(bitPattern: unsafeBitCast(fn, to: UnsafeRawPointer.self))
}

private func resetRuntimeAssertTestState() {
    assertLazyMessageEvaluations = 0
    _ = kk_assertions_reset()
}

@Suite(.runtimeIsolation(.gcOnly, resetAdditionalState: resetRuntimeAssertTestState))
struct RuntimeAssertTests {
    // MARK: - Eager assert

    @Test func assertTrueDoesNotThrow() {
        var thrown = 0
        _ = kk_precondition_assert(1, &thrown)
        #expect(thrown == 0, "assert(true) should not throw")
    }

    @Test func assertFalseThrows() {
        var thrown = 0
        _ = kk_precondition_assert(0, &thrown)
        #expect(thrown != 0, "assert(false) should throw")
    }

    @Test func assertFalseThrowsAssertionError() throws {
        var thrown = 0
        _ = kk_precondition_assert(0, &thrown)
        #expect(thrown != 0)
        let pointer = try #require(UnsafeMutableRawPointer(bitPattern: thrown))
        let throwable = try #require(tryCast(pointer, to: RuntimeThrowableBox.self))
        #expect(
            throwable.renderedMessage.hasPrefix("AssertionError:"),
            "Expected rendered message to start with 'AssertionError:', got: \(throwable.renderedMessage)"
        )
        #expect(
            throwable.renderedMessage.contains("Assertion failed"),
            "Expected rendered message to contain 'Assertion failed', got: \(throwable.renderedMessage)"
        )
    }

    // MARK: - Lazy assert (no lambda — fallback to default message)

    @Test func assertLazyTrueDoesNotThrow() {
        var thrown = 0
        _ = kk_precondition_assert_lazy(1, 0, 0, &thrown)
        #expect(thrown == 0, "assert(true) { ... } should not throw when condition is true")
    }

    @Test func assertLazyFalseNoLambdaThrowsDefaultMessage() throws {
        var thrown = 0
        _ = kk_precondition_assert_lazy(0, 0, 0, &thrown)
        #expect(thrown != 0, "assert(false) with no lambda should throw")
        let pointer = try #require(UnsafeMutableRawPointer(bitPattern: thrown))
        let throwable = try #require(tryCast(pointer, to: RuntimeThrowableBox.self))
        #expect(
            throwable.renderedMessage.hasPrefix("AssertionError:"),
            "Expected default rendered message to start with 'AssertionError:', got: \(throwable.renderedMessage)"
        )
    }

    @Test func assertLazyFalseUsesAssertionErrorPrefixForCustomMessage() throws {
        var thrown = 0
        _ = kk_precondition_assert_lazy(0, fnPtrInt(lazyMessageReturnsString), 0, &thrown)
        #expect(thrown != 0, "assert(false) with lambda should throw")
        let pointer = try #require(UnsafeMutableRawPointer(bitPattern: thrown))
        let throwable = try #require(tryCast(pointer, to: RuntimeThrowableBox.self))
        #expect(throwable.renderedMessage == "AssertionError: custom assert message")
    }

    @Test func assertionsCanBeDisabledAtRuntime() {
        _ = kk_assertions_set_enabled(0)
        #expect(kk_assertions_enabled() == 0)

        var thrown = 0
        _ = kk_precondition_assert(0, &thrown)

        #expect(thrown == 0, "disabled assert(false) should not throw")
    }

    @Test func disabledAssertionsDoNotEvaluateLazyMessage() {
        _ = kk_assertions_set_enabled(0)
        #expect(kk_assertions_enabled() == 0)

        var thrown = 0
        _ = kk_precondition_assert_lazy(0, fnPtrInt(lazyMessageCountsEvaluation), 0, &thrown)

        #expect(thrown == 0, "disabled assert(false) { ... } should not throw")
        #expect(assertLazyMessageEvaluations == 0, "lazy message must not be evaluated when assertions are disabled")
    }

    @Test func assertionsCanBeReEnabledAtRuntime() {
        _ = kk_assertions_set_enabled(0)
        _ = kk_assertions_set_enabled(1)
        #expect(kk_assertions_enabled() == 1)

        var thrown = 0
        _ = kk_precondition_assert(0, &thrown)

        #expect(thrown != 0, "re-enabled assert(false) should throw again")
    }
}
