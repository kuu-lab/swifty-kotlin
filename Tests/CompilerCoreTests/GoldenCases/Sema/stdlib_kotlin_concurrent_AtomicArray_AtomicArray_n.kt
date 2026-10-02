@file:OptIn(kotlin.ExperimentalStdlibApi::class)

package golden.sema

import kotlin.concurrent.AtomicArray

fun atomicArrayLength(array: AtomicArray<String>): Int = array.length
fun atomicArrayGet(array: AtomicArray<String>): String = array[0]
fun atomicArraySet(array: AtomicArray<String>, value: String) {
    array[0] = value
}
fun atomicArrayGetAndSet(array: AtomicArray<String>, value: String): String = array.getAndSet(0, value)
fun atomicArrayCompareAndSet(array: AtomicArray<String>, expected: String, value: String): Boolean =
    array.compareAndSet(0, expected, value)
fun atomicArrayCompareAndExchange(array: AtomicArray<String>, expected: String, value: String): String =
    array.compareAndExchange(0, expected, value)
fun atomicArrayToString(array: AtomicArray<String>): String = array.toString()
