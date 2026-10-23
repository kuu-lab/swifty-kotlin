@file:OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.flow.*

fun main() = runBlocking {
    val collected = mutableListOf<Int>()
    flowOf(1, 2, 3).collectLatest { value ->
        if (value < 3) delay(50)
        collected.add(value)
    }
    println(collected)

    val mappedSideEffects = mutableListOf<Int>()
    val mapped = flowOf(1, 2, 3).mapLatest { value ->
        if (value < 3) delay(50)
        mappedSideEffects.add(value)
        value
    }
    println(mapped.toList())
    println(mappedSideEffects)

    val innerStarted = mutableListOf<Int>()
    val innerCompleted = mutableListOf<Int>()
    val flattenedLatest = flow {
        emit(1)
        delay(200)
        emit(2)
        delay(200)
        emit(3)
    }.flatMapLatest { value ->
        flow {
            innerStarted.add(value)
            emit(value * 10)
            delay(1_000)
            innerCompleted.add(value)
            emit(value)
        }
    }.toList()
    println(flattenedLatest)
    println(innerStarted)
    println(innerCompleted)
}
