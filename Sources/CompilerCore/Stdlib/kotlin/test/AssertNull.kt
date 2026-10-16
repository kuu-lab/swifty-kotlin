/*
 * Copyright 2010-2021 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-test libraries/kotlin.test/common/src/main/kotlin/kotlin/test/Assertions.kt.
 * Stable APIs follow Kotlin 2.3.10; experimental lazy messages retain their 2.4 version marker.
 * Upstream revision: 150f34458460c5d688ba80e13f269ca6715f32b4.
 */

@file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")
@file:OptIn(kotlin.contracts.ExperimentalContracts::class)

package kotlin.test

import kotlin.contracts.*
import kotlin.internal.InlineOnly

/** Asserts that [actual] is null. */
public fun assertNull(actual: Any?, message: String? = null) {
    contract { returns() implies (actual == null) }
    asserter.assertNull(message, actual)
}

/** Asserts that [actual] is null, evaluating [lazyMessage] only if the assertion fails. */
@SinceKotlin("2.4")
@ExperimentalKotlinTestApi
public fun assertNull(actual: Any?, lazyMessage: () -> String) {
    contract { returns() implies (actual == null) }
    if (actual != null) assertNull(actual, lazyMessage())
}

/** Asserts that [actual] is non-null and returns it with its non-null type. */
@IgnorableReturnValue
public fun <T : Any> assertNotNull(actual: T?, message: String? = null): T {
    contract { returns() implies (actual != null) }
    asserter.assertNotNull(message, actual)
    return actual!!
}

/** Asserts that [actual] is non-null, evaluating [lazyMessage] only if the assertion fails. */
@SinceKotlin("2.4")
@ExperimentalKotlinTestApi
@IgnorableReturnValue
public fun <T : Any> assertNotNull(actual: T?, lazyMessage: () -> String): T {
    contract { returns() implies (actual != null) }
    if (actual == null) assertNotNull(actual, lazyMessage())
    return actual!!
}

/**
 * Asserts that [actual] is non-null and passes it to [block].
 *
 * The block is not a lazy error message generator. Use `assertNotNull(actual, message).let(block)` instead.
 */
@Deprecated(
    message = "This assertNotNull overload proved to be misused and will be removed soon. " +
        "If you need to perform some actions on the asserted value within a new lexical scope, " +
        "consider using assertNotNull(...).let { } instead. " +
        "Note that there are no assertNotNull overloads accepting the lazy message at the moment.",
    level = DeprecationLevel.WARNING,
    replaceWith = ReplaceWith("assertNotNull(actual, message).let(block)")
)
@InlineOnly
public inline fun <T : Any, R> assertNotNull(actual: T?, message: String? = null, block: (T) -> R) {
    contract { returns() implies (actual != null) }
    val _ = block(assertNotNull(actual, message))
}
