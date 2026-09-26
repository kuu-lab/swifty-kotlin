// SKIP-DIFF (DEBT-DIFF-001): fetchAndUpdate / update / updateAndFetch on
// kotlin.concurrent.atomics.AtomicReference are Native-only in Kotlin; the
// JVM kotlinc reference cannot resolve them. Compilation and runtime
// behaviour are covered by the Sema golden and the bundled stdlib.

@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

import kotlin.concurrent.atomics.AtomicReference

class RefBox(val s: String)

fun main() {
    val atomic = AtomicReference(RefBox("a"))
    val old = atomic.fetchAndUpdate { RefBox(it.s + "b") }
    println(old.s)
    println(atomic.load().s)
    atomic.update { RefBox(it.s + "c") }
    println(atomic.load().s)
    val newValue = atomic.updateAndFetch { RefBox(it.s + "d") }
    println(newValue.s)
    println(atomic.load().s)
}
