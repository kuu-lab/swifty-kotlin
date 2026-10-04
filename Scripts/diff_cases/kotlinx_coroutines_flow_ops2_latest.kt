@file:OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.flow.*

fun main() = runBlocking {
    println(flowOf(1, 2, 3).mapLatest { it * 10 }.toList())
    println(flowOf(1, 2, 3).transformLatest<Int, Int> { value ->
        if (value != 2) {
            emit(value)
            emit(value * 10)
        }
    }.toList())
    println(flowOf(1).conflate().toList())
    println(flowOf(1, 2).flatMapLatest { flowOf(it, it * 10) }.toList())
}
