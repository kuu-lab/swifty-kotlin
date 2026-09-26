@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

package golden.sema

import kotlin.concurrent.atomics.AtomicLongArray

fun atomicLongArrayCompareAndExchange(
    values: AtomicLongArray,
    index: Int,
    expectedValue: Long,
    newValue: Long
): Long = values.compareAndExchange(index, expectedValue, newValue)

fun atomicLongArrayCompareAndSet(
    values: AtomicLongArray,
    index: Int,
    expectedValue: Long,
    newValue: Long
): Boolean = values.compareAndSet(index, expectedValue, newValue)

fun atomicLongArrayLength(values: AtomicLongArray): Int = values.length

fun atomicLongArraySize(values: AtomicLongArray): Int = values.size

fun atomicLongArrayToString(values: AtomicLongArray): String = values.toString()
