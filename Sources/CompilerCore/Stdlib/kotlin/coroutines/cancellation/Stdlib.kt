/*
 * Copyright 2010-2020 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 * Derived from libraries/stdlib/common-non-jvm/src/kotlin/coroutines/cancellation/CancellationException.kt.
 */
package kotlin.coroutines.cancellation

import kotlin.internal.InlineOnly

// The Native constructors are declared in CancellationExceptionH.kt. These
// hidden factories preserve the common expect/actual API's source ownership.
@SinceKotlin("1.4")
@Deprecated("Provided for expect-actual matching", level = DeprecationLevel.HIDDEN)
@InlineOnly
public inline fun CancellationException(message: String?, cause: Throwable?): CancellationException =
    CancellationException(message, cause)

@SinceKotlin("1.4")
@Deprecated("Provided for expect-actual matching", level = DeprecationLevel.HIDDEN)
@InlineOnly
public inline fun CancellationException(cause: Throwable?): CancellationException =
    CancellationException(cause)
