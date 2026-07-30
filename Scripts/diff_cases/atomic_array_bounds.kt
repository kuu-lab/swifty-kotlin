@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

import kotlin.concurrent.atomics.AtomicIntArray
import kotlin.concurrent.atomics.AtomicLongArray

fun main() {
    val a = AtomicIntArray(3)
    a.storeAt(0, 5)
    try {
        a.loadAt(10)
    } catch (e: IndexOutOfBoundsException) {
        println("oob-high: " + e.message)
    }
    try {
        a.storeAt(-1, 1)
    } catch (e: IndexOutOfBoundsException) {
        println("oob-neg: " + e.message)
    }
    val l = AtomicLongArray(2)
    try {
        l.exchangeAt(5, 1L)
    } catch (e: IndexOutOfBoundsException) {
        println("oob-long: " + e.message)
    }
    println(a.loadAt(0))
}
