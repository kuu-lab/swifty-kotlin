// CANDIDATE-ONLY

import kotlin.concurrent.AtomicInt

fun main() {
    val atomic = AtomicInt(7)
    println(atomic.value)
    println(atomic.toString())
}
