
// MARK: - Typed Exception Box Classes (STDLIB-LOG-149)
//
// Typed RuntimeThrowableBox subclasses for AssertionError, IllegalStateException,
// IllegalArgumentException, NoWhenBranchMatchedException, and
// ConcurrentModificationException, StringIndexOutOfBoundsException, and
// ArrayIndexOutOfBoundsException. These enable proper type-discriminated catch
// blocks in compiled Kotlin code (e.g., `catch (e: IllegalArgumentException)`).
//
// The message stored in each box is the *user-visible* message (without the
// exception-type prefix). The `renderedMessage` property adds the type prefix
// for stack-trace / toString() output, matching Kotlin JVM behaviour.

final class RuntimeAssertionErrorBox: RuntimeThrowableBox {
    override var exceptionFQName: String {
        "kotlin.AssertionError"
    }

    override var exceptionHierarchyFQNames: [String] {
        [
            "kotlin.AssertionError",
            "kotlin.Error",
            "kotlin.Throwable",
        ]
    }

    override var renderedMessage: String {
        "AssertionError: \(message)"
    }
}

final class RuntimeIllegalStateExceptionBox: RuntimeThrowableBox {
    override var exceptionFQName: String {
        "kotlin.IllegalStateException"
    }

    override var exceptionHierarchyFQNames: [String] {
        [
            "kotlin.IllegalStateException",
            "kotlin.RuntimeException",
            "kotlin.Exception",
            "kotlin.Throwable",
        ]
    }

    override var renderedMessage: String {
        "IllegalStateException: \(message)"
    }
}

final class RuntimeIllegalArgumentExceptionBox: RuntimeThrowableBox {
    override var exceptionFQName: String {
        "kotlin.IllegalArgumentException"
    }

    override var exceptionHierarchyFQNames: [String] {
        [
            "kotlin.IllegalArgumentException",
            "kotlin.RuntimeException",
            "kotlin.Exception",
            "kotlin.Throwable",
        ]
    }

    override var renderedMessage: String {
        "IllegalArgumentException: \(message)"
    }
}

final class RuntimeNoWhenBranchMatchedExceptionBox: RuntimeThrowableBox {
    override var exceptionFQName: String {
        "kotlin.NoWhenBranchMatchedException"
    }

    override var exceptionHierarchyFQNames: [String] {
        [
            "kotlin.NoWhenBranchMatchedException",
            "kotlin.RuntimeException",
            "kotlin.Exception",
            "kotlin.Throwable",
        ]
    }

    override var renderedMessage: String {
        "NoWhenBranchMatchedException: \(message)"
    }
}

final class RuntimeConcurrentModificationExceptionBox: RuntimeThrowableBox {
    override var exceptionFQName: String {
        "kotlin.ConcurrentModificationException"
    }

    override var exceptionHierarchyFQNames: [String] {
        [
            "kotlin.ConcurrentModificationException",
            "kotlin.RuntimeException",
            "kotlin.Exception",
            "kotlin.Throwable",
        ]
    }

    override var renderedMessage: String {
        "ConcurrentModificationException: \(message)"
    }
}

final class RuntimeArrayIndexOutOfBoundsExceptionBox: RuntimeThrowableBox {
    override var exceptionFQName: String {
        "kotlin.ArrayIndexOutOfBoundsException"
    }

    override var exceptionHierarchyFQNames: [String] {
        [
            "kotlin.ArrayIndexOutOfBoundsException",
            "kotlin.IndexOutOfBoundsException",
            "kotlin.RuntimeException",
            "kotlin.Exception",
            "kotlin.Throwable",
        ]
    }

    override var renderedMessage: String {
        "ArrayIndexOutOfBoundsException: \(message)"
    }
}

final class RuntimeStringIndexOutOfBoundsExceptionBox: RuntimeThrowableBox {
    override var exceptionFQName: String {
        "kotlin.StringIndexOutOfBoundsException"
    }

    override var exceptionHierarchyFQNames: [String] {
        [
            "kotlin.StringIndexOutOfBoundsException",
            "kotlin.IndexOutOfBoundsException",
            "kotlin.RuntimeException",
            "kotlin.Exception",
            "kotlin.Throwable",
        ]
    }

    override var renderedMessage: String {
        "StringIndexOutOfBoundsException: \(message)"
    }
}

final class RuntimeNumberFormatExceptionBox: RuntimeThrowableBox {
    override var exceptionFQName: String {
        "kotlin.NumberFormatException"
    }

    override var exceptionHierarchyFQNames: [String] {
        [
            "kotlin.NumberFormatException",
            "kotlin.IllegalArgumentException",
            "kotlin.RuntimeException",
            "kotlin.Exception",
            "kotlin.Throwable",
        ]
    }

    override var renderedMessage: String {
        "NumberFormatException: \(message)"
    }
}

final class RuntimeArithmeticExceptionBox: RuntimeThrowableBox {
    override var exceptionFQName: String {
        "kotlin.ArithmeticException"
    }

    override var exceptionHierarchyFQNames: [String] {
        [
            "kotlin.ArithmeticException",
            "kotlin.RuntimeException",
            "kotlin.Exception",
            "kotlin.Throwable",
        ]
    }

    override var renderedMessage: String {
        "ArithmeticException: \(message)"
    }
}

// KSP-467-adjacent (catch-clause sibling-type discrimination fix): typed boxes for
// the remaining built-in exception classes that were previously constructed via the
// generic, type-erased `kk_throwable_new`/`kk_throwable_new_with_cause` external
// functions. Without a distinct RuntimeThrowableBox subclass + hierarchy, `kk_op_is`
// cannot tell these apart from any other built-in exception, so a `catch (e: T)`
// clause for one of these types would incorrectly match an unrelated sibling
// exception (e.g. `catch (e: NumberFormatException)` catching a thrown
// `IllegalStateException`). See Sources/Runtime/RuntimeStringArray.swift kk_op_is.
final class RuntimeExceptionBox: RuntimeThrowableBox {
    override var exceptionFQName: String {
        "kotlin.Exception"
    }

    override var exceptionHierarchyFQNames: [String] {
        [
            "kotlin.Exception",
            "kotlin.Throwable",
        ]
    }

    override var renderedMessage: String {
        "Exception: \(message)"
    }
}

final class RuntimeRuntimeExceptionBox: RuntimeThrowableBox {
    override var exceptionFQName: String {
        "kotlin.RuntimeException"
    }

    override var exceptionHierarchyFQNames: [String] {
        [
            "kotlin.RuntimeException",
            "kotlin.Exception",
            "kotlin.Throwable",
        ]
    }

    override var renderedMessage: String {
        "RuntimeException: \(message)"
    }
}

final class RuntimeErrorBox: RuntimeThrowableBox {
    override var exceptionFQName: String {
        "kotlin.Error"
    }

    override var exceptionHierarchyFQNames: [String] {
        [
            "kotlin.Error",
            "kotlin.Throwable",
        ]
    }

    override var renderedMessage: String {
        "Error: \(message)"
    }
}

final class RuntimeIndexOutOfBoundsExceptionBox: RuntimeThrowableBox {
    override var exceptionFQName: String {
        "kotlin.IndexOutOfBoundsException"
    }

    override var exceptionHierarchyFQNames: [String] {
        [
            "kotlin.IndexOutOfBoundsException",
            "kotlin.RuntimeException",
            "kotlin.Exception",
            "kotlin.Throwable",
        ]
    }

    override var renderedMessage: String {
        "IndexOutOfBoundsException: \(message)"
    }
}

final class RuntimeUnsupportedOperationExceptionBox: RuntimeThrowableBox {
    override var exceptionFQName: String {
        "kotlin.UnsupportedOperationException"
    }

    override var exceptionHierarchyFQNames: [String] {
        [
            "kotlin.UnsupportedOperationException",
            "kotlin.RuntimeException",
            "kotlin.Exception",
            "kotlin.Throwable",
        ]
    }

    override var renderedMessage: String {
        "UnsupportedOperationException: \(message)"
    }
}

final class RuntimeNoSuchElementExceptionBox: RuntimeThrowableBox {
    override var exceptionFQName: String {
        "kotlin.NoSuchElementException"
    }

    override var exceptionHierarchyFQNames: [String] {
        [
            "kotlin.NoSuchElementException",
            "kotlin.RuntimeException",
            "kotlin.Exception",
            "kotlin.Throwable",
        ]
    }

    override var renderedMessage: String {
        "NoSuchElementException: \(message)"
    }
}

final class RuntimeClassCastExceptionBox: RuntimeThrowableBox {
    override var exceptionFQName: String {
        "kotlin.ClassCastException"
    }

    override var exceptionHierarchyFQNames: [String] {
        [
            "kotlin.ClassCastException",
            "kotlin.RuntimeException",
            "kotlin.Exception",
            "kotlin.Throwable",
        ]
    }

    override var renderedMessage: String {
        "ClassCastException: \(message)"
    }
}

final class RuntimeNullPointerExceptionBox: RuntimeThrowableBox {
    override var exceptionFQName: String {
        "kotlin.NullPointerException"
    }

    override var exceptionHierarchyFQNames: [String] {
        [
            "kotlin.NullPointerException",
            "kotlin.RuntimeException",
            "kotlin.Exception",
            "kotlin.Throwable",
        ]
    }

    override var renderedMessage: String {
        "NullPointerException: \(message)"
    }
}

// MARK: - Typed Allocators

/// Allocates an `AssertionError` with the given message.
func runtimeAllocateAssertionError(message: String, cause: Int = 0) -> Int {
    let throwable = RuntimeAssertionErrorBox(message: message, cause: cause)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(throwable).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

/// Allocates an `IllegalStateException` with the given message.
func runtimeAllocateIllegalStateException(message: String, cause: Int = 0) -> Int {
    let throwable = RuntimeIllegalStateExceptionBox(message: message, cause: cause)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(throwable).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

/// Allocates an `IllegalArgumentException` with the given message.
func runtimeAllocateIllegalArgumentException(message: String, cause: Int = 0) -> Int {
    let throwable = RuntimeIllegalArgumentExceptionBox(message: message, cause: cause)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(throwable).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

func runtimeAllocateNoWhenBranchMatchedException(message: String, cause: Int = 0) -> Int {
    let throwable = RuntimeNoWhenBranchMatchedExceptionBox(message: message, cause: cause)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(throwable).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

func runtimeAllocateConcurrentModificationException(message: String, cause: Int = 0) -> Int {
    let throwable = RuntimeConcurrentModificationExceptionBox(message: message, cause: cause)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(throwable).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

func runtimeAllocateArrayIndexOutOfBoundsException(message: String) -> Int {
    let throwable = RuntimeArrayIndexOutOfBoundsExceptionBox(message: message)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(throwable).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

func runtimeAllocateStringIndexOutOfBoundsException(message: String) -> Int {
    let throwable = RuntimeStringIndexOutOfBoundsExceptionBox(message: message)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(throwable).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

func runtimeAllocateNumberFormatException(message: String, cause: Int = 0) -> Int {
    let throwable = RuntimeNumberFormatExceptionBox(message: message, cause: cause)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(throwable).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

func runtimeAllocateArithmeticException(message: String, cause: Int = 0) -> Int {
    let throwable = RuntimeArithmeticExceptionBox(message: message, cause: cause)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(throwable).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

/// Allocates an `Exception` with the given message.
func runtimeAllocateException(message: String, cause: Int = 0) -> Int {
    let throwable = RuntimeExceptionBox(message: message, cause: cause)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(throwable).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

/// Allocates a `RuntimeException` with the given message.
func runtimeAllocateRuntimeException(message: String, cause: Int = 0) -> Int {
    let throwable = RuntimeRuntimeExceptionBox(message: message, cause: cause)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(throwable).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

/// Allocates an `Error` with the given message.
func runtimeAllocateError(message: String, cause: Int = 0) -> Int {
    let throwable = RuntimeErrorBox(message: message, cause: cause)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(throwable).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

/// Allocates an `IndexOutOfBoundsException` with the given message.
func runtimeAllocateIndexOutOfBoundsException(message: String, cause: Int = 0) -> Int {
    let throwable = RuntimeIndexOutOfBoundsExceptionBox(message: message, cause: cause)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(throwable).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

/// Allocates an `UnsupportedOperationException` with the given message.
func runtimeAllocateUnsupportedOperationException(message: String, cause: Int = 0) -> Int {
    let throwable = RuntimeUnsupportedOperationExceptionBox(message: message, cause: cause)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(throwable).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

/// Allocates a `NoSuchElementException` with the given message.
func runtimeAllocateNoSuchElementException(message: String, cause: Int = 0) -> Int {
    let throwable = RuntimeNoSuchElementExceptionBox(message: message, cause: cause)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(throwable).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

/// Allocates a `ClassCastException` with the given message.
func runtimeAllocateClassCastException(message: String, cause: Int = 0) -> Int {
    let throwable = RuntimeClassCastExceptionBox(message: message, cause: cause)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(throwable).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

/// Allocates a `NullPointerException` with the given message.
func runtimeAllocateNullPointerException(message: String, cause: Int = 0) -> Int {
    let throwable = RuntimeNullPointerExceptionBox(message: message, cause: cause)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(throwable).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

private func runtimeExceptionMessage(from raw: Int, defaultMessage: String) -> String {
    if raw == 0 || raw == runtimeNullSentinelInt {
        return defaultMessage
    }
    return extractString(from: UnsafeMutableRawPointer(bitPattern: raw)) ?? defaultMessage
}

@_cdecl("kk_no_when_branch_matched_exception_new")
public func kk_no_when_branch_matched_exception_new() -> Int {
    runtimeAllocateNoWhenBranchMatchedException(message: "No when branch matched")
}

@_cdecl("kk_no_when_branch_matched_exception_new_message")
public func kk_no_when_branch_matched_exception_new_message(_ messageRaw: Int) -> Int {
    runtimeAllocateNoWhenBranchMatchedException(
        message: runtimeExceptionMessage(from: messageRaw, defaultMessage: "No when branch matched")
    )
}

@_cdecl("kk_no_when_branch_matched_exception_new_message_cause")
public func kk_no_when_branch_matched_exception_new_message_cause(_ messageRaw: Int, _ causeRaw: Int) -> Int {
    runtimeAllocateNoWhenBranchMatchedException(
        message: runtimeExceptionMessage(from: messageRaw, defaultMessage: "No when branch matched"),
        cause: (causeRaw == 0 || causeRaw == runtimeNullSentinelInt) ? 0 : causeRaw
    )
}

@_cdecl("kk_no_when_branch_matched_exception_new_cause")
public func kk_no_when_branch_matched_exception_new_cause(_ causeRaw: Int) -> Int {
    runtimeAllocateNoWhenBranchMatchedException(
        message: "No when branch matched",
        cause: (causeRaw == 0 || causeRaw == runtimeNullSentinelInt) ? 0 : causeRaw
    )
}

@_cdecl("kk_concurrent_modification_exception_new")
public func kk_concurrent_modification_exception_new() -> Int {
    runtimeAllocateConcurrentModificationException(message: "")
}

@_cdecl("kk_concurrent_modification_exception_new_message")
public func kk_concurrent_modification_exception_new_message(_ messageRaw: Int) -> Int {
    runtimeAllocateConcurrentModificationException(
        message: runtimeExceptionMessage(from: messageRaw, defaultMessage: "")
    )
}

@_cdecl("kk_concurrent_modification_exception_new_message_cause")
public func kk_concurrent_modification_exception_new_message_cause(_ messageRaw: Int, _ causeRaw: Int) -> Int {
    runtimeAllocateConcurrentModificationException(
        message: runtimeExceptionMessage(from: messageRaw, defaultMessage: ""),
        cause: (causeRaw == 0 || causeRaw == runtimeNullSentinelInt) ? 0 : causeRaw
    )
}

@_cdecl("kk_concurrent_modification_exception_new_cause")
public func kk_concurrent_modification_exception_new_cause(_ causeRaw: Int) -> Int {
    runtimeAllocateConcurrentModificationException(
        message: "",
        cause: (causeRaw == 0 || causeRaw == runtimeNullSentinelInt) ? 0 : causeRaw
    )
}

@_cdecl("kk_array_index_out_of_bounds_exception_new")
public func kk_array_index_out_of_bounds_exception_new() -> Int {
    runtimeAllocateArrayIndexOutOfBoundsException(message: "")
}

@_cdecl("kk_array_index_out_of_bounds_exception_new_message")
public func kk_array_index_out_of_bounds_exception_new_message(_ messageRaw: Int) -> Int {
    runtimeAllocateArrayIndexOutOfBoundsException(
        message: runtimeExceptionMessage(from: messageRaw, defaultMessage: "")
    )
}

// MARK: - Explicit constructor entry points (catch-clause sibling-type discrimination fix)
//
// Each of these gives a user-facing `SomeBuiltinException(...)` constructor call its
// own external symbol (instead of sharing the type-erased `kk_throwable_new`/
// `kk_throwable_new_with_cause`), so the allocated box carries the correct
// `exceptionHierarchyFQNames` and `kk_op_is`/catch-clause dispatch can tell sibling
// exception types apart. See HeaderHelpers+SyntheticExceptionStubs.swift for the
// constructor registrations that reference these link names.

@_cdecl("kk_illegal_state_exception_new")
public func kk_illegal_state_exception_new() -> Int {
    runtimeAllocateIllegalStateException(message: "")
}

@_cdecl("kk_illegal_state_exception_new_message")
public func kk_illegal_state_exception_new_message(_ messageRaw: Int) -> Int {
    runtimeAllocateIllegalStateException(message: runtimeExceptionMessage(from: messageRaw, defaultMessage: ""))
}

@_cdecl("kk_illegal_state_exception_new_message_cause")
public func kk_illegal_state_exception_new_message_cause(_ messageRaw: Int, _ causeRaw: Int) -> Int {
    runtimeAllocateIllegalStateException(
        message: runtimeExceptionMessage(from: messageRaw, defaultMessage: ""),
        cause: (causeRaw == 0 || causeRaw == runtimeNullSentinelInt) ? 0 : causeRaw
    )
}

@_cdecl("kk_illegal_argument_exception_new")
public func kk_illegal_argument_exception_new() -> Int {
    runtimeAllocateIllegalArgumentException(message: "")
}

@_cdecl("kk_illegal_argument_exception_new_message")
public func kk_illegal_argument_exception_new_message(_ messageRaw: Int) -> Int {
    runtimeAllocateIllegalArgumentException(message: runtimeExceptionMessage(from: messageRaw, defaultMessage: ""))
}

@_cdecl("kk_illegal_argument_exception_new_message_cause")
public func kk_illegal_argument_exception_new_message_cause(_ messageRaw: Int, _ causeRaw: Int) -> Int {
    runtimeAllocateIllegalArgumentException(
        message: runtimeExceptionMessage(from: messageRaw, defaultMessage: ""),
        cause: (causeRaw == 0 || causeRaw == runtimeNullSentinelInt) ? 0 : causeRaw
    )
}

@_cdecl("kk_number_format_exception_new")
public func kk_number_format_exception_new() -> Int {
    runtimeAllocateNumberFormatException(message: "")
}

@_cdecl("kk_number_format_exception_new_message")
public func kk_number_format_exception_new_message(_ messageRaw: Int) -> Int {
    runtimeAllocateNumberFormatException(message: runtimeExceptionMessage(from: messageRaw, defaultMessage: ""))
}

@_cdecl("kk_number_format_exception_new_message_cause")
public func kk_number_format_exception_new_message_cause(_ messageRaw: Int, _ causeRaw: Int) -> Int {
    runtimeAllocateNumberFormatException(
        message: runtimeExceptionMessage(from: messageRaw, defaultMessage: ""),
        cause: (causeRaw == 0 || causeRaw == runtimeNullSentinelInt) ? 0 : causeRaw
    )
}

@_cdecl("kk_arithmetic_exception_new")
public func kk_arithmetic_exception_new() -> Int {
    runtimeAllocateArithmeticException(message: "")
}

@_cdecl("kk_arithmetic_exception_new_message")
public func kk_arithmetic_exception_new_message(_ messageRaw: Int) -> Int {
    runtimeAllocateArithmeticException(message: runtimeExceptionMessage(from: messageRaw, defaultMessage: ""))
}

@_cdecl("kk_arithmetic_exception_new_message_cause")
public func kk_arithmetic_exception_new_message_cause(_ messageRaw: Int, _ causeRaw: Int) -> Int {
    runtimeAllocateArithmeticException(
        message: runtimeExceptionMessage(from: messageRaw, defaultMessage: ""),
        cause: (causeRaw == 0 || causeRaw == runtimeNullSentinelInt) ? 0 : causeRaw
    )
}

@_cdecl("kk_assertion_error_new")
public func kk_assertion_error_new() -> Int {
    runtimeAllocateAssertionError(message: "")
}

@_cdecl("kk_assertion_error_new_message")
public func kk_assertion_error_new_message(_ messageRaw: Int) -> Int {
    runtimeAllocateAssertionError(message: runtimeExceptionMessage(from: messageRaw, defaultMessage: ""))
}

@_cdecl("kk_assertion_error_new_message_cause")
public func kk_assertion_error_new_message_cause(_ messageRaw: Int, _ causeRaw: Int) -> Int {
    runtimeAllocateAssertionError(
        message: runtimeExceptionMessage(from: messageRaw, defaultMessage: ""),
        cause: (causeRaw == 0 || causeRaw == runtimeNullSentinelInt) ? 0 : causeRaw
    )
}

@_cdecl("kk_uninitialized_property_access_exception_new")
public func kk_uninitialized_property_access_exception_new() -> Int {
    runtimeAllocateUninitializedPropertyAccessException(message: "")
}

@_cdecl("kk_uninitialized_property_access_exception_new_message")
public func kk_uninitialized_property_access_exception_new_message(_ messageRaw: Int) -> Int {
    runtimeAllocateUninitializedPropertyAccessException(
        message: runtimeExceptionMessage(from: messageRaw, defaultMessage: "")
    )
}

@_cdecl("kk_uninitialized_property_access_exception_new_message_cause")
public func kk_uninitialized_property_access_exception_new_message_cause(_ messageRaw: Int, _ causeRaw: Int) -> Int {
    runtimeAllocateUninitializedPropertyAccessException(
        message: runtimeExceptionMessage(from: messageRaw, defaultMessage: ""),
        cause: (causeRaw == 0 || causeRaw == runtimeNullSentinelInt) ? 0 : causeRaw
    )
}

@_cdecl("kk_exception_new")
public func kk_exception_new() -> Int {
    runtimeAllocateException(message: "")
}

@_cdecl("kk_runtime_exception_new")
public func kk_runtime_exception_new() -> Int {
    runtimeAllocateRuntimeException(message: "")
}

@_cdecl("kk_runtime_exception_new_message")
public func kk_runtime_exception_new_message(_ messageRaw: Int) -> Int {
    runtimeAllocateRuntimeException(message: runtimeExceptionMessage(from: messageRaw, defaultMessage: ""))
}

@_cdecl("kk_runtime_exception_new_message_cause")
public func kk_runtime_exception_new_message_cause(_ messageRaw: Int, _ causeRaw: Int) -> Int {
    runtimeAllocateRuntimeException(
        message: runtimeExceptionMessage(from: messageRaw, defaultMessage: ""),
        cause: (causeRaw == 0 || causeRaw == runtimeNullSentinelInt) ? 0 : causeRaw
    )
}

@_cdecl("kk_error_new")
public func kk_error_new() -> Int {
    runtimeAllocateError(message: "")
}

@_cdecl("kk_error_new_message")
public func kk_error_new_message(_ messageRaw: Int) -> Int {
    runtimeAllocateError(message: runtimeExceptionMessage(from: messageRaw, defaultMessage: ""))
}

@_cdecl("kk_error_new_message_cause")
public func kk_error_new_message_cause(_ messageRaw: Int, _ causeRaw: Int) -> Int {
    runtimeAllocateError(
        message: runtimeExceptionMessage(from: messageRaw, defaultMessage: ""),
        cause: (causeRaw == 0 || causeRaw == runtimeNullSentinelInt) ? 0 : causeRaw
    )
}

@_cdecl("kk_index_out_of_bounds_exception_new")
public func kk_index_out_of_bounds_exception_new() -> Int {
    runtimeAllocateIndexOutOfBoundsException(message: "")
}

@_cdecl("kk_index_out_of_bounds_exception_new_message")
public func kk_index_out_of_bounds_exception_new_message(_ messageRaw: Int) -> Int {
    runtimeAllocateIndexOutOfBoundsException(message: runtimeExceptionMessage(from: messageRaw, defaultMessage: ""))
}

@_cdecl("kk_index_out_of_bounds_exception_new_message_cause")
public func kk_index_out_of_bounds_exception_new_message_cause(_ messageRaw: Int, _ causeRaw: Int) -> Int {
    runtimeAllocateIndexOutOfBoundsException(
        message: runtimeExceptionMessage(from: messageRaw, defaultMessage: ""),
        cause: (causeRaw == 0 || causeRaw == runtimeNullSentinelInt) ? 0 : causeRaw
    )
}

@_cdecl("kk_unsupported_operation_exception_new")
public func kk_unsupported_operation_exception_new() -> Int {
    runtimeAllocateUnsupportedOperationException(message: "")
}

@_cdecl("kk_unsupported_operation_exception_new_message")
public func kk_unsupported_operation_exception_new_message(_ messageRaw: Int) -> Int {
    runtimeAllocateUnsupportedOperationException(
        message: runtimeExceptionMessage(from: messageRaw, defaultMessage: "")
    )
}

@_cdecl("kk_unsupported_operation_exception_new_message_cause")
public func kk_unsupported_operation_exception_new_message_cause(_ messageRaw: Int, _ causeRaw: Int) -> Int {
    runtimeAllocateUnsupportedOperationException(
        message: runtimeExceptionMessage(from: messageRaw, defaultMessage: ""),
        cause: (causeRaw == 0 || causeRaw == runtimeNullSentinelInt) ? 0 : causeRaw
    )
}

@_cdecl("kk_no_such_element_exception_new")
public func kk_no_such_element_exception_new() -> Int {
    runtimeAllocateNoSuchElementException(message: "")
}

@_cdecl("kk_no_such_element_exception_new_message")
public func kk_no_such_element_exception_new_message(_ messageRaw: Int) -> Int {
    runtimeAllocateNoSuchElementException(message: runtimeExceptionMessage(from: messageRaw, defaultMessage: ""))
}

@_cdecl("kk_no_such_element_exception_new_message_cause")
public func kk_no_such_element_exception_new_message_cause(_ messageRaw: Int, _ causeRaw: Int) -> Int {
    runtimeAllocateNoSuchElementException(
        message: runtimeExceptionMessage(from: messageRaw, defaultMessage: ""),
        cause: (causeRaw == 0 || causeRaw == runtimeNullSentinelInt) ? 0 : causeRaw
    )
}

@_cdecl("kk_class_cast_exception_new")
public func kk_class_cast_exception_new() -> Int {
    runtimeAllocateClassCastException(message: "")
}

@_cdecl("kk_class_cast_exception_new_message")
public func kk_class_cast_exception_new_message(_ messageRaw: Int) -> Int {
    runtimeAllocateClassCastException(message: runtimeExceptionMessage(from: messageRaw, defaultMessage: ""))
}

@_cdecl("kk_class_cast_exception_new_message_cause")
public func kk_class_cast_exception_new_message_cause(_ messageRaw: Int, _ causeRaw: Int) -> Int {
    runtimeAllocateClassCastException(
        message: runtimeExceptionMessage(from: messageRaw, defaultMessage: ""),
        cause: (causeRaw == 0 || causeRaw == runtimeNullSentinelInt) ? 0 : causeRaw
    )
}

@_cdecl("kk_null_pointer_exception_new")
public func kk_null_pointer_exception_new() -> Int {
    runtimeAllocateNullPointerException(message: "")
}
