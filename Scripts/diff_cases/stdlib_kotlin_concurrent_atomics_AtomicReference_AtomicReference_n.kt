@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

import kotlin.concurrent.atomics.AtomicReference

class Box(val s: String)

// Exercise exchange, the canonical Kotlin name for Java's getAndSet.
fun main() {
    val atomic = AtomicReference("initial")
    println(atomic.load())
    atomic.store("stored")
    println(atomic.exchange("exchanged"))
    println(atomic.toString())

    val boxes = AtomicReference(Box("b1"))
    println(boxes.load().s)
    val expected = boxes.load()
    println(boxes.compareAndExchange(expected, Box("b2")).s)
    println(boxes.load().s)
}
