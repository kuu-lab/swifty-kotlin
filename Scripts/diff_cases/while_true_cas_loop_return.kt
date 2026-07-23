@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

import kotlin.concurrent.atomics.AtomicInt

// KSP-CAP-004: a `while(true)` CAS retry loop with no `break` never completes
// normally, so it satisfies a non-Unit return type without a trailing
// return/value after the loop — the getAndUpdate/updateAndGet shape that
// blocked KSP-673 / AtomicMigration.kt ("while(true) CAS loops are deferred
// until the type-checker handles Nothing-typed infinite loops in bundled
// source").
fun AtomicInt.testGetAndUpdate(function: (Int) -> Int): Int {
    while (true) {
        val cur = this.load()
        val next = function(cur)
        if (this.compareAndSet(cur, next)) return cur
    }
}

fun AtomicInt.testUpdateAndGet(function: (Int) -> Int): Int {
    while (true) {
        val cur = this.load()
        val next = function(cur)
        if (this.compareAndSet(cur, next)) return next
    }
}

// Same language feature without atomics: a while(true) loop as a function's
// entire body, producing the function's return value only from inside the
// loop.
fun firstPositive(values: List<Int>): Int {
    var index = 0
    while (true) {
        val v = values[index]
        index++
        if (v > 0) return v
    }
}

fun main() {
    val counter = AtomicInt(10)
    println(counter.testGetAndUpdate { it + 5 })
    println(counter.load())
    println(counter.testUpdateAndGet { it * 2 })
    println(counter.load())
    println(firstPositive(listOf(-1, -2, 3, 4)))
}
