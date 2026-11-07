// Typed RuntimeThrowableBox subclasses enable proper type-discriminated catch
// blocks in compiled Kotlin code (e.g., `catch (e: IllegalArgumentException)`).
//
// The message stored in each box is the *user-visible* message (without the
// exception-type prefix). The `renderedMessage` property adds the type prefix
// for stack-trace / toString() output, matching Kotlin JVM behaviour.

final class RuntimeFreezingExceptionBox: RuntimeThrowableBox {
    override var exceptionFQName: String {
        "kotlin.native.concurrent.FreezingException"
    }

    override var exceptionHierarchyFQNames: [String] {
        [
            "kotlin.native.concurrent.FreezingException",
            "kotlin.RuntimeException",
            "kotlin.Exception",
            "kotlin.Throwable",
        ]
    }

    override var renderedMessage: String {
        runtimeRenderedExceptionMessage("FreezingException", message)
    }
}

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
        runtimeRenderedExceptionMessage("AssertionError", message)
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
        runtimeRenderedExceptionMessage("IllegalStateException", message)
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
        runtimeRenderedExceptionMessage("IllegalArgumentException", message)
    }
}

final class RuntimeInvalidParameterExceptionBox: RuntimeThrowableBox {
    override var exceptionFQName: String {
        "java.security.InvalidParameterException"
    }

    override var exceptionHierarchyFQNames: [String] {
        [
            "java.security.InvalidParameterException",
            "java.lang.IllegalArgumentException",
            "kotlin.IllegalArgumentException",
            "kotlin.RuntimeException",
            "kotlin.Exception",
            "kotlin.Throwable",
        ]
    }

    override var renderedMessage: String {
        runtimeRenderedExceptionMessage("InvalidParameterException", message)
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
        runtimeRenderedExceptionMessage("NoWhenBranchMatchedException", message)
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
        runtimeRenderedExceptionMessage("ConcurrentModificationException", message)
    }
}

final class RuntimeInvalidMutabilityExceptionBox: RuntimeThrowableBox {
    override var exceptionFQName: String {
        "kotlin.native.concurrent.InvalidMutabilityException"
    }

    override var exceptionHierarchyFQNames: [String] {
        [
            "kotlin.native.concurrent.InvalidMutabilityException",
            "kotlin.RuntimeException",
            "kotlin.Exception",
            "kotlin.Throwable",
        ]
    }

    override var renderedMessage: String {
        runtimeRenderedExceptionMessage("InvalidMutabilityException", message)
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
        runtimeRenderedExceptionMessage("ArrayIndexOutOfBoundsException", message)
    }
}

final class RuntimeArrayStoreExceptionBox: RuntimeThrowableBox {
    override var exceptionFQName: String {
        "java.lang.ArrayStoreException"
    }

    override var exceptionHierarchyFQNames: [String] {
        [
            "java.lang.ArrayStoreException",
            "kotlin.RuntimeException",
            "kotlin.Exception",
            "kotlin.Throwable",
        ]
    }

    override var renderedMessage: String {
        runtimeRenderedExceptionMessage("ArrayStoreException", message)
    }
}

final class RuntimeStringIndexOutOfBoundsExceptionBox: RuntimeThrowableBox {
    override var exceptionFQName: String {
        "java.lang.StringIndexOutOfBoundsException"
    }

    override var exceptionHierarchyFQNames: [String] {
        [
            "java.lang.StringIndexOutOfBoundsException",
            "kotlin.IndexOutOfBoundsException",
            "kotlin.RuntimeException",
            "kotlin.Exception",
            "kotlin.Throwable",
        ]
    }

    override var renderedMessage: String {
        runtimeRenderedExceptionMessage("StringIndexOutOfBoundsException", message)
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
        runtimeRenderedExceptionMessage("NumberFormatException", message)
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
        runtimeRenderedExceptionMessage("ArithmeticException", message)
    }
}

final class RuntimeNegativeArraySizeExceptionBox: RuntimeThrowableBox {
    override var exceptionFQName: String {
        "kotlin.NegativeArraySizeException"
    }

    override var exceptionHierarchyFQNames: [String] {
        [
            "kotlin.NegativeArraySizeException",
            "kotlin.RuntimeException",
            "kotlin.Exception",
            "kotlin.Throwable",
        ]
    }

    override var renderedMessage: String {
        runtimeRenderedExceptionMessage("NegativeArraySizeException", message)
    }
}

// Typed boxes for the remaining built-in exception classes that were previously
// constructed via the generic, type-erased `__kk_throwable_new`/
// `__kk_throwable_new_with_cause` external functions. Without a distinct
// RuntimeThrowableBox subclass + hierarchy, `kk_op_is` cannot tell these apart
// from any other built-in exception, so a `catch (e: T)` clause for one of these
// types would incorrectly match an unrelated sibling exception (e.g.
// `catch (e: NumberFormatException)` catching a thrown `IllegalStateException`).
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
        runtimeRenderedExceptionMessage("Exception", message)
    }
}

final class RuntimeIOExceptionBox: RuntimeThrowableBox {
    override var exceptionFQName: String {
        "java.io.IOException"
    }

    override var exceptionHierarchyFQNames: [String] {
        [
            "java.io.IOException",
            "kotlinx.io.IOException",
            "kotlin.Exception",
            "kotlin.Throwable",
        ]
    }

    override var renderedMessage: String {
        runtimeRenderedExceptionMessage("IOException", message)
    }
}

final class RuntimeCharacterCodingExceptionBox: RuntimeThrowableBox {
    override var exceptionFQName: String {
        "kotlin.text.CharacterCodingException"
    }

    override var exceptionHierarchyFQNames: [String] {
        [
            "kotlin.text.CharacterCodingException",
            "kotlin.Exception",
            "kotlin.Throwable",
        ]
    }

    override var renderedMessage: String {
        runtimeRenderedExceptionMessage("CharacterCodingException", message)
    }
}

final class RuntimeMalformedInputExceptionBox: RuntimeThrowableBox {
    override var exceptionFQName: String {
        "java.nio.charset.MalformedInputException"
    }

    override var exceptionHierarchyFQNames: [String] {
        [
            "java.nio.charset.MalformedInputException",
            "java.nio.charset.CharacterCodingException",
            "kotlin.text.CharacterCodingException",
            "kotlin.Exception",
            "kotlin.Throwable",
        ]
    }

    override var renderedMessage: String {
        runtimeRenderedExceptionMessage("MalformedInputException", message)
    }
}

final class RuntimeKotlinNothingValueExceptionBox: RuntimeThrowableBox {
    override var exceptionFQName: String {
        "kotlin.KotlinNothingValueException"
    }

    override var exceptionHierarchyFQNames: [String] {
        [
            "kotlin.KotlinNothingValueException",
            "kotlin.RuntimeException",
            "kotlin.Exception",
            "kotlin.Throwable",
        ]
    }

    override var renderedMessage: String {
        runtimeRenderedExceptionMessage("KotlinNothingValueException", message)
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
        runtimeRenderedExceptionMessage("Error", message)
    }
}

final class RuntimeExceptionInInitializerErrorBox: RuntimeThrowableBox {
    override var exceptionFQName: String {
        "java.lang.ExceptionInInitializerError"
    }

    override var exceptionHierarchyFQNames: [String] {
        [
            "java.lang.ExceptionInInitializerError",
            "kotlin.Error",
            "java.lang.Error",
            "kotlin.Throwable",
        ]
    }

    override var renderedMessage: String {
        runtimeRenderedExceptionMessage("ExceptionInInitializerError", message)
    }
}

final class RuntimeKotlinReflectionNotSupportedErrorBox: RuntimeThrowableBox {
    override var exceptionFQName: String {
        "kotlin.KotlinReflectionNotSupportedError"
    }

    override var exceptionHierarchyFQNames: [String] {
        [
            "kotlin.KotlinReflectionNotSupportedError",
            "kotlin.Error",
            "kotlin.Throwable",
        ]
    }

    override var renderedMessage: String {
        runtimeRenderedExceptionMessage("KotlinReflectionNotSupportedError", message)
    }
}

final class RuntimeOutOfMemoryErrorBox: RuntimeThrowableBox {
    override var exceptionFQName: String {
        "kotlin.OutOfMemoryError"
    }

    override var exceptionHierarchyFQNames: [String] {
        [
            "kotlin.OutOfMemoryError",
            "kotlin.Error",
            "kotlin.Throwable",
        ]
    }

    override var renderedMessage: String {
        runtimeRenderedExceptionMessage("OutOfMemoryError", message)
    }
}

final class RuntimeStackOverflowErrorBox: RuntimeThrowableBox {
    override var exceptionFQName: String {
        "kotlin.StackOverflowError"
    }

    override var exceptionHierarchyFQNames: [String] {
        [
            "kotlin.StackOverflowError",
            "kotlin.Error",
            "kotlin.Throwable",
        ]
    }

    override var renderedMessage: String {
        runtimeRenderedExceptionMessage("StackOverflowError", message)
    }
}

final class RuntimeNotImplementedErrorBox: RuntimeThrowableBox {
    override var exceptionFQName: String {
        "kotlin.NotImplementedError"
    }

    override var exceptionHierarchyFQNames: [String] {
        [
            "kotlin.NotImplementedError",
            "kotlin.Error",
            "kotlin.Throwable",
        ]
    }

    override var renderedMessage: String {
        runtimeRenderedExceptionMessage("NotImplementedError", message)
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
        runtimeRenderedExceptionMessage("IndexOutOfBoundsException", message)
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
        runtimeRenderedExceptionMessage("UnsupportedOperationException", message)
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
        runtimeRenderedExceptionMessage("NoSuchElementException", message)
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
        runtimeRenderedExceptionMessage("ClassCastException", message)
    }
}

final class RuntimeTypeCastExceptionBox: RuntimeThrowableBox {
    override var exceptionFQName: String {
        "kotlin.TypeCastException"
    }

    override var exceptionHierarchyFQNames: [String] {
        [
            "kotlin.TypeCastException",
            "kotlin.ClassCastException",
            "kotlin.RuntimeException",
            "kotlin.Exception",
            "kotlin.Throwable",
        ]
    }

    override var renderedMessage: String {
        runtimeRenderedExceptionMessage("TypeCastException", message)
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
        runtimeRenderedExceptionMessage("NullPointerException", message)
    }
}


/// Allocates a `FreezingException` with Kotlin/Native's exact constructor message.
func runtimeAllocateFreezingException(toFreezeRaw: Int, blockerRaw: Int) -> Int {
    let message = "freezing of \(runtimeRenderAnyForPrint(toFreezeRaw)) has failed, first blocker is \(runtimeRenderAnyForPrint(blockerRaw))"
    return runtimeRegisterThrowable(RuntimeFreezingExceptionBox(message: message))
}

func runtimeAllocateAssertionError(message: String?, cause: Int = 0, messageRaw: Int = 0) -> Int {
    return runtimeRegisterThrowable(RuntimeAssertionErrorBox(message: message, cause: cause, messageRaw: messageRaw))
}

func runtimeAllocateIllegalStateException(message: String?, cause: Int = 0, messageRaw: Int = 0) -> Int {
    return runtimeRegisterThrowable(RuntimeIllegalStateExceptionBox(message: message, cause: cause, messageRaw: messageRaw))
}

func runtimeAllocateIllegalArgumentException(message: String?, cause: Int = 0, messageRaw: Int = 0) -> Int {
    return runtimeRegisterThrowable(RuntimeIllegalArgumentExceptionBox(message: message, cause: cause, messageRaw: messageRaw))
}

func runtimeAllocateInvalidParameterException(message: String?, cause: Int = 0, messageRaw: Int = 0) -> Int {
    return runtimeRegisterThrowable(RuntimeInvalidParameterExceptionBox(message: message, cause: cause, messageRaw: messageRaw))
}

func runtimeAllocateNoWhenBranchMatchedException(message: String?, cause: Int = 0, messageRaw: Int = 0) -> Int {
    return runtimeRegisterThrowable(RuntimeNoWhenBranchMatchedExceptionBox(message: message, cause: cause, messageRaw: messageRaw))
}

func runtimeAllocateConcurrentModificationException(message: String?, cause: Int = 0, messageRaw: Int = 0) -> Int {
    return runtimeRegisterThrowable(RuntimeConcurrentModificationExceptionBox(message: message, cause: cause, messageRaw: messageRaw))
}

func runtimeAllocateInvalidMutabilityException(message: String?, messageRaw: Int = 0) -> Int {
    return runtimeRegisterThrowable(RuntimeInvalidMutabilityExceptionBox(message: message, messageRaw: messageRaw))
}

func runtimeAllocateArrayIndexOutOfBoundsException(message: String?, messageRaw: Int = 0) -> Int {
    return runtimeRegisterThrowable(RuntimeArrayIndexOutOfBoundsExceptionBox(message: message, messageRaw: messageRaw))
}

func runtimeAllocateArrayStoreException(message: String?, messageRaw: Int = 0) -> Int {
    return runtimeRegisterThrowable(RuntimeArrayStoreExceptionBox(message: message, messageRaw: messageRaw))
}

func runtimeAllocateStringIndexOutOfBoundsException(message: String?, messageRaw: Int = 0) -> Int {
    return runtimeRegisterThrowable(RuntimeStringIndexOutOfBoundsExceptionBox(message: message, messageRaw: messageRaw))
}

func runtimeAllocateNumberFormatException(message: String?, cause: Int = 0, messageRaw: Int = 0) -> Int {
    return runtimeRegisterThrowable(RuntimeNumberFormatExceptionBox(message: message, cause: cause, messageRaw: messageRaw))
}

func runtimeAllocateArithmeticException(message: String?, cause: Int = 0, messageRaw: Int = 0) -> Int {
    return runtimeRegisterThrowable(RuntimeArithmeticExceptionBox(message: message, cause: cause, messageRaw: messageRaw))
}

func runtimeAllocateNegativeArraySizeException(message: String?, messageRaw: Int = 0) -> Int {
    return runtimeRegisterThrowable(RuntimeNegativeArraySizeExceptionBox(message: message, messageRaw: messageRaw))
}

func runtimeAllocateException(message: String?, cause: Int = 0, messageRaw: Int = 0) -> Int {
    return runtimeRegisterThrowable(RuntimeExceptionBox(message: message, cause: cause, messageRaw: messageRaw))
}

func runtimeAllocateIOException(message: String?, cause: Int = 0, messageRaw: Int = 0) -> Int {
    return runtimeRegisterThrowable(RuntimeIOExceptionBox(message: message, cause: cause, messageRaw: messageRaw))
}

func runtimeAllocateCharacterCodingException(message: String?, messageRaw: Int = 0) -> Int {
    return runtimeRegisterThrowable(RuntimeCharacterCodingExceptionBox(message: message, messageRaw: messageRaw))
}

/// Message used by `MalformedInputException` for a one-byte invalid sequence.
let runtimeMalformedInputExceptionDefaultMessage = "Input length = 1"

func runtimeAllocateMalformedInputException(
    message: String? = runtimeMalformedInputExceptionDefaultMessage,
    messageRaw: Int = 0
) -> Int {
    return runtimeRegisterThrowable(RuntimeMalformedInputExceptionBox(message: message, messageRaw: messageRaw))
}

func runtimeAllocateKotlinNothingValueException(message: String?, cause: Int = 0, messageRaw: Int = 0) -> Int {
    return runtimeRegisterThrowable(RuntimeKotlinNothingValueExceptionBox(message: message, cause: cause, messageRaw: messageRaw))
}

func runtimeAllocateError(message: String?, cause: Int = 0, messageRaw: Int = 0) -> Int {
    return runtimeRegisterThrowable(RuntimeErrorBox(message: message, cause: cause, messageRaw: messageRaw))
}

func runtimeAllocateExceptionInInitializerError(message: String?, cause: Int = 0, messageRaw: Int = 0) -> Int {
    return runtimeRegisterThrowable(
        RuntimeExceptionInInitializerErrorBox(message: message, cause: cause, messageRaw: messageRaw)
    )
}

func runtimeAllocateKotlinReflectionNotSupportedError(message: String?, cause: Int = 0, messageRaw: Int = 0) -> Int {
    return runtimeRegisterThrowable(
        RuntimeKotlinReflectionNotSupportedErrorBox(message: message, cause: cause, messageRaw: messageRaw)
    )
}

func runtimeAllocateOutOfMemoryError(message: String?, cause: Int = 0, messageRaw: Int = 0) -> Int {
    return runtimeRegisterThrowable(RuntimeOutOfMemoryErrorBox(message: message, cause: cause, messageRaw: messageRaw))
}

func runtimeAllocateStackOverflowError(message: String?, cause: Int = 0, messageRaw: Int = 0) -> Int {
    return runtimeRegisterThrowable(RuntimeStackOverflowErrorBox(message: message, cause: cause, messageRaw: messageRaw))
}

let runtimeNotImplementedDefaultMessage = "An operation is not implemented."

func runtimeAllocateNotImplementedError(message: String, cause: Int = 0, messageRaw: Int = 0) -> Int {
    return runtimeRegisterThrowable(RuntimeNotImplementedErrorBox(message: message, cause: cause, messageRaw: messageRaw))
}

func runtimeAllocateIndexOutOfBoundsException(message: String?, cause: Int = 0, messageRaw: Int = 0) -> Int {
    return runtimeRegisterThrowable(RuntimeIndexOutOfBoundsExceptionBox(message: message, cause: cause, messageRaw: messageRaw))
}

func runtimeAllocateUnsupportedOperationException(message: String?, cause: Int = 0, messageRaw: Int = 0) -> Int {
    return runtimeRegisterThrowable(RuntimeUnsupportedOperationExceptionBox(message: message, cause: cause, messageRaw: messageRaw))
}

func runtimeAllocateNoSuchElementException(message: String?, cause: Int = 0, messageRaw: Int = 0) -> Int {
    return runtimeRegisterThrowable(RuntimeNoSuchElementExceptionBox(message: message, cause: cause, messageRaw: messageRaw))
}

func runtimeAllocateClassCastException(message: String?, cause: Int = 0, messageRaw: Int = 0) -> Int {
    return runtimeRegisterThrowable(RuntimeClassCastExceptionBox(message: message, cause: cause, messageRaw: messageRaw))
}

func runtimeAllocateTypeCastException(message: String?, cause: Int = 0, messageRaw: Int = 0) -> Int {
    return runtimeRegisterThrowable(RuntimeTypeCastExceptionBox(message: message, cause: cause, messageRaw: messageRaw))
}

func runtimeAllocateNullPointerException(message: String?, cause: Int = 0, messageRaw: Int = 0) -> Int {
    return runtimeRegisterThrowable(RuntimeNullPointerExceptionBox(message: message, cause: cause, messageRaw: messageRaw))
}

private func runtimeExceptionMessage(from raw: Int, defaultMessage: String?) -> String? {
    if raw == 0 || raw == runtimeNullSentinelInt {
        return defaultMessage
    }
    return extractString(from: UnsafeMutableRawPointer(bitPattern: raw)) ?? defaultMessage
}

func runtimeJVMExceptionFQName(from kotlinFQName: String) -> String {
    switch kotlinFQName {
    case "kotlin.Exception":
        return "java.lang.Exception"
    case "kotlin.RuntimeException":
        return "java.lang.RuntimeException"
    case "kotlin.IllegalArgumentException":
        return "java.lang.IllegalArgumentException"
    case "kotlin.IllegalStateException":
        return "java.lang.IllegalStateException"
    case "kotlin.ArithmeticException":
        return "java.lang.ArithmeticException"
    case "kotlin.AssertionError":
        return "java.lang.AssertionError"
    case "kotlin.ClassCastException":
        return "java.lang.ClassCastException"
    case "kotlin.IndexOutOfBoundsException":
        return "java.lang.IndexOutOfBoundsException"
    case "kotlin.ArrayIndexOutOfBoundsException":
        return "java.lang.ArrayIndexOutOfBoundsException"
    case "kotlin.StringIndexOutOfBoundsException":
        return "java.lang.StringIndexOutOfBoundsException"
    case "kotlin.NegativeArraySizeException":
        return "java.lang.NegativeArraySizeException"
    case "kotlin.NullPointerException":
        return "java.lang.NullPointerException"
    case "kotlin.NumberFormatException":
        return "java.lang.NumberFormatException"
    case "kotlin.UnsupportedOperationException":
        return "java.lang.UnsupportedOperationException"
    case "kotlin.Error":
        return "java.lang.Error"
    case "kotlin.OutOfMemoryError":
        return "java.lang.OutOfMemoryError"
    case "kotlin.StackOverflowError":
        return "java.lang.StackOverflowError"
    case "kotlin.ConcurrentModificationException":
        return "java.util.ConcurrentModificationException"
    case "kotlin.NoSuchElementException":
        return "java.util.NoSuchElementException"
    case "kotlin.io.IOException":
        return "java.io.IOException"
    case "kotlin.Throwable":
        return "java.lang.Throwable"
    default:
        // Preserve unknown or user-defined FQ names instead of guessing java.lang.
        return kotlinFQName
    }
}

// Shared by typed exception bridges and the source-backed Throwable(cause)
// constructor. The JVM constructor derives its message from cause.toString().
func runtimeCauseToString(from raw: Int) -> String? {
    guard raw != 0,
          raw != runtimeNullSentinelInt,
          let ptr = UnsafeMutableRawPointer(bitPattern: raw)
    else {
        return nil
    }

    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return nil
    }

    if let throwable = tryCast(ptr, to: RuntimeThrowableBox.self) {
        let exceptionFQName = runtimeJVMExceptionFQName(from: throwable.exceptionFQName)
        guard let message = throwable.message else {
            return exceptionFQName
        }
        return "\(exceptionFQName): \(message)"
    }

    if let object = tryCast(ptr, to: RuntimeObjectBox.self) {
        let exceptionFQName = runtimeJVMExceptionFQName(
            from: runtimeSourceThrowableQualifiedName(for: object.classID)
        )
        guard let message = runtimeSourceThrowableMessage(raw, object: object) else {
            return exceptionFQName
        }
        return "\(exceptionFQName): \(message)"
    }

    return nil
}

private func runtimeAssertionErrorMessage(from raw: Int) -> String? {
    if raw == 0 || raw == runtimeNullSentinelInt {
        return nil
    }
    return runtimeRenderAnyForPrint(raw)
}

@inline(__always)
func runtimeMakeException<T: RuntimeThrowableBox>(
    _ factory: (String?, Int, Int) -> T
) -> Int {
    runtimeRegisterThrowable(factory(nil, 0, 0))
}

@inline(__always)
func runtimeMakeException<T: RuntimeThrowableBox>(
    _ messageRaw: Int,
    _ factory: (String?, Int, Int) -> T
) -> Int {
    let msg = runtimeExceptionMessage(from: messageRaw, defaultMessage: nil)
    return runtimeRegisterThrowable(factory(msg, 0, messageRaw))
}

@inline(__always)
func runtimeMakeException<T: RuntimeThrowableBox>(
    _ messageRaw: Int,
    _ causeRaw: Int,
    _ factory: (String?, Int, Int) -> T
) -> Int {
    let msg = runtimeExceptionMessage(from: messageRaw, defaultMessage: nil)
    let cause = (causeRaw == 0 || causeRaw == runtimeNullSentinelInt) ? 0 : causeRaw
    return runtimeMarkThrowableCauseInitialized(
        runtimeRegisterThrowable(factory(msg, cause, messageRaw))
    )
}

@inline(__always)
func runtimeMakeExceptionWithCause<T: RuntimeThrowableBox>(
    _ causeRaw: Int,
    _ factory: (String?, Int, Int) -> T
) -> Int {
    let cause = (causeRaw == 0 || causeRaw == runtimeNullSentinelInt) ? 0 : causeRaw
    let msg = runtimeCauseToString(from: causeRaw)
    return runtimeMarkThrowableCauseInitialized(
        runtimeRegisterThrowable(factory(msg, cause, 0))
    )
}

@_cdecl("__kk_no_when_branch_matched_exception_new")
public func kk_no_when_branch_matched_exception_new() -> Int {
    runtimeMakeException(RuntimeNoWhenBranchMatchedExceptionBox.init)
}

@_cdecl("__kk_no_when_branch_matched_exception_new_message")
public func kk_no_when_branch_matched_exception_new_message(_ messageRaw: Int) -> Int {
    runtimeMakeException(messageRaw, RuntimeNoWhenBranchMatchedExceptionBox.init)
}

@_cdecl("__kk_no_when_branch_matched_exception_new_message_cause")
public func kk_no_when_branch_matched_exception_new_message_cause(_ messageRaw: Int, _ causeRaw: Int) -> Int {
    runtimeMakeException(messageRaw, causeRaw, RuntimeNoWhenBranchMatchedExceptionBox.init)
}

@_cdecl("__kk_no_when_branch_matched_exception_new_cause")
public func kk_no_when_branch_matched_exception_new_cause(_ causeRaw: Int) -> Int {
    runtimeMakeExceptionWithCause(causeRaw, RuntimeNoWhenBranchMatchedExceptionBox.init)
}

@_cdecl("__kk_concurrent_modification_exception_new")
public func kk_concurrent_modification_exception_new() -> Int {
    runtimeMakeException(RuntimeConcurrentModificationExceptionBox.init)
}

@_cdecl("__kk_concurrent_modification_exception_new_message")
public func kk_concurrent_modification_exception_new_message(_ messageRaw: Int) -> Int {
    runtimeMakeException(messageRaw, RuntimeConcurrentModificationExceptionBox.init)
}

@_cdecl("__kk_invalid_mutability_exception_new_message")
public func kk_invalid_mutability_exception_new_message(_ messageRaw: Int) -> Int {
    runtimeMakeException(messageRaw, RuntimeInvalidMutabilityExceptionBox.init)
}

@_cdecl("__kk_concurrent_modification_exception_new_message_cause")
public func kk_concurrent_modification_exception_new_message_cause(_ messageRaw: Int, _ causeRaw: Int) -> Int {
    runtimeMakeException(messageRaw, causeRaw, RuntimeConcurrentModificationExceptionBox.init)
}

@_cdecl("__kk_concurrent_modification_exception_new_cause")
public func kk_concurrent_modification_exception_new_cause(_ causeRaw: Int) -> Int {
    runtimeMakeExceptionWithCause(causeRaw, RuntimeConcurrentModificationExceptionBox.init)
}

@_cdecl("__kk_array_index_out_of_bounds_exception_new")
public func kk_array_index_out_of_bounds_exception_new() -> Int {
    runtimeMakeException(RuntimeArrayIndexOutOfBoundsExceptionBox.init)
}

@_cdecl("__kk_array_store_exception_new")
public func kk_array_store_exception_new() -> Int {
    runtimeMakeException(RuntimeArrayStoreExceptionBox.init)
}

@_cdecl("__kk_array_store_exception_new_message")
public func kk_array_store_exception_new_message(_ messageRaw: Int) -> Int {
    runtimeMakeException(messageRaw, RuntimeArrayStoreExceptionBox.init)
}

@_cdecl("__kk_array_index_out_of_bounds_exception_new_message")
public func kk_array_index_out_of_bounds_exception_new_message(_ messageRaw: Int) -> Int {
    runtimeMakeException(messageRaw, RuntimeArrayIndexOutOfBoundsExceptionBox.init)
}

@_cdecl("__kk_string_index_out_of_bounds_exception_new")
public func kk_string_index_out_of_bounds_exception_new() -> Int {
    runtimeMakeException(RuntimeStringIndexOutOfBoundsExceptionBox.init)
}

@_cdecl("__kk_string_index_out_of_bounds_exception_new_message")
public func kk_string_index_out_of_bounds_exception_new_message(_ messageRaw: Int) -> Int {
    runtimeMakeException(messageRaw, RuntimeStringIndexOutOfBoundsExceptionBox.init)
}

@_cdecl("kk_negative_array_size_exception_new")
public func kk_negative_array_size_exception_new() -> Int {
    runtimeMakeException(RuntimeNegativeArraySizeExceptionBox.init)
}

@_cdecl("kk_negative_array_size_exception_new_message")
public func kk_negative_array_size_exception_new_message(_ messageRaw: Int) -> Int {
    runtimeMakeException(messageRaw, RuntimeNegativeArraySizeExceptionBox.init)
}

@_cdecl("__kk_freezing_exception_new")
public func kk_freezing_exception_new(_ toFreezeRaw: Int, _ blockerRaw: Int) -> Int {
    runtimeAllocateFreezingException(toFreezeRaw: toFreezeRaw, blockerRaw: blockerRaw)
}

@_cdecl("__kk_illegal_state_exception_new")
public func kk_illegal_state_exception_new() -> Int {
    runtimeMakeException(RuntimeIllegalStateExceptionBox.init)
}

@_cdecl("__kk_null_pointer_exception_new")
public func kk_null_pointer_exception_new() -> Int {
    runtimeMakeException(RuntimeNullPointerExceptionBox.init)
}

@_cdecl("__kk_illegal_state_exception_new_message")
public func kk_illegal_state_exception_new_message(_ messageRaw: Int) -> Int {
    runtimeMakeException(messageRaw, RuntimeIllegalStateExceptionBox.init)
}

@_cdecl("__kk_illegal_state_exception_new_message_cause")
public func kk_illegal_state_exception_new_message_cause(_ messageRaw: Int, _ causeRaw: Int) -> Int {
    runtimeMakeException(messageRaw, causeRaw, RuntimeIllegalStateExceptionBox.init)
}

@_cdecl("__kk_illegal_state_exception_new_cause")
public func kk_illegal_state_exception_new_cause(_ causeRaw: Int) -> Int {
    runtimeMakeExceptionWithCause(causeRaw, RuntimeIllegalStateExceptionBox.init)
}

@_cdecl("__kk_cancellation_exception_new")
public func kk_cancellation_exception_new() -> Int {
    runtimeAllocateCancellationException(message: nil)
}

@_cdecl("__kk_cancellation_exception_new_message")
public func kk_cancellation_exception_new_message(_ messageRaw: Int) -> Int {
    runtimeAllocateCancellationException(
        message: runtimeExceptionMessage(from: messageRaw, defaultMessage: nil),
        messageRaw: messageRaw
    )
}

@_cdecl("__kk_cancellation_exception_new_message_cause")
public func kk_cancellation_exception_new_message_cause(_ messageRaw: Int, _ causeRaw: Int) -> Int {
    let cause = (causeRaw == 0 || causeRaw == runtimeNullSentinelInt) ? 0 : causeRaw
    return runtimeMarkThrowableCauseInitialized(runtimeAllocateCancellationException(
        message: runtimeExceptionMessage(from: messageRaw, defaultMessage: nil),
        cause: cause,
        messageRaw: messageRaw
    ))
}

@_cdecl("__kk_cancellation_exception_new_cause")
public func kk_cancellation_exception_new_cause(_ causeRaw: Int) -> Int {
    let cause = (causeRaw == 0 || causeRaw == runtimeNullSentinelInt) ? 0 : causeRaw
    return runtimeMarkThrowableCauseInitialized(runtimeAllocateCancellationException(
        message: runtimeCauseToString(from: cause),
        cause: cause
    ))
}

@_cdecl("__kk_illegal_argument_exception_new")
public func kk_illegal_argument_exception_new() -> Int {
    runtimeMakeException(RuntimeIllegalArgumentExceptionBox.init)
}

@_cdecl("__kk_illegal_argument_exception_new_message")
public func kk_illegal_argument_exception_new_message(_ messageRaw: Int) -> Int {
    runtimeMakeException(messageRaw, RuntimeIllegalArgumentExceptionBox.init)
}

@_cdecl("__kk_illegal_argument_exception_new_message_cause")
public func kk_illegal_argument_exception_new_message_cause(_ messageRaw: Int, _ causeRaw: Int) -> Int {
    runtimeMakeException(messageRaw, causeRaw, RuntimeIllegalArgumentExceptionBox.init)
}

@_cdecl("__kk_illegal_argument_exception_new_cause")
public func kk_illegal_argument_exception_new_cause(_ causeRaw: Int) -> Int {
    runtimeMakeExceptionWithCause(causeRaw, RuntimeIllegalArgumentExceptionBox.init)
}

@_cdecl("__kk_invalid_parameter_exception_new")
public func kk_invalid_parameter_exception_new() -> Int {
    runtimeMakeException(RuntimeInvalidParameterExceptionBox.init)
}

@_cdecl("__kk_invalid_parameter_exception_new_message")
public func kk_invalid_parameter_exception_new_message(_ messageRaw: Int) -> Int {
    runtimeMakeException(messageRaw, RuntimeInvalidParameterExceptionBox.init)
}

@_cdecl("__kk_invalid_parameter_exception_new_message_cause")
public func kk_invalid_parameter_exception_new_message_cause(_ messageRaw: Int, _ causeRaw: Int) -> Int {
    runtimeMakeException(messageRaw, causeRaw, RuntimeInvalidParameterExceptionBox.init)
}

@_cdecl("__kk_invalid_parameter_exception_new_cause")
public func kk_invalid_parameter_exception_new_cause(_ causeRaw: Int) -> Int {
    runtimeMakeExceptionWithCause(causeRaw, RuntimeInvalidParameterExceptionBox.init)
}

@_cdecl("__kk_arithmetic_exception_new")
public func kk_arithmetic_exception_new() -> Int {
    runtimeMakeException(RuntimeArithmeticExceptionBox.init)
}

@_cdecl("__kk_arithmetic_exception_new_message")
public func kk_arithmetic_exception_new_message(_ messageRaw: Int) -> Int {
    runtimeMakeException(messageRaw, RuntimeArithmeticExceptionBox.init)
}

@_cdecl("__kk_assertion_error_new")
public func kk_assertion_error_new() -> Int {
    runtimeMakeException(RuntimeAssertionErrorBox.init)
}

@_cdecl("__kk_assertion_error_new_message")
public func kk_assertion_error_new_message(_ messageRaw: Int) -> Int {
    // `AssertionError(Any?)` renders arbitrary arguments; only an actual
    // `String` argument keeps its reference (`String.valueOf` identity on JVM).
    runtimeAllocateAssertionError(
        message: runtimeAssertionErrorMessage(from: messageRaw),
        messageRaw: runtimeThrowableStringMessageRaw(messageRaw)
    )
}

@_cdecl("__kk_assertion_error_new_message_cause")
public func kk_assertion_error_new_message_cause(_ messageRaw: Int, _ causeRaw: Int) -> Int {
    runtimeMakeException(messageRaw, causeRaw, RuntimeAssertionErrorBox.init)
}

@_cdecl("__kk_uninitialized_property_access_exception_new")
public func kk_uninitialized_property_access_exception_new() -> Int {
    runtimeMakeException(RuntimeUninitializedPropertyAccessExceptionBox.init)
}

@_cdecl("__kk_uninitialized_property_access_exception_new_message")
public func kk_uninitialized_property_access_exception_new_message(_ messageRaw: Int) -> Int {
    runtimeMakeException(messageRaw, RuntimeUninitializedPropertyAccessExceptionBox.init)
}

@_cdecl("__kk_uninitialized_property_access_exception_new_message_cause")
public func kk_uninitialized_property_access_exception_new_message_cause(_ messageRaw: Int, _ causeRaw: Int) -> Int {
    runtimeMakeException(messageRaw, causeRaw, RuntimeUninitializedPropertyAccessExceptionBox.init)
}

@_cdecl("__kk_uninitialized_property_access_exception_new_cause")
public func kk_uninitialized_property_access_exception_new_cause(_ causeRaw: Int) -> Int {
    runtimeMakeExceptionWithCause(causeRaw, RuntimeUninitializedPropertyAccessExceptionBox.init)
}

@_cdecl("__kk_exception_new")
public func kk_exception_new() -> Int {
    runtimeMakeException(RuntimeExceptionBox.init)
}

@_cdecl("__kk_exception_new_message")
public func kk_exception_new_message(_ messageRaw: Int) -> Int {
    runtimeMakeException(messageRaw, RuntimeExceptionBox.init)
}

@_cdecl("__kk_exception_new_message_cause")
public func kk_exception_new_message_cause(_ messageRaw: Int, _ causeRaw: Int) -> Int {
    runtimeMakeException(messageRaw, causeRaw, RuntimeExceptionBox.init)
}

@_cdecl("__kk_exception_new_cause")
public func kk_exception_new_cause(_ causeRaw: Int) -> Int {
    runtimeMakeExceptionWithCause(causeRaw, RuntimeExceptionBox.init)
}

@_cdecl("__kk_character_coding_exception_new")
public func kk_character_coding_exception_new() -> Int {
    runtimeMakeException(RuntimeCharacterCodingExceptionBox.init)
}

@_cdecl("__kk_character_coding_exception_new_message")
public func kk_character_coding_exception_new_message(_ messageRaw: Int) -> Int {
    runtimeMakeException(messageRaw, RuntimeCharacterCodingExceptionBox.init)
}

@_cdecl("__kk_kotlin_nothing_value_exception_new")
public func kk_kotlin_nothing_value_exception_new() -> Int {
    runtimeMakeException(RuntimeKotlinNothingValueExceptionBox.init)
}

@_cdecl("__kk_kotlin_nothing_value_exception_new_message")
public func kk_kotlin_nothing_value_exception_new_message(_ messageRaw: Int) -> Int {
    runtimeMakeException(messageRaw, RuntimeKotlinNothingValueExceptionBox.init)
}

@_cdecl("__kk_kotlin_nothing_value_exception_new_message_cause")
public func kk_kotlin_nothing_value_exception_new_message_cause(_ messageRaw: Int, _ causeRaw: Int) -> Int {
    runtimeMakeException(messageRaw, causeRaw, RuntimeKotlinNothingValueExceptionBox.init)
}

@_cdecl("__kk_kotlin_nothing_value_exception_new_cause")
public func kk_kotlin_nothing_value_exception_new_cause(_ causeRaw: Int) -> Int {
    runtimeMakeExceptionWithCause(causeRaw, RuntimeKotlinNothingValueExceptionBox.init)
}

@_cdecl("__kk_error_new")
public func kk_error_new() -> Int {
    runtimeMakeException(RuntimeErrorBox.init)
}

@_cdecl("__kk_error_new_message")
public func kk_error_new_message(_ messageRaw: Int) -> Int {
    runtimeMakeException(messageRaw, RuntimeErrorBox.init)
}

@_cdecl("__kk_error_new_message_cause")
public func kk_error_new_message_cause(_ messageRaw: Int, _ causeRaw: Int) -> Int {
    runtimeMakeException(messageRaw, causeRaw, RuntimeErrorBox.init)
}

@_cdecl("__kk_error_new_cause")
public func kk_error_new_cause(_ causeRaw: Int) -> Int {
    runtimeMakeExceptionWithCause(causeRaw, RuntimeErrorBox.init)
}

@_cdecl("__kk_exception_in_initializer_error_new")
public func kk_exception_in_initializer_error_new() -> Int {
    runtimeMakeException(RuntimeExceptionInInitializerErrorBox.init)
}

@_cdecl("__kk_exception_in_initializer_error_new_message")
public func kk_exception_in_initializer_error_new_message(_ messageRaw: Int) -> Int {
    runtimeMakeException(messageRaw, RuntimeExceptionInInitializerErrorBox.init)
}

@_cdecl("__kk_exception_in_initializer_error_new_cause")
public func kk_exception_in_initializer_error_new_cause(_ causeRaw: Int) -> Int {
    runtimeMakeExceptionWithCause(causeRaw, RuntimeExceptionInInitializerErrorBox.init)
}

@_cdecl("__kk_kotlin_reflection_not_supported_error_new")
public func kk_kotlin_reflection_not_supported_error_new() -> Int {
    runtimeMakeException(RuntimeKotlinReflectionNotSupportedErrorBox.init)
}

@_cdecl("__kk_kotlin_reflection_not_supported_error_new_message")
public func kk_kotlin_reflection_not_supported_error_new_message(_ messageRaw: Int) -> Int {
    runtimeMakeException(messageRaw, RuntimeKotlinReflectionNotSupportedErrorBox.init)
}

@_cdecl("__kk_kotlin_reflection_not_supported_error_new_message_cause")
public func kk_kotlin_reflection_not_supported_error_new_message_cause(_ messageRaw: Int, _ causeRaw: Int) -> Int {
    runtimeMakeException(messageRaw, causeRaw, RuntimeKotlinReflectionNotSupportedErrorBox.init)
}

@_cdecl("__kk_kotlin_reflection_not_supported_error_new_cause")
public func kk_kotlin_reflection_not_supported_error_new_cause(_ causeRaw: Int) -> Int {
    runtimeMakeExceptionWithCause(causeRaw, RuntimeKotlinReflectionNotSupportedErrorBox.init)
}

@_cdecl("__kk_out_of_memory_error_new")
public func kk_out_of_memory_error_new() -> Int {
    runtimeMakeException(RuntimeOutOfMemoryErrorBox.init)
}

@_cdecl("__kk_out_of_memory_error_new_message")
public func kk_out_of_memory_error_new_message(_ messageRaw: Int) -> Int {
    runtimeMakeException(messageRaw, RuntimeOutOfMemoryErrorBox.init)
}

@_cdecl("__kk_stack_overflow_error_new")
public func kk_stack_overflow_error_new() -> Int {
    runtimeMakeException(RuntimeStackOverflowErrorBox.init)
}

@_cdecl("__kk_stack_overflow_error_new_message")
public func kk_stack_overflow_error_new_message(_ messageRaw: Int) -> Int {
    runtimeMakeException(messageRaw, RuntimeStackOverflowErrorBox.init)
}

@_cdecl("__kk_stack_overflow_error_new_message_cause")
public func kk_stack_overflow_error_new_message_cause(_ messageRaw: Int, _ causeRaw: Int) -> Int {
    runtimeMakeException(messageRaw, causeRaw, RuntimeStackOverflowErrorBox.init)
}

@_cdecl("__kk_stack_overflow_error_new_cause")
public func kk_stack_overflow_error_new_cause(_ causeRaw: Int) -> Int {
    runtimeMakeExceptionWithCause(causeRaw, RuntimeStackOverflowErrorBox.init)
}

@_cdecl("__kk_not_implemented_error_new")
public func __kk_not_implemented_error_new() -> Int {
    runtimeAllocateNotImplementedError(message: runtimeNotImplementedDefaultMessage)
}

@_cdecl("__kk_not_implemented_error_new_message")
public func __kk_not_implemented_error_new_message(_ messageRaw: Int) -> Int {
    runtimeAllocateNotImplementedError(
        message: runtimeExceptionMessage(from: messageRaw, defaultMessage: runtimeNotImplementedDefaultMessage)
            ?? runtimeNotImplementedDefaultMessage,
        messageRaw: messageRaw
    )
}

@_cdecl("__kk_unsupported_operation_exception_new")
public func kk_unsupported_operation_exception_new() -> Int {
    runtimeMakeException(RuntimeUnsupportedOperationExceptionBox.init)
}

@_cdecl("__kk_unsupported_operation_exception_new_message")
public func kk_unsupported_operation_exception_new_message(_ messageRaw: Int) -> Int {
    runtimeMakeException(messageRaw, RuntimeUnsupportedOperationExceptionBox.init)
}

@_cdecl("__kk_unsupported_operation_exception_new_message_cause")
public func kk_unsupported_operation_exception_new_message_cause(_ messageRaw: Int, _ causeRaw: Int) -> Int {
    runtimeMakeException(messageRaw, causeRaw, RuntimeUnsupportedOperationExceptionBox.init)
}

@_cdecl("__kk_unsupported_operation_exception_new_cause")
public func kk_unsupported_operation_exception_new_cause(_ causeRaw: Int) -> Int {
    runtimeMakeExceptionWithCause(causeRaw, RuntimeUnsupportedOperationExceptionBox.init)
}

@_cdecl("__kk_no_such_element_exception_new")
public func kk_no_such_element_exception_new() -> Int {
    runtimeMakeException(RuntimeNoSuchElementExceptionBox.init)
}

@_cdecl("__kk_no_such_element_exception_new_message")
public func kk_no_such_element_exception_new_message(_ messageRaw: Int) -> Int {
    runtimeMakeException(messageRaw, RuntimeNoSuchElementExceptionBox.init)
}

@_cdecl("__kk_class_cast_exception_new")
public func kk_class_cast_exception_new() -> Int {
    runtimeMakeException(RuntimeClassCastExceptionBox.init)
}

@_cdecl("__kk_class_cast_exception_new_message")
public func kk_class_cast_exception_new_message(_ messageRaw: Int) -> Int {
    runtimeMakeException(messageRaw, RuntimeClassCastExceptionBox.init)
}

@_cdecl("__kk_type_cast_exception_new")
public func kk_type_cast_exception_new() -> Int {
    runtimeMakeException(RuntimeTypeCastExceptionBox.init)
}

@_cdecl("__kk_type_cast_exception_new_message")
public func kk_type_cast_exception_new_message(_ messageRaw: Int) -> Int {
    runtimeMakeException(messageRaw, RuntimeTypeCastExceptionBox.init)
}
