@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

import kotlin.concurrent.atomics.AtomicInt
import kotlin.concurrent.atomics.AtomicLong

// KSP-671: fetchAndAdd/fetchAndIncrement/fetchAndDecrement reverse variants and
// compareAndSet public layer on AtomicInt/AtomicLong.
fun main() {
    val a = AtomicInt(10)
    println(a.fetchAndAdd(5))        // 10 (a = 15)
    println(a.addAndFetch(5))        // 20
    println(a.fetchAndIncrement())   // 20 (a = 21)
    println(a.fetchAndDecrement())   // 21 (a = 20)
    println(a.compareAndSet(20, 100)) // true (a = 100)
    println(a.compareAndSet(20, 200)) // false (a = 100)
    println(a.load())                // 100

    val b = AtomicLong(1000L)
    println(b.fetchAndAdd(-100L))    // 1000 (b = 900)
    println(b.fetchAndIncrement())   // 900 (b = 901)
    println(b.fetchAndDecrement())   // 901 (b = 900)
    println(b.compareAndSet(900L, 5000L)) // true (b = 5000)
    println(b.load())                // 5000
}
