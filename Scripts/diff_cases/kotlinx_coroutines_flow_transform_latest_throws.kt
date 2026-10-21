import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*

fun main() {
    runBlocking {
        try {
            flowOf(1, 2, 3).transformLatest<Int, String> { value ->
                if (value == 2) throw IllegalStateException("transform blew up")
                emit("v$value")
            }.collect { println(it) }
        } catch (e: IllegalStateException) {
            println("caught:${e.message}")
        }
        try {
            flowOf(1, 2, 3).transformLatest<Int, String> { value ->
                if (value == 3) throw IllegalStateException("last blew up")
                emit("p$value")
            }.collect { println(it) }
        } catch (e: IllegalStateException) {
            println("caught:${e.message}")
        }
        try {
            flowOf(1, 2, 3).mapLatest { value ->
                if (value == 2) throw IllegalStateException("map blew up")
                "m$value"
            }.collect { println(it) }
        } catch (e: IllegalStateException) {
            println("caught:${e.message}")
        }
    }
}
