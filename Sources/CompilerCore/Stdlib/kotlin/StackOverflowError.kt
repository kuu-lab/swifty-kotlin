/*
 * Copyright 2010-2020 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Use of this source code is governed by the Apache 2.0 license that can be found
 * in the license/LICENSE.txt file.
 */

package kotlin

import kotlin.internal.KsSymbolName

public open class StackOverflowError : Error {
    @KsSymbolName("__kk_stack_overflow_error_new")
    public constructor()

    @KsSymbolName("__kk_stack_overflow_error_new_message")
    public constructor(message: String?)

    @KsSymbolName("__kk_stack_overflow_error_new_message_cause")
    public constructor(message: String?, cause: Throwable?)

    @KsSymbolName("__kk_stack_overflow_error_new_cause")
    public constructor(cause: Throwable?)
}
