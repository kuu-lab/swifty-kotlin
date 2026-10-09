// DIFF_CANDIDATE_ONLY_EXPECTED_OUTPUT: stdlib_kotlin_concurrent_n_n.expected.stdout

@file:OptIn(kotlin.ExperimentalStdlibApi::class, kotlinx.cinterop.ExperimentalForeignApi::class)

import kotlin.concurrent.AtomicArray
import kotlin.concurrent.AtomicInt
import kotlin.concurrent.AtomicIntArray
import kotlin.concurrent.AtomicLong
import kotlin.concurrent.AtomicLongArray
import kotlin.concurrent.AtomicNativePtr
import kotlin.concurrent.AtomicReference

fun main() {
    val int: AtomicInt? = null
    val long: AtomicLong? = null
    val reference: AtomicReference<String>? = null
    val array: AtomicArray<String?>? = null
    val nativePtr: AtomicNativePtr? = null
    val ints = AtomicIntArray(2) { it }
    val longs = AtomicLongArray(2) { it.toLong() }
    val refs = AtomicArray(2) { it.toString() }
    println(listOf(int, long, reference, array, nativePtr, ints, longs, refs).size)
}
