@file:OptIn(kotlin.ExperimentalStdlibApi::class)
@file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")

package golden.sema

import kotlin.concurrent.AtomicLongArray

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

fun atomicLongArrayToString(values: AtomicLongArray): String = values.toString()
