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
}
