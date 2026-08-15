/*
 * Copyright 2010-2019 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Use of this source code is governed by the Apache 2.0 license that can be found
 * in the license/LICENSE.txt file.
 */

package kotlin.text

import kotlin.Exception
import kotlin.internal.KsSymbolName

/**
 * The exception thrown when a character encoding or decoding error occurs.
 */
public open class CharacterCodingException : Exception {
    @KsSymbolName("__kk_throwable_new")
    public constructor()

    @KsSymbolName("__kk_throwable_new")
    public constructor(message: String?)
}
