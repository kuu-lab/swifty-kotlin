@file:OptIn(kotlinx.coroutines.FlowPreview::class, kotlinx.coroutines.ExperimentalCoroutinesApi::class)
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.*
import kotlinx.coroutines.flow.*
import kotlin.time.Duration
import kotlin.time.Duration.Companion.microseconds
import kotlin.time.Duration.Companion.nanoseconds

fun main() = runBlocking {
    withContext(CoroutineName("collector")) {
        var collections = 0
        val sampled = callbackFlow<Int> {
            collections += 1
            println("producer context: ${currentCoroutineContext()[CoroutineName]?.name}")
            send(collections)
            awaitClose { println("collection cleaned: $collections") }
        }.sample(10)
        repeat(2) {
            sampled.take(1).collect { value ->
                println("collection value: $value / ${currentCoroutineContext()[CoroutineName]?.name}")
            }
        }
    }
    try {
        callbackFlow<Int> {
            send(1)
            awaitClose { throw IllegalStateException("producer cleanup") }
        }.sample(10).take(1).collect { println("cleanup value: $it") }
    } catch (failure: IllegalStateException) { println("cleanup failure: ${failure.message}") }
    val collectorRoot = IllegalArgumentException("collector root")
    try {
        callbackFlow<Int> {
            send(1)
            awaitClose { throw IllegalStateException("later producer cleanup") }
        }.sample(10).collect { throw collectorRoot }
    } catch (failure: Throwable) {
        println("collector root identity: ${failure === collectorRoot}")
        println("collector root message: ${failure.message}")
    }
    val failSource = Channel<Unit>(1)
    val upstreamRoot = IllegalArgumentException("upstream root")
    try {
        flow<Int> { emit(1); failSource.receive(); throw upstreamRoot }
            .sample(5).collect {
                failSource.trySend(Unit)
                try { awaitCancellation() }
                finally { throw IllegalStateException("later collector cleanup") }
            }
    } catch (failure: Throwable) {
        println("upstream root identity: ${failure === upstreamRoot}")
        println("upstream root message: ${failure.message}")
    }
    for (period in listOf(1.nanoseconds, 1500.microseconds, Duration.INFINITE)) {
        emptyFlow<Int>().sample(period).collect { println("unexpected duration value") }
        println("duration completed")
    }
    try { emptyFlow<Int>().sample(Duration.ZERO) }
    catch (failure: IllegalArgumentException) { println("invalid duration: ${failure.message}") }
    println("lifecycle done")
}
