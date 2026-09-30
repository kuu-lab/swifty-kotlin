@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

package golden.sema

import kotlin.concurrent.atomics.AtomicArray

fun atomicArrayCompareAndExchange(
    array: AtomicArray<String>,
    index: Int,
    expectedValue: String,
    newValue: String
): String = array.compareAndExchange(index, expectedValue, newValue)

fun atomicArrayCompareAndExchangeAt(
    array: AtomicArray<String>,
    index: Int,
    expectedValue: String,
    newValue: String
): String = array.compareAndExchangeAt(index, expectedValue, newValue)

fun atomicArrayCompareAndSet(
    array: AtomicArray<String>,
    index: Int,
    expectedValue: String,
    newValue: String
): Boolean = array.compareAndSet(index, expectedValue, newValue)

fun atomicArrayCompareAndSetAt(
    array: AtomicArray<String>,
    index: Int,
    expectedValue: String,
    newValue: String
): Boolean = array.compareAndSetAt(index, expectedValue, newValue)

fun atomicArrayExchangeAt(array: AtomicArray<String>, index: Int, newValue: String): String =
    array.exchangeAt(index, newValue)

fun atomicArrayGet(array: AtomicArray<String>, index: Int): String = array[index]

fun atomicArrayGetAndSet(array: AtomicArray<String>, index: Int, newValue: String): String =
    array.getAndSet(index, newValue)

fun atomicArrayLength(array: AtomicArray<String>): Int = array.length

fun atomicArrayLoadAt(array: AtomicArray<String>, index: Int): String = array.loadAt(index)

fun atomicArraySet(array: AtomicArray<String>, index: Int, value: String) {
    array[index] = value
}

fun atomicArraySize(array: AtomicArray<String>): Int = array.size

fun atomicArrayStoreAt(array: AtomicArray<String>, index: Int, value: String) {
    array.storeAt(index, value)
}

fun atomicArrayToString(array: AtomicArray<String>): String = array.toString()
