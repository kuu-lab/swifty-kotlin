/*
 * Copyright 2010-2020 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Use of this source code is governed by the Apache 2.0 license that can be found
 * in the license/LICENSE.txt file.
 */

package kotlin

import kotlin.internal.KsSymbolName

// KSP-851: source owner for the complete IllegalStateException constructor surface.
// The runtime-backed constructors preserve typed throwable identity and storage.

public open class IllegalStateException : RuntimeException {
    @KsSymbolName("__kk_illegal_state_exception_new")
    public constructor()

    @KsSymbolName("__kk_illegal_state_exception_new_message")
    public constructor(message: String?)

    @KsSymbolName("__kk_illegal_state_exception_new_message_cause")
    public constructor(message: String?, cause: Throwable?)

    @KsSymbolName("__kk_illegal_state_exception_new_cause")
    public constructor(cause: Throwable?)
}
