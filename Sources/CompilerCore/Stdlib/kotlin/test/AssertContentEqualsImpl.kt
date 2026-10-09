/*
 * Copyright 2010-2021 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 * Derived from JetBrains/kotlin revision 150f34458460c5d688ba80e13f269ca6715f32b4.
 * Stable APIs follow Kotlin 2.3.10; experimental lazy messages retain their 2.4 version marker.
 */
@file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")
@file:OptIn(kotlin.contracts.ExperimentalContracts::class, kotlin.ExperimentalUnsignedTypes::class)
package kotlin.test

import kotlin.contracts.contract

internal fun <T> assertArrayContentEquals(
    message: String?,
    expected: T?,
    actual: T?,
    size: (T) -> Int,
    get: T.(Int) -> Any?,
    contentToString: T?.() -> String,
    contentEquals: T?.(T?) -> Boolean
) = assertArrayContentEquals({ message }, expected, actual, size, get, contentToString, contentEquals)

internal fun <T> assertArrayContentEquals(
    lazyMessage: () -> String?,
    expected: T?,
    actual: T?,
    size: (T) -> Int,
    get: T.(Int) -> Any?,
    contentToString: T?.() -> String,
    contentEquals: T?.(T?) -> Boolean
) {
    if (expected.contentEquals(actual)) return

    val typeName = "Array"

    if (checkReferenceAndNullEquality(typeName, lazyMessage, expected, actual, contentToString)) return

    val expectedSize = size(expected)
    val actualSize = size(actual)

    if (expectedSize != actualSize) {
        val sizesDifferMessage = "$typeName sizes differ. Expected size is $expectedSize, actual size is $actualSize."
        val toString = "Expected <${expected.contentToString()}>, actual <${actual.contentToString()}>."

        fail(messagePrefix(lazyMessage()) + sizesDifferMessage + "\n" + toString)
    }

    for (index in 0 until expectedSize) {
        val expectedElement = expected.get(index)
        val actualElement = actual.get(index)

        if (expectedElement != actualElement) {
            val elementsDifferMessage = elementsDifferMessage(typeName, index, expectedElement, actualElement)
            val toString = "Expected <${expected.contentToString()}>, actual <${actual.contentToString()}>."

            fail(messagePrefix(lazyMessage()) + elementsDifferMessage + "\n" + toString)
        }
    }
}

private fun <T> checkReferenceAndNullEquality(
    typeName: String,
    message: String?,
    expected: T?,
    actual: T?,
    contentToString: T?.() -> String
): Boolean = checkReferenceAndNullEquality(typeName, { message }, expected, actual, contentToString)

private fun <T> checkReferenceAndNullEquality(
    typeName: String,
    lazyMessage: () -> String?,
    expected: T?,
    actual: T?,
    contentToString: T?.() -> String
): Boolean {
    contract {
        returns(false) implies (expected != null && actual != null)
    }

    if (expected === actual) {
        return true
    }
    if (expected == null) {
        fail(messagePrefix(lazyMessage()) + "Expected <null> $typeName, actual <${actual.contentToString()}>.")
    }
    if (actual == null) {
        fail(messagePrefix(lazyMessage()) + "Expected non-null $typeName <${expected.contentToString()}>, actual <null>.")
    }

    return false
}

private fun elementsDifferMessage(typeName: String, index: Int, expectedElement: Any?, actualElement: Any?): String =
    "$typeName elements differ at index $index. Expected element <$expectedElement>, actual element <${actualElement}>."
