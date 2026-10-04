@file:OptIn(kotlin.ExperimentalStdlibApi::class)
@file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")

package golden.sema

import kotlin.concurrent.AtomicIntArray

fun atomicIntArrayCompareAndExchange(
    values: AtomicIntArray,
    index: Int,
    expectedValue: Int,
    newValue: Int
): Int = values.compareAndExchange(index, expectedValue, newValue)

fun atomicIntArrayCompareAndSet(
    values: AtomicIntArray,
    index: Int,
    expectedValue: Int,
    newValue: Int
): Boolean = values.compareAndSet(index, expectedValue, newValue)

fun atomicIntArrayLength(values: AtomicIntArray): Int = values.length

fun atomicIntArrayToString(values: AtomicIntArray): String = values.toString()
