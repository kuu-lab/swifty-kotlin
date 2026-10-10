import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*

suspend fun invokeSuspending(block: suspend () -> Unit) { block() }

fun main() = runBlocking {
    val cancellation = CancellationException("sentinel cancellation")
    try {
        invokeSuspending { delay(1); throw cancellation }
    } catch (failure: Throwable) {
        println("cancellation identity: ${failure === cancellation}")
        println("cancellation type: ${failure is CancellationException}")
        println("cancellation message: ${failure.message}")
    }
    val ordinary = IllegalArgumentException("sentinel failure")
    try {
        invokeSuspending { delay(1); throw ordinary }
    } catch (failure: Throwable) {
        println("ordinary identity: ${failure === ordinary}")
        println("ordinary message: ${failure.message}")
    }
    flow<Int> { emit(7); println("unexpected upstream continuation") }
        .onEach { delay(1) }.take(1).collect { println("taken: $it") }
    println("done")
}
