@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

package diff

import kotlin.concurrent.atomics.AtomicReference
import kotlin.concurrent.atomics.fetchAndUpdate

fun appendAtomically(atomic: AtomicReference<String>): String =
    atomic.fetchAndUpdate { it + "x" }

fun readNullable(atomic: AtomicReference<String?>): String? = atomic.load()

fun main() {
    println("typealias generic inference")
}
