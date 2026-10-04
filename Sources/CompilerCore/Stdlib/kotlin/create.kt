/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/util/Result.kt.
 */

package kotlin

/**
 * Creates the opaque failure payload used by the bundled Result representation.
 *
 * The runtime stores the Throwable directly in its Result failure box, so no
 * separate Kotlin marker object is needed here.
 */
@PublishedApi
@SinceKotlin("1.3")
internal fun createFailure(exception: Throwable): Any = exception
