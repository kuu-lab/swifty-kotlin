import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*

fun main() = runBlocking {
    flowOf("a", "b").collectIndexed { index, value -> println("$index:$value") }
    emptyFlow<Int>().collectIndexed { index, value -> println("unreachable:$index:$value") }
    flowOf(1, 2).collectLatest { value -> println("latest:$value") }
    println(flow<Int> {
        emit(0)
        emitAll(emptyFlow<Int>())
        emitAll(flowOf(1, 2))
        emit(3)
    }.toList())
    var calls = 0
    val fallback = emptyFlow<Int>().onEmpty {
        calls += 1
        emit(7)
        emitAll(flowOf(8, 9))
    }
    println("before:$calls")
    println(fallback.toList())
    println(fallback.toList())
    println("after:$calls")
    println(flowOf<Int?>(null).onEmpty { emit(10) }.toList())
    println(flowOf(4).onEmpty { emit(5) }.toList())
    val collector = object : FlowCollector<Int> {
        override suspend fun emit(value: Int) { println("collector:$value") }
    }
    collector.emitAll(flowOf(10, 11))
    try {
        flow<Int> { throw IllegalStateException("upstream") }.onEmpty { emit(12) }.toList()
    } catch (e: IllegalStateException) {
        println("upstream failure")
    }
}
