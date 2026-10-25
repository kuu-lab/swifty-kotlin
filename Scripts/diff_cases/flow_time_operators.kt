@file:OptIn(kotlinx.coroutines.FlowPreview::class)

import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.runBlocking
import kotlin.time.Duration.Companion.milliseconds

fun main() = runBlocking {
    flow {
        emit(1)
        delay(5)
        emit(2)
        delay(50)
        emit(3)
        delay(50)
    }.debounce(20).collect { println("debounce:$it") }

    flowOf(9).debounce(100).collect { println("debounce-tail:$it") }

    flow {
        emit(1)
        delay(5)
        emit(2)
        delay(50)
        emit(3)
        delay(50)
    }.sample(20).collect { println("sample:$it") }

    try {
        flow {
            emit(1)
            delay(60)
            emit(2)
        }.timeout(20.milliseconds).collect { println("timeout:$it") }
    } catch (_: TimeoutCancellationException) {
        println("timeout:caught")
    }

    flowOf(4, 5).timeout(20.milliseconds).collect {
        delay(40)
        println("timeout-slow-downstream:$it")
    }
}
