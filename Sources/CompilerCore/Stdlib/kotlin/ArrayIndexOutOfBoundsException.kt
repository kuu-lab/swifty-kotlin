/*
 * Copyright 2010-2019 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Use of this source code is governed by the Apache 2.0 license that can be found
 * in the license/LICENSE.txt file.
 */

package kotlin

import kotlin.internal.KsSymbolName

/**
 * Thrown when an array is accessed with an index that is out of bounds.
 */
public open class ArrayIndexOutOfBoundsException : IndexOutOfBoundsException {
    @KsSymbolName("__kk_array_index_out_of_bounds_exception_new")
    public constructor()

    @KsSymbolName("__kk_array_index_out_of_bounds_exception_new_message")
    public constructor(message: String?)
}
