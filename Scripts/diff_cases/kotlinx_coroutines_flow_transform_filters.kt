import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*

fun main() {
    runBlocking {
        var calls = 0
        val source = flowOf(1, 2, 3, 4, 5).onEach { calls += 1 }
        println(calls)
        println(source.drop(1).dropWhile { it < 3 }.filterNot { it == 4 }.toList())
        println(calls)
        println(source.takeWhile { it < 3 }.toList())
        println(calls)
        println(flowOf<Int?>(null, 1, null, 2).filterNotNull().toList())
        println(flowOf(1, 2, 3).mapNotNull { if (it == 2) null else it * 10 }.toList())
        println(flowOf<Any>(1, "a", 2, "b").filterIsInstance<String>().toList())
        val mixed: Flow<*> = flowOf<Any?>(null, 1, "a", 2, "b")
        println(mixed.filterIsInstance<String>().toList())
        flowOf("a", "b").withIndex().collect { println("${it.index}:${it.value}") }
        flowOf(7, 8).collectIndexed { index, value -> println("$index:$value") }
        try {
            source.drop(-1)
        } catch (e: IllegalArgumentException) {
            println("negative drop")
        }
    }
}
