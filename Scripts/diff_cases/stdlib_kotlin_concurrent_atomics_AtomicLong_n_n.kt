@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

import kotlin.concurrent.atomics.AtomicLong

fun main() {
    println(AtomicLong(0L).load())
    println(AtomicLong(42L).load())
}
