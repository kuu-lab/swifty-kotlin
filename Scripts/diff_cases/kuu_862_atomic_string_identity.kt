@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
import kotlin.concurrent.atomics.AtomicReference

private fun initial(): String = "initial"

fun main() {
    val value = AtomicReference(initial())
    println(value.compareAndExchange("initial", "updated"))
    println(value.load())
    println(value.compareAndSet("updated", "done"))
    println(value.load())

    val first = charArrayOf('s', 'a', 'm', 'e').concatToString()
    val second = charArrayOf('s', 'a', 'm', 'e').concatToString()
    val dynamic = AtomicReference(first)
    println(first == second)
    println(first === second)
    println(dynamic.compareAndSet(second, "wrong"))
    println(dynamic.load() === first)
    val loaded = dynamic.load()
    println(dynamic.compareAndSet(loaded, "correct"))
    println(dynamic.load())
    println("é" === "é")
}
