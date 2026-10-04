// KUU-963: a user-defined `emit` member on a non-Flow receiver must keep its
// own dispatch inside suspend receiver callbacks — Flow lowering must not
// rewrite it to the `kk_flow_emit` runtime bridge on the bare name alone.
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*

class Sink {
    val items = mutableListOf<Int>()
    fun emit(value: Int) { items.add(value) }
}

suspend fun applyTwice(block: suspend Sink.(Int) -> Unit): List<Int> {
    val sink = Sink()
    block(sink, 3)
    block(sink, 4)
    return sink.items
}

suspend fun latest(block: suspend Sink.(Int) -> Unit): List<Int> {
    val sink = Sink()
    coroutineScope {
        var previous: Job? = null
        for (value in listOf(1, 2)) {
            previous?.join()
            previous = launch(start = CoroutineStart.UNDISPATCHED) {
                block(sink, value)
            }
        }
        previous?.join()
    }
    return sink.items
}

fun directEmit(block: Sink.(Int) -> Unit): List<Int> {
    val sink = Sink()
    sink.block(5)
    return sink.items
}

fun main() = runBlocking {
    println(applyTwice {
        emit(it)
        emit(it * 10)
    })
    println(latest {
        emit(it)
        emit(it * 10)
    })
    println(directEmit { emit(it); emit(it * 10) })

    // Control: a real flow { } builder still lowers emit to the flow effect.
    flow {
        emit(7)
        emit(70)
    }.collect { println(it) }
}
