/*
 * Copyright 2010-2021 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 * Derived from JetBrains/kotlin revision 150f34458460c5d688ba80e13f269ca6715f32b4.
 * Stable APIs follow Kotlin 2.3.10; experimental lazy messages retain their 2.4 version marker.
 */
@file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")
@file:OptIn(kotlin.contracts.ExperimentalContracts::class, kotlin.ExperimentalUnsignedTypes::class)
package kotlin.test

import kotlin.internal.OnlyInputTypes

/**
 * Two iterables are considered structurally equal if they have the same size, and elements at corresponding positions,
 * following the iteration order, are equal. Elements are compared for equality using the [equals][Any.equals] function.
 *
 * The iterables are also considered equal if both are `null`.
 */
@SinceKotlin("1.5")
public fun <@OnlyInputTypes T> assertContentEquals(expected: Iterable<T>?, actual: Iterable<T>?, message: String? = null) {
    assertIterableContentEquals("Iterable", message, expected, actual, Iterable<*>::iterator)
}

/**
 * Two iterables are considered structurally equal if they have the same size, and elements at corresponding positions,
 * following the iteration order, are equal. Elements are compared for equality using the [equals][Any.equals] function.
 *
 * The iterables are also considered equal if both are `null`.
 */
@SinceKotlin("2.4")
@ExperimentalKotlinTestApi
public fun <@OnlyInputTypes T> assertContentEquals(expected: Iterable<T>?, actual: Iterable<T>?, lazyMessage: () -> String) {
    assertIterableContentEquals("Iterable", lazyMessage, expected, actual, Iterable<*>::iterator)
}

/**
 * Two sets are compared by the order of their elements.
 *
 * The sets are also considered equal if both are `null`.
 */
@SinceKotlin("1.5")
@Deprecated(
    "'assertContentEquals' for Set arguments is ambiguous. Use 'assertEquals' to compare content with the unordered set equality, or cast one of arguments to Iterable to compare the set elements in order of iteration.",
    level = DeprecationLevel.ERROR,
    replaceWith = ReplaceWith("assertContentEquals(expected, actual?.asIterable(), message)")
)
public fun <@OnlyInputTypes T> assertContentEquals(expected: Set<T>?, actual: Set<T>?, message: String? = null): Unit =
    assertContentEquals(expected, actual?.asIterable(), message)

/**
 * Two sets are compared by the order of their elements.
 *
 * The sets are also considered equal if both are `null`.
 */
@SinceKotlin("2.4")
@ExperimentalKotlinTestApi
@Deprecated(
    "'assertContentEquals' for Set arguments is ambiguous. Use 'assertEquals' to compare content with the unordered set equality, or cast one of arguments to Iterable to compare the set elements in order of iteration.",
    level = DeprecationLevel.ERROR,
    replaceWith = ReplaceWith("assertContentEquals(expected, actual?.asIterable(), lazyMessage)")
)
public fun <@OnlyInputTypes T> assertContentEquals(expected: Set<T>?, actual: Set<T>?, lazyMessage: () -> String): Unit =
    assertContentEquals(expected, actual?.asIterable(), lazyMessage)

/**
 * Two sequences are considered structurally equal if they have the same size, and elements at corresponding positions,
 * following the iteration order, are equal. Elements are compared for equality using the [equals][Any.equals] function.
 *
 * The sequences are also considered equal if both are `null`.
 */
@SinceKotlin("1.5")
public fun <@OnlyInputTypes T> assertContentEquals(expected: Sequence<T>?, actual: Sequence<T>?, message: String? = null) {
    assertIterableContentEquals("Sequence", message, expected, actual, Sequence<*>::iterator)
}

/**
 * Two sequences are considered structurally equal if they have the same size, and elements at corresponding positions,
 * following the iteration order, are equal. Elements are compared for equality using the [equals][Any.equals] function.
 *
 * The sequences are also considered equal if both are `null`.
 */
@SinceKotlin("2.4")
@ExperimentalKotlinTestApi
public fun <@OnlyInputTypes T> assertContentEquals(expected: Sequence<T>?, actual: Sequence<T>?, lazyMessage: () -> String) {
    assertIterableContentEquals("Sequence", lazyMessage, expected, actual, Sequence<*>::iterator)
}

/**
 * Two arrays are considered structurally equal if they have the same size, and elements at corresponding indices are equal.
 * Elements are compared for equality using the [equals][Any.equals] function.
 * For floating point numbers, this means `NaN` is equal to itself and `-0.0` is not equal to `0.0`.
 *
 * The arrays are also considered equal if both are `null`.
 */
@SinceKotlin("1.5")
public fun <@OnlyInputTypes T> assertContentEquals(expected: Array<T>?, actual: Array<T>?, message: String? = null) {
    assertArrayContentEquals(message, expected, actual, { it.size }, Array<*>::get, Array<*>?::contentToString, Array<*>?::contentEquals)
}

/**
 * Two arrays are considered structurally equal if they have the same size, and elements at corresponding indices are equal.
 * Elements are compared for equality using the [equals][Any.equals] function.
 * For floating point numbers, this means `NaN` is equal to itself and `-0.0` is not equal to `0.0`.
 *
 * The arrays are also considered equal if both are `null`.
 */
@SinceKotlin("2.4")
@ExperimentalKotlinTestApi
public fun <@OnlyInputTypes T> assertContentEquals(expected: Array<T>?, actual: Array<T>?, lazyMessage: () -> String) {
    assertArrayContentEquals(
        lazyMessage,
        expected,
        actual,
        { it.size },
        Array<*>::get,
        Array<*>?::contentToString,
        Array<*>?::contentEquals
    )
}

/**
 * Two arrays are considered structurally equal if they have the same size, and elements at corresponding indices are equal.
 *
 * The arrays are also considered equal if both are `null`.
 */
@SinceKotlin("1.5")
public fun assertContentEquals(expected: ByteArray?, actual: ByteArray?, message: String? = null) {
    assertArrayContentEquals(message, expected, actual, { it.size }, ByteArray::get, ByteArray?::contentToString, ByteArray?::contentEquals)
}

/**
 * Two arrays are considered structurally equal if they have the same size, and elements at corresponding indices are equal.
 *
 * The arrays are also considered equal if both are `null`.
 */
@SinceKotlin("2.4")
@ExperimentalKotlinTestApi
public fun assertContentEquals(expected: ByteArray?, actual: ByteArray?, lazyMessage: () -> String) {
    assertArrayContentEquals(
        lazyMessage,
        expected,
        actual,
        { it.size },
        ByteArray::get,
        ByteArray?::contentToString,
        ByteArray?::contentEquals
    )
}

/**
 * Two arrays are considered structurally equal if they have the same size, and elements at corresponding indices are equal.
 *
 * The arrays are also considered equal if both are `null`.
 */
@SinceKotlin("1.5")
public fun assertContentEquals(expected: ShortArray?, actual: ShortArray?, message: String? = null) {
    assertArrayContentEquals(message, expected, actual, { it.size }, ShortArray::get, ShortArray?::contentToString, ShortArray?::contentEquals)
}

/**
 * Two arrays are considered structurally equal if they have the same size, and elements at corresponding indices are equal.
 *
 * The arrays are also considered equal if both are `null`.
 */
@SinceKotlin("2.4")
@ExperimentalKotlinTestApi
public fun assertContentEquals(expected: ShortArray?, actual: ShortArray?, lazyMessage: () -> String) {
    assertArrayContentEquals(
        lazyMessage,
        expected,
        actual,
        { it.size },
        ShortArray::get,
        ShortArray?::contentToString,
        ShortArray?::contentEquals
    )
}

/**
 * Two arrays are considered structurally equal if they have the same size, and elements at corresponding indices are equal.
 *
 * The arrays are also considered equal if both are `null`.
 */
@SinceKotlin("1.5")
public fun assertContentEquals(expected: IntArray?, actual: IntArray?, message: String? = null) {
    assertArrayContentEquals(message, expected, actual, { it.size }, IntArray::get, IntArray?::contentToString, IntArray?::contentEquals)
}

/**
 * Two arrays are considered structurally equal if they have the same size, and elements at corresponding indices are equal.
 *
 * The arrays are also considered equal if both are `null`.
 */
@SinceKotlin("2.4")
@ExperimentalKotlinTestApi
public fun assertContentEquals(expected: IntArray?, actual: IntArray?, lazyMessage: () -> String) {
    assertArrayContentEquals(
        lazyMessage,
        expected,
        actual,
        { it.size },
        IntArray::get,
        IntArray?::contentToString,
        IntArray?::contentEquals
    )
}

/**
 * Two arrays are considered structurally equal if they have the same size, and elements at corresponding indices are equal.
 *
 * The arrays are also considered equal if both are `null`.
 */
@SinceKotlin("1.5")
public fun assertContentEquals(expected: LongArray?, actual: LongArray?, message: String? = null) {
    assertArrayContentEquals(message, expected, actual, { it.size }, LongArray::get, LongArray?::contentToString, LongArray?::contentEquals)
}

/**
 * Two arrays are considered structurally equal if they have the same size, and elements at corresponding indices are equal.
 *
 * The arrays are also considered equal if both are `null`.
 */
@SinceKotlin("2.4")
@ExperimentalKotlinTestApi
public fun assertContentEquals(expected: LongArray?, actual: LongArray?, lazyMessage: () -> String) {
    assertArrayContentEquals(
        lazyMessage,
        expected,
        actual,
        { it.size },
        LongArray::get,
        LongArray?::contentToString,
        LongArray?::contentEquals
    )
}

/**
 * Two arrays are considered structurally equal if they have the same size, and elements at corresponding indices are equal.
 * Elements are compared for equality using the [equals][Any.equals] function.
 * For floating point numbers, this means `NaN` is equal to itself and `-0.0` is not equal to `0.0`.
 *
 * The arrays are also considered equal if both are `null`.
 */
@SinceKotlin("1.5")
public fun assertContentEquals(expected: FloatArray?, actual: FloatArray?, message: String? = null) {
    assertArrayContentEquals(message, expected, actual, { it.size }, FloatArray::get, FloatArray?::contentToString, FloatArray?::contentEquals)
}

/**
 * Two arrays are considered structurally equal if they have the same size, and elements at corresponding indices are equal.
 * Elements are compared for equality using the [equals][Any.equals] function.
 * For floating point numbers, this means `NaN` is equal to itself and `-0.0` is not equal to `0.0`.
 *
 * The arrays are also considered equal if both are `null`.
 */
@SinceKotlin("2.4")
@ExperimentalKotlinTestApi
public fun assertContentEquals(expected: FloatArray?, actual: FloatArray?, lazyMessage: () -> String) {
    assertArrayContentEquals(
        lazyMessage,
        expected,
        actual,
        { it.size },
        FloatArray::get,
        FloatArray?::contentToString,
        FloatArray?::contentEquals
    )
}

/**
 * Two arrays are considered structurally equal if they have the same size, and elements at corresponding indices are equal.
 * Elements are compared for equality using the [equals][Any.equals] function.
 * For floating point numbers, this means `NaN` is equal to itself and `-0.0` is not equal to `0.0`.
 *
 * The arrays are also considered equal if both are `null`.
 */
@SinceKotlin("1.5")
public fun assertContentEquals(expected: DoubleArray?, actual: DoubleArray?, message: String? = null) {
    assertArrayContentEquals(message, expected, actual, { it.size }, DoubleArray::get, DoubleArray?::contentToString, DoubleArray?::contentEquals)
}

/**
 * Two arrays are considered structurally equal if they have the same size, and elements at corresponding indices are equal.
 * Elements are compared for equality using the [equals][Any.equals] function.
 * For floating point numbers, this means `NaN` is equal to itself and `-0.0` is not equal to `0.0`.
 *
 * The arrays are also considered equal if both are `null`.
 */
@SinceKotlin("2.4")
@ExperimentalKotlinTestApi
public fun assertContentEquals(expected: DoubleArray?, actual: DoubleArray?, lazyMessage: () -> String) {
    assertArrayContentEquals(
        lazyMessage,
        expected,
        actual,
        { it.size },
        DoubleArray::get,
        DoubleArray?::contentToString,
        DoubleArray?::contentEquals
    )
}

/**
 * Two arrays are considered structurally equal if they have the same size, and elements at corresponding indices are equal.
 *
 * The arrays are also considered equal if both are `null`.
 */
@SinceKotlin("1.5")
public fun assertContentEquals(expected: BooleanArray?, actual: BooleanArray?, message: String? = null) {
    assertArrayContentEquals(message, expected, actual, { it.size }, BooleanArray::get, BooleanArray?::contentToString, BooleanArray?::contentEquals)
}

/**
 * Two arrays are considered structurally equal if they have the same size, and elements at corresponding indices are equal.
 *
 * The arrays are also considered equal if both are `null`.
 */
@SinceKotlin("2.4")
@ExperimentalKotlinTestApi
public fun assertContentEquals(expected: BooleanArray?, actual: BooleanArray?, lazyMessage: () -> String) {
    assertArrayContentEquals(
        lazyMessage,
        expected,
        actual,
        { it.size },
        BooleanArray::get,
        BooleanArray?::contentToString,
        BooleanArray?::contentEquals
    )
}

/**
 * Two arrays are considered structurally equal if they have the same size, and elements at corresponding indices are equal.
 *
 * The arrays are also considered equal if both are `null`.
 */
@SinceKotlin("1.5")
public fun assertContentEquals(expected: CharArray?, actual: CharArray?, message: String? = null) {
    assertArrayContentEquals(message, expected, actual, { it.size }, CharArray::get, CharArray?::contentToString, CharArray?::contentEquals)
}

/**
 * Two arrays are considered structurally equal if they have the same size, and elements at corresponding indices are equal.
 *
 * The arrays are also considered equal if both are `null`.
 */
@SinceKotlin("2.4")
@ExperimentalKotlinTestApi
public fun assertContentEquals(expected: CharArray?, actual: CharArray?, lazyMessage: () -> String) {
    assertArrayContentEquals(
        lazyMessage,
        expected,
        actual,
        { it.size },
        CharArray::get,
        CharArray?::contentToString,
        CharArray?::contentEquals
    )
}

/**
 * Two arrays are considered structurally equal if they have the same size, and elements at corresponding indices are equal.
 *
 * The arrays are also considered equal if both are `null`.
 */
@SinceKotlin("1.5")
@OptIn(ExperimentalUnsignedTypes::class)
public fun assertContentEquals(expected: UByteArray?, actual: UByteArray?, message: String? = null) {
    assertArrayContentEquals(message, expected, actual, { it.size }, UByteArray::get, UByteArray?::contentToString, UByteArray?::contentEquals)
}

/**
 * Two arrays are considered structurally equal if they have the same size, and elements at corresponding indices are equal.
 *
 * The arrays are also considered equal if both are `null`.
 */
@SinceKotlin("2.4")
@ExperimentalKotlinTestApi
@OptIn(ExperimentalUnsignedTypes::class)
public fun assertContentEquals(expected: UByteArray?, actual: UByteArray?, lazyMessage: () -> String) {
    assertArrayContentEquals(
        lazyMessage,
        expected,
        actual,
        { it.size },
        UByteArray::get,
        UByteArray?::contentToString,
        UByteArray?::contentEquals
    )
}

/**
 * Two arrays are considered structurally equal if they have the same size, and elements at corresponding indices are equal.
 *
 * The arrays are also considered equal if both are `null`.
 */
@SinceKotlin("1.5")
@OptIn(ExperimentalUnsignedTypes::class)
public fun assertContentEquals(expected: UShortArray?, actual: UShortArray?, message: String? = null) {
    assertArrayContentEquals(message, expected, actual, { it.size }, UShortArray::get, UShortArray?::contentToString, UShortArray?::contentEquals)
}

/**
 * Two arrays are considered structurally equal if they have the same size, and elements at corresponding indices are equal.
 *
 * The arrays are also considered equal if both are `null`.
 */
@SinceKotlin("2.4")
@ExperimentalKotlinTestApi
@OptIn(ExperimentalUnsignedTypes::class)
public fun assertContentEquals(expected: UShortArray?, actual: UShortArray?, lazyMessage: () -> String) {
    assertArrayContentEquals(
        lazyMessage,
        expected,
        actual,
        { it.size },
        UShortArray::get,
        UShortArray?::contentToString,
        UShortArray?::contentEquals
    )
}

/**
 * Two arrays are considered structurally equal if they have the same size, and elements at corresponding indices are equal.
 *
 * The arrays are also considered equal if both are `null`.
 */
@SinceKotlin("1.5")
@OptIn(ExperimentalUnsignedTypes::class)
public fun assertContentEquals(expected: UIntArray?, actual: UIntArray?, message: String? = null) {
    assertArrayContentEquals(message, expected, actual, { it.size }, UIntArray::get, UIntArray?::contentToString, UIntArray?::contentEquals)
}

/**
 * Two arrays are considered structurally equal if they have the same size, and elements at corresponding indices are equal.
 *
 * The arrays are also considered equal if both are `null`.
 */
@SinceKotlin("2.4")
@ExperimentalKotlinTestApi
@OptIn(ExperimentalUnsignedTypes::class)
public fun assertContentEquals(expected: UIntArray?, actual: UIntArray?, lazyMessage: () -> String) {
    assertArrayContentEquals(
        lazyMessage,
        expected,
        actual,
        { it.size },
        UIntArray::get,
        UIntArray?::contentToString,
        UIntArray?::contentEquals
    )
}


/**
 * Two arrays are considered structurally equal if they have the same size, and elements at corresponding indices are equal.
 *
 * The arrays are also considered equal if both are `null`.
 */
@SinceKotlin("1.5")
@OptIn(ExperimentalUnsignedTypes::class)
public fun assertContentEquals(expected: ULongArray?, actual: ULongArray?, message: String? = null) {
    assertArrayContentEquals(message, expected, actual, { it.size }, ULongArray::get, ULongArray?::contentToString, ULongArray?::contentEquals)
}

/**
 * Two arrays are considered structurally equal if they have the same size, and elements at corresponding indices are equal.
 *
 * The arrays are also considered equal if both are `null`.
 */
@SinceKotlin("2.4")
@ExperimentalKotlinTestApi
@OptIn(ExperimentalUnsignedTypes::class)
public fun assertContentEquals(expected: ULongArray?, actual: ULongArray?, lazyMessage: () -> String) {
    assertArrayContentEquals(
        lazyMessage,
        expected,
        actual,
        { it.size },
        ULongArray::get,
        ULongArray?::contentToString,
        ULongArray?::contentEquals
    )
}
