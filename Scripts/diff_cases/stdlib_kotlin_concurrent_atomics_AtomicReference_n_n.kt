@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

import kotlin.concurrent.atomics.AtomicReference

class Box(val s: String)

fun main() {
    println(AtomicReference(41).load())
    println(AtomicReference("initial").load())
    val boxes = AtomicReference(Box("b1"))
    println(boxes.load().s)
    println(AtomicReference<Box?>(null).load())
}
