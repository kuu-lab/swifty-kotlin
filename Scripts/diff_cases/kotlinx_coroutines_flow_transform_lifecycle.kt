import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*

fun main() {
    runBlocking {
        val source = flowOf(1, 2).onStart { emit(0) }.onEach { println("each:$it") }
            .onCompletion { cause -> println(cause == null); emit(3) }
        println("created")
        println(source.toList())
        println(source.toList())
        println(flowOf(1, 2).transform<Int, Int> { emit(it); emit(it * 10) }.toList())
        var visited = 0
        println(flowOf(1, 2, 3).onEach { visited += 1 }.transformWhile<Int, Int> {
            emit(it)
            it < 2
        }.toList())
        println(visited)
        println(flowOf(1, 2).transformLatest<Int, Int> { emit(it * 10) }.toList())
    }
}
