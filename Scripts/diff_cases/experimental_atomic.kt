@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

import kotlin.concurrent.atomics.AtomicIntArray
import kotlin.concurrent.atomics.AtomicLongArray

fun main() {
    val arr = AtomicIntArray(intArrayOf(1, 2, 3))
    val longs = AtomicLongArray(longArrayOf(4L, 5L, 6L))
    println(arr.size)
    println(arr[0])
    arr[1] = 10
    println(arr.get(1))
    println(arr.compareAndSet(1, 10, 11))
    println(arr.getAndAdd(2, 5))
    println(arr.updateAndGet(2) { it * 2 })
    println(arr.toString())
    println(longs.size)
    println(longs[0])
    longs[1] = 20L
    println(longs.get(1))
    println(longs.compareAndSet(1, 20L, 21L))
    println(longs.getAndAdd(2, 5L))
    println(longs.updateAndGet(2) { it * 2L })
    println(longs.toString())
}
