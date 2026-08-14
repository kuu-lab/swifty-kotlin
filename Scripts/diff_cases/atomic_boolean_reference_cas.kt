@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

import kotlin.concurrent.atomics.AtomicBoolean
import kotlin.concurrent.atomics.AtomicReference

// KSP-688: AtomicBoolean and AtomicReference compareAndSet are Kotlin wrappers
// over the compareAndExchange runtime cores.
data class Token(val id: Int)

fun main() {
    val flag = AtomicBoolean(true)
    println(flag.compareAndSet(false, false)) // false; value remains true
    println(flag.load())
    println(flag.compareAndSet(true, false)) // true; value becomes false
    println(flag.load())

    val current = Token(1)
    val equalButDistinct = Token(1)
    val replacement = Token(2)
    val ref = AtomicReference(current)
    println(ref.compareAndSet(equalButDistinct, replacement)) // false: identity mismatch
    println(ref.load() === current)                           // true: value retained
    println(ref.compareAndSet(current, replacement))         // true
    println(ref.load() === replacement)                      // true: update published
}
