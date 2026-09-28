@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

import kotlin.concurrent.atomics.AtomicInt

fun main() {
    println(AtomicInt(0).load())
    println(AtomicInt(42).load())
}
