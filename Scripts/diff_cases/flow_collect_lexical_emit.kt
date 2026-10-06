// KUU-967: collect callbacks must dispatch lexical emit members and forward
// to an enclosing Flow builder without reentering the source collector.
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*

class EmitSink {
    val items = mutableListOf<Int>()

    fun emit(value: Int) { items.add(value) }

    suspend fun collectValues() {
        flowOf(1, 2).collect { emit(it) }
    }
}

suspend fun FlowCollector<Int>.collectValues() {
    flowOf(5, 6).collect {
        delay(1)
        emit(it)
    }
}

fun main() = runBlocking {
    val sink = EmitSink()
    sink.collectValues()
    println(sink.items)
    with(sink) { flowOf(3, 4).collect { emit(it) } }
    println(sink.items)

    val collector = object : FlowCollector<Int> {
        override suspend fun emit(value: Int) { sink.emit(value) }
    }
    collector.collectValues()
    println(sink.items)

    val forwarded = flow<Int> {
        flowOf(7, 8).collect {
            delay(1)
            emit(it)
        }
    }
    println(forwarded.toList())
    println(forwarded.toList())
}
