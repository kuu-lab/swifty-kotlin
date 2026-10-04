@file:Suppress("DEPRECATION_ERROR")
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.*

fun main() = runBlocking {
    println(combine(flowOf(1), flowOf(10), flowOf(100)) { values: Array<Int> -> values.toList().sum() }.toList())
    println(combine(listOf(flowOf(2), flowOf(20))) { values: Array<Int> -> values.toList().sum() }.toList())
    println(combine<Int, Int>(transform = { values: Array<Int> -> values.toList().sum() }).toList())
    println(combine(flowOf(1), emptyFlow<Int>()) { values: Array<Int> -> values.toList().sum() }.toList())
    println(flowOf(2).combineLatest(flowOf("x")) { a, b -> "$a$b" }.toList())
    println(flowOf(1).combineLatest(flowOf(2), flowOf(3)) { a, b, c -> a + b + c }.toList())
    println(flowOf(1).combineLatest(flowOf(2), flowOf(3), flowOf(4)) { a, b, c, d -> a + b + c + d }.toList())
    println(flowOf(1).combineLatest(flowOf(2), flowOf(3), flowOf(4), flowOf(5)) { a, b, c, d, e -> a + b + c + d + e }.toList())
    println(combine(flowOf(2), flowOf("x"), flowOf(true), flowOf(3.5), flowOf('z')) { a, b, c, d, e ->
        "$a:$b:$c:$d:$e"
    }.toList())
    println(flowOf(1, 2, 3).zip(flowOf(10, 20)) { a, b -> a + b }.toList())
    val offset = 10
    println(combine(flowOf(1), flowOf(2), flowOf(3)) { a, b, c ->
        delay(1L)
        a + b + c + offset
    }.toList())
    try {
        combine(flowOf(1), flowOf(2), flowOf(3), flowOf(4), flowOf(5)) { a, b, c, d, e ->
            delay(1L)
            if (a + b + c + d + e > 0) throw IllegalArgumentException("transform")
            a + b + c + d + e
        }.toList()
    } catch (e: IllegalArgumentException) {
        println(e.message)
    }
    println("done")
}
