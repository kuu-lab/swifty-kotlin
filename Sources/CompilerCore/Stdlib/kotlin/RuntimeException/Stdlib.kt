/*
 * Copyright 2010-2020 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Use of this source code is governed by the Apache 2.0 license that can be found
 * in the license/LICENSE.txt file.
 */

package kotlin

/**
 * The common superclass for exceptions caused by incorrect program logic or
 * invalid state.
 */
public open class RuntimeException : Exception {
    public constructor() : super() {
        __kkThrowableSetMessage(this, null)
    }

    public constructor(message: String?) : super(message) {
        __kkThrowableSetMessage(this, message)
    }

    public constructor(message: String?, cause: Throwable?) : super(message, cause) {
        __kkThrowableSetMessage(this, message)
        __kkThrowableSetCause(this, cause)
    }

    // Like the JVM, a cause-only exception derives its message from
    // `cause.toString()`; the runtime-backed super constructor provides that.
    public constructor(cause: Throwable?) : super(cause)
}
