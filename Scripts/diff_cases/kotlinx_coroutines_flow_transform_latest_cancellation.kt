import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*

fun main() {
    runBlocking {
        println(flowOf(1, 2).transformLatest<Int, Int> {
            emit(it)
            delay(20)
            emit(it * 10)
        }.toList())
    }
}
