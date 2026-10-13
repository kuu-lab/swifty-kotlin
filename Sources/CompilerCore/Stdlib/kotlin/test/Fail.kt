/*
 * Copyright 2010-2021 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-test libraries/kotlin.test/common/src/main/kotlin/kotlin/test/Assertions.kt.
 * Stable APIs follow Kotlin 2.3.10; experimental lazy messages retain their 2.4 version marker.
 * Upstream revision: 150f34458460c5d688ba80e13f269ca6715f32b4.
 */

@file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")

package kotlin.test


/** Marks a test as having failed if this point in the execution path is reached, with an optional [message]. */
public fun fail(message: String? = null): Nothing {
    asserter.fail(message)
}

/**
 * Marks a test as having failed if this point in the execution path is reached, with an optional [message]
 * and [cause] exception.
 *
 * The [cause] exception is set as the root cause of the test failure.
 */
@SinceKotlin("1.4")
public fun fail(message: String? = null, cause: Throwable? = null): Nothing {
    asserter.fail(message, cause)
}
