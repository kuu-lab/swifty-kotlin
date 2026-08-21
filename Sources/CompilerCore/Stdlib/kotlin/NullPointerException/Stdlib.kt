/*
 * Copyright 2010-2019 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Use of this source code is governed by the Apache 2.0 license that can be found
 * in the license/LICENSE.txt file.
 */

package kotlin

/**
 * Thrown when an application attempts to use a null reference.
 */
public open class NullPointerException : RuntimeException {
    public constructor() : super() {
        __kkThrowableSetMessage(this, null)
    }

    public constructor(message: String?) : super(message) {
        __kkThrowableSetMessage(this, message)
    }
}
