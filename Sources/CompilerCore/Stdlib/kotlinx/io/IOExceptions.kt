/*
 * Copyright 2017-2024 JetBrains s.r.o. and respective authors and developers.
 * Use of this source code is governed by the Apache 2.0 license that can be found in the LICENCE file.
 *
 * Derived from kotlinx-io core/common/src/-CommonPlatform.kt and core/native/src/-NonJvmPlatform.kt (tag 0.9.1).
 * kotlinx-io declares these as `expect`/`actual` per platform; this compiler has a single target, so
 * the Native `actual` bodies are inlined directly as plain classes.
 */
package kotlinx.io

import kotlin.__kkThrowableSetCause
import kotlin.__kkThrowableSetMessage

/**
 * Signals that an I/O exception of some sort has occurred.
 */
public open class IOException : Exception {
    public constructor() : super() {
        __kkThrowableSetMessage(this, null)
    }

    public constructor(message: String?) : super(message) {
        __kkThrowableSetMessage(this, message)
    }

    public constructor(cause: Throwable?) : super(null, cause) {
        __kkThrowableSetMessage(this, null)
        __kkThrowableSetCause(this, cause)
    }

    public constructor(message: String?, cause: Throwable?) : super(message, cause) {
        __kkThrowableSetMessage(this, message)
        __kkThrowableSetCause(this, cause)
    }
}

/**
 * Signals that the end of the file or stream was reached unexpectedly during an input operation.
 */
public open class EOFException : IOException {
    public constructor() : super()
    public constructor(message: String?) : super(message)
}
