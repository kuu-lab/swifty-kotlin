/*
 * Copyright 2010-2020 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 * Derived from libraries/stdlib/common-non-jvm/src/kotlin/coroutines/cancellation/CancellationException.kt.
 */
package kotlin.coroutines.cancellation

import kotlin.internal.InlineOnly

// Keep constructor calls behind differently named helpers. Calling
// CancellationException(...) from a hidden factory body also discovers that
// same hidden factory before constructor candidates are added, which makes the
// factory diagnose its own body as a hidden-deprecation use.
@PublishedApi
internal fun createCancellationException(message: String?, cause: Throwable?): CancellationException =
    CancellationException(message, cause)

@PublishedApi
internal fun createCancellationException(cause: Throwable?): CancellationException =
    CancellationException(cause)

// The Native constructors are declared in CancellationExceptionH.kt. These
// hidden factories preserve the common expect/actual API's source ownership.
@SinceKotlin("1.4")
@Deprecated("Provided for expect-actual matching", level = DeprecationLevel.HIDDEN)
@InlineOnly
public inline fun CancellationException(message: String?, cause: Throwable?): CancellationException =
    createCancellationException(message, cause)

@SinceKotlin("1.4")
@Deprecated("Provided for expect-actual matching", level = DeprecationLevel.HIDDEN)
@InlineOnly
public inline fun CancellationException(cause: Throwable?): CancellationException =
    createCancellationException(cause)
