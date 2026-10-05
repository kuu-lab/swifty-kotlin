import kotlinx.coroutines.flow.*
import kotlinx.coroutines.runBlocking

fun runCollect(source: Flow<Int>, action: suspend (Int) -> Unit) = runBlocking {
    source.collect(action)
}

fun runCollectCatching(source: Flow<Int>, action: suspend (Int) -> Unit) = runBlocking {
    try { source.collect(action) }
    catch (e: IllegalArgumentException) { println("inner:${e.message}") }
}

fun throwCaptured(message: String): Unit = runBlocking {
    throw IllegalArgumentException(message)
}

fun throwUncaptured(): Unit = runBlocking {
    throw IllegalArgumentException("uncaptured")
}

fun main() {
    val failure: suspend (Int) -> Unit = { throw IllegalArgumentException("converted") }
    try { runCollect(flowOf(1), failure) }
    catch (e: IllegalArgumentException) { println("specific:${e.message}") }
    catch (e: Throwable) { println("other:${e.message}") }

    runCollectCatching(flowOf(1), failure)
    val success: suspend (Int) -> Unit = { println("value:$it") }
    runCollect(flowOf(2, 3), success)

    val otherFailure: suspend (Int) -> Unit = { throw IllegalStateException("state") }
    try { runCollect(flowOf(1), otherFailure) }
    catch (e: IllegalArgumentException) { println("wrong:${e.message}") }
    catch (e: Throwable) { println("other:${e.message}") }

    try { throwCaptured("captured") }
    catch (e: IllegalArgumentException) { println("direct:${e.message}") }
    try { throwUncaptured() }
    catch (e: IllegalArgumentException) { println("direct:${e.message}") }
    println("done")
}
