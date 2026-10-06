@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

package golden.sema

import kotlin.concurrent.atomics.AtomicArray

fun atomicArrayCompareAndExchangeAt(
    array: AtomicArray<String>,
    index: Int,
    expectedValue: String,
    newValue: String
): String = array.compareAndExchangeAt(index, expectedValue, newValue)

fun atomicArrayCompareAndSetAt(
    array: AtomicArray<String>,
    index: Int,
    expectedValue: String,
    newValue: String
): Boolean = array.compareAndSetAt(index, expectedValue, newValue)

fun atomicArrayExchangeAt(array: AtomicArray<String>, index: Int, newValue: String): String =
    array.exchangeAt(index, newValue)

fun atomicArrayLoadAt(array: AtomicArray<String>, index: Int): String = array.loadAt(index)

fun atomicArraySize(array: AtomicArray<String>): Int = array.size

fun atomicArrayStoreAt(array: AtomicArray<String>, index: Int, value: String) {
    array.storeAt(index, value)
}

fun atomicArrayToString(array: AtomicArray<String>): String = array.toString()
