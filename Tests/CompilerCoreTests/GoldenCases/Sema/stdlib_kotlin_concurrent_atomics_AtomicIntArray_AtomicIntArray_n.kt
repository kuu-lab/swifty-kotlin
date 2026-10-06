@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

package golden.sema

import kotlin.concurrent.atomics.AtomicIntArray

fun atomicIntArrayCompareAndExchange(
    values: AtomicIntArray,
    index: Int,
    expectedValue: Int,
    newValue: Int
): Int = values.compareAndExchangeAt(index, expectedValue, newValue)

fun atomicIntArrayCompareAndSet(
    values: AtomicIntArray,
    index: Int,
    expectedValue: Int,
    newValue: Int
): Boolean = values.compareAndSetAt(index, expectedValue, newValue)

fun atomicIntArrayLength(values: AtomicIntArray): Int = values.size

fun atomicIntArraySize(values: AtomicIntArray): Int = values.size

fun atomicIntArrayToString(values: AtomicIntArray): String = values.toString()
