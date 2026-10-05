import kotlinx.coroutines.flow.*
import kotlinx.coroutines.runBlocking

fun runCollect(source: Flow<Int>, action: (Int) -> Unit) = runBlocking {
    source.collect(action)
}

fun invoke0(action: suspend () -> String) = runBlocking { action() }
fun invoke1(action: suspend (Int) -> Int) = runBlocking { action(7) }
fun invoke2(action: suspend (Int, Int) -> Int) = runBlocking { action(4, 5) }
fun <T, R> invokeGeneric(value: T, action: suspend (T) -> R) = runBlocking { action(value) }
fun invokeReceiver(action: suspend Int.(Int) -> Int) = runBlocking { 6.action(2) }

fun main() {
    runCollect(flowOf(12, 13)) { println(it) }
    var total = 10
    val collector: (Int) -> Unit = { total += it }
    runCollect(flowOf(2, 3), collector)
    runCollect(flowOf(4), collector)
    println(total)
    val prefix = "captured"
    val zero: () -> String = { prefix }
    val one: (Int) -> Int = { it + total }
    val two: (Int, Int) -> Int = { a, b -> a * b + total }
    val text: (Int) -> String = { "$prefix:$it" }
    val receiver: Int.(Int) -> Int = { other -> this + other + total }
    println(invoke0(zero))
    println(invoke1(one))
    println(invoke2(two))
    println(invokeGeneric(8, text))
    println(invokeReceiver(receiver))
    val failure: (Int) -> Unit = { throw IllegalArgumentException("converted") }
    try {
        runCollect(flowOf(1), failure)
    } catch (e: IllegalArgumentException) {
        println(e.message)
    }
}
