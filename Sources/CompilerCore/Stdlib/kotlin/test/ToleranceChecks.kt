/*
 * Copyright 2010-2021 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 * Derived from JetBrains/kotlin revision 150f34458460c5d688ba80e13f269ca6715f32b4.
 * Stable APIs follow Kotlin 2.3.10; experimental lazy messages retain their 2.4 version marker.
 */
@file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")
@file:OptIn(kotlin.contracts.ExperimentalContracts::class, kotlin.ExperimentalUnsignedTypes::class)
package kotlin.test

import kotlin.math.abs

private fun checkAbsoluteTolerance(absoluteTolerance: Double) {
    require(absoluteTolerance >= 0.0) { "Illegal negative absolute tolerance <$absoluteTolerance>." }
    require(!absoluteTolerance.isNaN()) { "Illegal NaN absolute tolerance <$absoluteTolerance>." }
}

internal fun checkDoublesAreEqual(
    expected: Double,
    actual: Double,
    absoluteTolerance: Double,
    message: String?,
    shouldFail: Boolean = false
) {
    checkDoublesAreEqual(expected, actual, absoluteTolerance, { message }, shouldFail)
}

internal fun checkDoublesAreEqual(
    expected: Double,
    actual: Double,
    absoluteTolerance: Double,
    lazyMessage: () -> String?,
    shouldFail: Boolean = false
) {
    checkAbsoluteTolerance(absoluteTolerance)
    val equal = expected.toBits() == actual.toBits() || abs(expected - actual) <= absoluteTolerance

    asserter.assertTrue(
        { messagePrefix(lazyMessage()) + "Expected <$expected> with absolute tolerance <$absoluteTolerance>, actual <$actual>." },
        equal != shouldFail
    )
}

internal fun checkFloatsAreEqual(
    expected: Float,
    actual: Float,
    absoluteTolerance: Float,
    message: String?,
    shouldFail: Boolean = false
) {
    checkFloatsAreEqual(expected, actual, absoluteTolerance, { message }, shouldFail)
}

internal fun checkFloatsAreEqual(
    expected: Float,
    actual: Float,
    absoluteTolerance: Float,
    lazyMessage: () -> String?,
    shouldFail: Boolean = false
) {
    checkAbsoluteTolerance(absoluteTolerance.toDouble())
    val equal = expected.toBits() == actual.toBits() || abs(expected - actual) <= absoluteTolerance

    asserter.assertTrue(
        { messagePrefix(lazyMessage()) + "Expected <$expected> with absolute tolerance <$absoluteTolerance>, actual <$actual>." },
        equal != shouldFail
    )
}
