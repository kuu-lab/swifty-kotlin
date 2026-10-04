@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

import kotlin.concurrent.atomics.AtomicArray

fun main() {
    val source = arrayOf("a", "b")
    val copied = AtomicArray(source)
    source[0] = "z"
    println(copied.size)
    println(copied.loadAt(0))
    println(copied.loadAt(1))
}
