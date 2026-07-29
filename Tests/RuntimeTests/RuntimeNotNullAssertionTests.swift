#if canImport(Testing)
import Testing
@testable import Runtime
import Foundation

// STDLIB-ASSERT-ABI-001: Runtime entry points for checkNotNull / requireNotNull.
//
// Covers:
//  - kk_check_not_null: non-null passthrough, null throws IllegalStateException
//  - kk_require_not_null: non-null passthrough, null throws IllegalArgumentException
//  - kk_check_not_null_lazy: lazy message evaluated only on null
//  - kk_require_not_null_lazy: lazy message evaluated only on null
//  - Default message "Required value was null." for both variants
//  - Exception type discrimination (IllegalState vs IllegalArgument)

private func throwableBox(from handle: Int) -> RuntimeThrowableBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        return nil
    }
    return tryCast(ptr, to: RuntimeThrowableBox.self)
}

private func fnPtrInt(_ fn: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int) -> Int {
    Int(bitPattern: unsafeBitCast(fn, to: UnsafeRawPointer.self))
}

private func makeRuntimeString(_ value: String) -> Int {
    value.withCString { cstr in
        cstr.withMemoryRebound(to: UInt8.self, capacity: value.utf8.count) { pointer in
            Int(bitPattern: kk_string_from_utf8(pointer, Int32(value.utf8.count)))
        }
    }
}

private func makeNonNullValue() -> Int {
    // Allocate a simple string to use as a non-null opaque pointer value
    makeRuntimeString("hello")
}

// Lazy thunk counter for "not evaluated" tests
private let notNullLazyLock = NSLock()
nonisolated(unsafe) private var _notNullLazyCounter = 0
private var notNullLazyCounter: Int {
    get { notNullLazyLock.lock(); defer { notNullLazyLock.unlock() }; return _notNullLazyCounter }
    set { notNullLazyLock.lock(); defer { notNullLazyLock.unlock() }; _notNullLazyCounter = newValue }
}

private let notNullCountingThunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { _, outThrown in
    outThrown?.pointee = 0
    notNullLazyCounter += 1
    return runtimeNullSentinelInt
}

private let notNullStringThunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { _, outThrown in
    outThrown?.pointee = 0
    let msg = "custom-null-msg"
    return msg.withCString { cstr in
        cstr.withMemoryRebound(to: UInt8.self, capacity: msg.utf8.count) { ptr in
            Int(bitPattern: kk_string_from_utf8(ptr, Int32(msg.utf8.count)))
        }
    }
}

@Suite(.serialized)
struct RuntimeNotNullAssertionTests {

    init() {
        notNullLazyCounter = 0
    }

    // MARK: - kk_check_not_null: non-null passthrough

    @Test
    func testCheckNotNullPassthroughNonNull() {
        let value = makeNonNullValue()
        var thrown = 0
        let result = kk_check_not_null(value, &thrown)
        #expect(thrown == 0, "checkNotNull(nonNull) must not throw")
        #expect(result == value, "checkNotNull(nonNull) must return the value unchanged")
    }

    // MARK: - kk_check_not_null: null throws IllegalStateException

    @Test
    func testCheckNotNullThrowsIllegalStateOnNull() throws {
        var thrown = 0
        _ = kk_check_not_null(runtimeNullSentinelInt, &thrown)
        #expect(thrown != 0, "checkNotNull(null) must throw")
        let box = try #require(throwableBox(from: thrown))
        #expect(box.exceptionFQName == "kotlin.IllegalStateException",
                "checkNotNull must throw IllegalStateException on null")
        #expect(
            !runtimeThrowableBoxHasExactType(box, RuntimeIllegalArgumentExceptionBox.self),
            "checkNotNull must NOT throw IllegalArgumentException"
        )
    }

    @Test
    func testCheckNotNullDefaultMessage() throws {
        var thrown = 0
        _ = kk_check_not_null(runtimeNullSentinelInt, &thrown)
        let box = try #require(throwableBox(from: thrown))
        #expect(box.message == "Required value was null.",
                "checkNotNull default message must be \"Required value was null.\"")
    }

    // MARK: - kk_require_not_null: non-null passthrough

    @Test
    func testRequireNotNullPassthroughNonNull() {
        let value = makeNonNullValue()
        var thrown = 0
        let result = kk_require_not_null(value, &thrown)
        #expect(thrown == 0, "requireNotNull(nonNull) must not throw")
        #expect(result == value, "requireNotNull(nonNull) must return the value unchanged")
    }

    // MARK: - kk_require_not_null: null throws IllegalArgumentException

    @Test
    func testRequireNotNullThrowsIllegalArgumentOnNull() throws {
        var thrown = 0
        _ = kk_require_not_null(runtimeNullSentinelInt, &thrown)
        #expect(thrown != 0, "requireNotNull(null) must throw")
        let box = try #require(throwableBox(from: thrown))
        #expect(box.exceptionFQName == "kotlin.IllegalArgumentException",
                "requireNotNull must throw IllegalArgumentException on null")
        #expect(
            !runtimeThrowableBoxHasExactType(box, RuntimeIllegalStateExceptionBox.self),
            "requireNotNull must NOT throw IllegalStateException"
        )
    }

    @Test
    func testRequireNotNullDefaultMessage() throws {
        var thrown = 0
        _ = kk_require_not_null(runtimeNullSentinelInt, &thrown)
        let box = try #require(throwableBox(from: thrown))
        #expect(box.message == "Required value was null.",
                "requireNotNull default message must be \"Required value was null.\"")
    }

    // MARK: - Lazy variants: message NOT evaluated when non-null

    @Test
    func testCheckNotNullLazyNotEvaluatedWhenNonNull() {
        let value = makeNonNullValue()
        var thrown = 0
        let result = kk_check_not_null_lazy(value, fnPtrInt(notNullCountingThunk), 0, &thrown)
        #expect(thrown == 0, "checkNotNull(nonNull) { ... } must not throw")
        #expect(result == value, "checkNotNull(nonNull) must return the value unchanged")
        #expect(notNullLazyCounter == 0,
                "Lazy message lambda must NOT be evaluated when value is non-null")
    }

    @Test
    func testRequireNotNullLazyNotEvaluatedWhenNonNull() {
        let value = makeNonNullValue()
        var thrown = 0
        let result = kk_require_not_null_lazy(value, fnPtrInt(notNullCountingThunk), 0, &thrown)
        #expect(thrown == 0, "requireNotNull(nonNull) { ... } must not throw")
        #expect(result == value, "requireNotNull(nonNull) must return the value unchanged")
        #expect(notNullLazyCounter == 0,
                "Lazy message lambda must NOT be evaluated when value is non-null")
    }

    // MARK: - Lazy variants: message evaluated on null

    @Test
    func testCheckNotNullLazyEvaluatedOnNull() {
        var thrown = 0
        _ = kk_check_not_null_lazy(runtimeNullSentinelInt, fnPtrInt(notNullCountingThunk), 0, &thrown)
        #expect(thrown != 0, "checkNotNull(null) { ... } must throw")
        #expect(notNullLazyCounter == 1,
                "Lazy message lambda must be evaluated exactly once when value is null")
    }

    @Test
    func testRequireNotNullLazyEvaluatedOnNull() {
        var thrown = 0
        _ = kk_require_not_null_lazy(runtimeNullSentinelInt, fnPtrInt(notNullCountingThunk), 0, &thrown)
        #expect(thrown != 0, "requireNotNull(null) { ... } must throw")
        #expect(notNullLazyCounter == 1,
                "Lazy message lambda must be evaluated exactly once when value is null")
    }

    // MARK: - Lazy variants: custom string message included in exception

    @Test
    func testCheckNotNullLazyStringMessageIncluded() throws {
        var thrown = 0
        _ = kk_check_not_null_lazy(runtimeNullSentinelInt, fnPtrInt(notNullStringThunk), 0, &thrown)
        let box = try #require(throwableBox(from: thrown))
        #expect(box.message == "custom-null-msg",
                "checkNotNull lazy message must be included in IllegalStateException")
    }

    @Test
    func testRequireNotNullLazyStringMessageIncluded() throws {
        var thrown = 0
        _ = kk_require_not_null_lazy(runtimeNullSentinelInt, fnPtrInt(notNullStringThunk), 0, &thrown)
        let box = try #require(throwableBox(from: thrown))
        #expect(box.message == "custom-null-msg",
                "requireNotNull lazy message must be included in IllegalArgumentException")
    }

    // MARK: - Exception type discrimination for lazy variants

    @Test
    func testCheckNotNullLazyThrowsIllegalStateException() throws {
        var thrown = 0
        _ = kk_check_not_null_lazy(runtimeNullSentinelInt, fnPtrInt(notNullCountingThunk), 0, &thrown)
        let box = try #require(throwableBox(from: thrown))
        #expect(box.exceptionFQName == "kotlin.IllegalStateException")
        #expect(!runtimeThrowableBoxHasExactType(box, RuntimeIllegalArgumentExceptionBox.self))
    }

    @Test
    func testRequireNotNullLazyThrowsIllegalArgumentException() throws {
        var thrown = 0
        _ = kk_require_not_null_lazy(runtimeNullSentinelInt, fnPtrInt(notNullCountingThunk), 0, &thrown)
        let box = try #require(throwableBox(from: thrown))
        #expect(box.exceptionFQName == "kotlin.IllegalArgumentException")
        #expect(!runtimeThrowableBoxHasExactType(box, RuntimeIllegalStateExceptionBox.self))
    }
}
#endif
