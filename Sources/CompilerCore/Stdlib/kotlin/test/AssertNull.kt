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

/** Asserts that [actual] is null. */
public fun assertNull(actual: Any?, message: String? = null) {
    contract { returns() implies (actual == null) }
    asserter.assertNull(message, actual)
}

/** Asserts that [actual] is non-null and returns it with its non-null type. */
@IgnorableReturnValue
public fun <T : Any> assertNotNull(actual: T?, message: String? = null): T {
    contract { returns() implies (actual != null) }
    asserter.assertNotNull(message, actual)
    return actual!!
}
