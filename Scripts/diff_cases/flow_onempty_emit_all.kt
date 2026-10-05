// KUU-1128: implicit FlowCollector.emit must dispatch to the actual collector,
// including when the same onEmpty action also calls emitAll.
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.runBlocking

fun main() = runBlocking {
    println(emptyFlow<Int>().onEmpty {
        emit(7)
        emitAll(flowOf(8, 9))
    }.toList())
    println(emptyFlow<Int>().onEmpty {
        emitAll(flowOf(8, 9))
        emit(7)
    }.toList())
    println(emptyFlow<Int>().onEmpty {
        emit(7)
        emit(8)
        emitAll(flowOf(9))
    }.toList())
    var fallbackCalls = 0
    val fallback = emptyFlow<Int>().onEmpty {
        fallbackCalls += 1
        emit(1)
        emitAll(emptyFlow<Int>())
        emit(2)
        emitAll(flowOf(3, 4))
        emit(5)
        emitAll(flowOf(6))
        emit(7)
    }
    println("fallbackCalls:$fallbackCalls")
    println(fallback.toList())
    println(fallback.toList())
    println("fallbackCalls:$fallbackCalls")
    println(emptyFlow<Int?>().onEmpty {
        emit(null)
        emitAll(flowOf(8, null))
        emit(9)
    }.toList())
    var calls = 0
    println(flowOf(10).onEmpty {
        calls += 1
        emit(7)
        emitAll(flowOf(8, 9))
    }.toList())
    println("calls:$calls")
    println(emptyFlow<Int>().onEmpty { emit(10) }.toList())
    println(flow<Int> {
        emit(7)
        emitAll(flowOf(8, 9))
    }.toList())
    try {
        emptyFlow<Int>().onEmpty {
            emit(7)
            emitAll(flow<Int> { throw IllegalArgumentException("nested") })
            emit(8)
        }.collect { println("value:$it") }
    } catch (e: IllegalArgumentException) {
        println("failure:${e.message}")
    }
    Unit
}
