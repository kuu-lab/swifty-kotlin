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
import kotlin.internal.OnlyInputTypes

/** Evaluates [block] once and asserts its result equals [expected]. */
public inline fun <@OnlyInputTypes T> expect(expected: T, block: () -> T) {
    contract { callsInPlace(block, InvocationKind.EXACTLY_ONCE) }
    val actual = block()
    asserter.assertEquals(null, expected, actual)
}

/** Evaluates [block] once and uses [message] when its result differs. */
public inline fun <@OnlyInputTypes T> expect(expected: T, message: String?, block: () -> T) {
    contract { callsInPlace(block, InvocationKind.EXACTLY_ONCE) }
    val actual = block()
    asserter.assertEquals(message, expected, actual)
}
