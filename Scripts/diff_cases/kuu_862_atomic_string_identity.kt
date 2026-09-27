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
    println(first !== second)
    val absent: String? = null
    val optional: String? = first
    println(absent === null)
    println(optional !== null)
    println(optional === first)
    val firstAny: Any? = first
    val secondAny: Any? = second
    val nullAny: Any? = null
    val numberAny: Any? = 1
    println(first === firstAny)
    println(first === secondAny)
    println(secondAny !== first)
    println(firstAny === first)
    println(absent === nullAny)
    println(nullAny === absent)
    println(absent === numberAny)
    println(firstAny === secondAny)
    println(dynamic.compareAndSet(second, "wrong"))
    println(dynamic.load() === first)
    val loaded = dynamic.load()
    println(dynamic.compareAndSet(loaded, "correct"))
    println(dynamic.load())
    println("é" === "é")
}
