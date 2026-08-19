/*
 * Copyright 2010-2020 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Use of this source code is governed by the Apache 2.0 license that can be found
 * in the license/LICENSE.txt file.
 */

package kotlin

import kotlin.internal.KsSymbolName

// KSP-656: Kotlin common exception hierarchy.
//
// The runtime still owns throwable storage and type identity. Each constructor
// is therefore a direct allocation bridge instead of a Kotlin delegation to
// Throwable, which would allocate a second storage-less object.

public open class Error : Throwable {
    @KsSymbolName("__kk_error_new")
    public constructor()

    @KsSymbolName("__kk_error_new_message")
    public constructor(message: String?)

    @KsSymbolName("__kk_error_new_message_cause")
    public constructor(message: String?, cause: Throwable?)

    @KsSymbolName("__kk_error_new_cause")
    public constructor(cause: Throwable?)
}

public open class Exception : Throwable {
    @KsSymbolName("__kk_exception_new")
    public constructor()

    @KsSymbolName("__kk_exception_new_message")
    public constructor(message: String?)

    @KsSymbolName("__kk_exception_new_message_cause")
    public constructor(message: String?, cause: Throwable?)

    @KsSymbolName("__kk_exception_new_cause")
    public constructor(cause: Throwable?)
}

public open class RuntimeException : Exception {
    @KsSymbolName("__kk_runtime_exception_new")
    public constructor()

    @KsSymbolName("__kk_runtime_exception_new_message")
    public constructor(message: String?)

    @KsSymbolName("__kk_runtime_exception_new_message_cause")
    public constructor(message: String?, cause: Throwable?)

    @KsSymbolName("__kk_runtime_exception_new_cause")
    public constructor(cause: Throwable?)
}

public open class IllegalArgumentException : RuntimeException {
    @KsSymbolName("__kk_illegal_argument_exception_new")
    public constructor()

    @KsSymbolName("__kk_illegal_argument_exception_new_message")
    public constructor(message: String?)

    @KsSymbolName("__kk_illegal_argument_exception_new_message_cause")
    public constructor(message: String?, cause: Throwable?)

    @KsSymbolName("__kk_illegal_argument_exception_new_cause")
    public constructor(cause: Throwable?)
}

public open class IndexOutOfBoundsException : RuntimeException {
    @KsSymbolName("__kk_index_out_of_bounds_exception_new")
    public constructor()

    @KsSymbolName("__kk_index_out_of_bounds_exception_new_message")
    public constructor(message: String?)
}

public open class ConcurrentModificationException : RuntimeException {
    @KsSymbolName("__kk_concurrent_modification_exception_new")
    public constructor()

    @KsSymbolName("__kk_concurrent_modification_exception_new_message")
    public constructor(message: String?)

    @KsSymbolName("__kk_concurrent_modification_exception_new_message_cause")
    public constructor(message: String?, cause: Throwable?)

    @KsSymbolName("__kk_concurrent_modification_exception_new_cause")
    public constructor(cause: Throwable?)
}

public open class UnsupportedOperationException : RuntimeException {
    @KsSymbolName("__kk_unsupported_operation_exception_new")
    public constructor()

    @KsSymbolName("__kk_unsupported_operation_exception_new_message")
    public constructor(message: String?)

    @KsSymbolName("__kk_unsupported_operation_exception_new_message_cause")
    public constructor(message: String?, cause: Throwable?)

    @KsSymbolName("__kk_unsupported_operation_exception_new_cause")
    public constructor(cause: Throwable?)
}

public open class NumberFormatException : IllegalArgumentException {
    @KsSymbolName("__kk_number_format_exception_new")
    public constructor()

    @KsSymbolName("__kk_number_format_exception_new_message")
    public constructor(message: String?)
}

public open class NullPointerException : RuntimeException {
    @KsSymbolName("__kk_null_pointer_exception_new")
    public constructor()

    @KsSymbolName("__kk_null_pointer_exception_new_message")
    public constructor(message: String?)
}

public open class ClassCastException : RuntimeException {
    @KsSymbolName("__kk_class_cast_exception_new")
    public constructor()

    @KsSymbolName("__kk_class_cast_exception_new_message")
    public constructor(message: String?)
}

public open class AssertionError : Error {
    @KsSymbolName("__kk_assertion_error_new")
    public constructor()

    @KsSymbolName("__kk_assertion_error_new_message")
    public constructor(message: Any?)

    @KsSymbolName("__kk_assertion_error_new_message_cause")
    public constructor(message: String?, cause: Throwable?)
}

public open class NoSuchElementException : RuntimeException {
    @KsSymbolName("__kk_no_such_element_exception_new")
    public constructor()

    @KsSymbolName("__kk_no_such_element_exception_new_message")
    public constructor(message: String?)
}

public open class ArithmeticException : RuntimeException {
    @KsSymbolName("__kk_arithmetic_exception_new")
    public constructor()

    @KsSymbolName("__kk_arithmetic_exception_new_message")
    public constructor(message: String?)
}

public open class NoWhenBranchMatchedException : RuntimeException {
    @KsSymbolName("__kk_no_when_branch_matched_exception_new")
    public constructor()

    @KsSymbolName("__kk_no_when_branch_matched_exception_new_message")
    public constructor(message: String?)

    @KsSymbolName("__kk_no_when_branch_matched_exception_new_message_cause")
    public constructor(message: String?, cause: Throwable?)

    @KsSymbolName("__kk_no_when_branch_matched_exception_new_cause")
    public constructor(cause: Throwable?)
}

public class UninitializedPropertyAccessException : RuntimeException {
    @KsSymbolName("__kk_uninitialized_property_access_exception_new")
    public constructor()

    @KsSymbolName("__kk_uninitialized_property_access_exception_new_message")
    public constructor(message: String?)

    @KsSymbolName("__kk_uninitialized_property_access_exception_new_message_cause")
    public constructor(message: String?, cause: Throwable?)

    @KsSymbolName("__kk_uninitialized_property_access_exception_new_cause")
    public constructor(cause: Throwable?)
}
