@file:OptIn(kotlinx.coroutines.FlowPreview::class, kotlinx.coroutines.ExperimentalCoroutinesApi::class, kotlinx.coroutines.InternalCoroutinesApi::class)
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.*
import kotlinx.coroutines.flow.*
fun main() = runBlocking {
    try {
    callbackFlow<Int> {
        send(3)
        awaitClose { println("sample-cleaned") }
    }.sample(10).take(1).collect { println("sample-value: $it") }
    println("sample-done")
    } catch (e: Throwable) { println("sample-failure: ${e.message}") }
    flowOf(1).sample(100).collect { println("tail-unexpected") }
    println("tail-dropped")
    callbackFlow<String?> {
        send(null)
        awaitClose { println("null-cleaned") }
    }.sample(10).take(1).collect { println("nullable: $it") }
    try {
        flow<Int> { throw IllegalArgumentException("upstream") }
            .sample(10).collect { println(it) }
    } catch (e: Throwable) { println("failure: ${e.message}") }
    try { flowOf(1).sample(0) }
    catch (e: IllegalArgumentException) { println("invalid: ${e.message}") }
    println("before-empty-long-period")
    emptyFlow<Int>().sample(Long.MAX_VALUE).collect { println("empty-unexpected") }
    println("after-empty-long-period")
    val sourceMayCancel = Channel<Unit>(1)
    val downstreamCleaned = Channel<Unit>(1)
    try {
        flow<Int> {
            emit(1)
            sourceMayCancel.receive()
            currentCoroutineContext().job.cancel(CancellationException("value-cancel"))
            withContext(NonCancellable) {
                downstreamCleaned.receive()
                println("upstream-cleaned")
            }
        }.sample(5).collect {
            sourceMayCancel.trySend(Unit)
            try { awaitCancellation() }
            finally { downstreamCleaned.trySend(Unit); println("downstream-cleaned") }
        }
    } catch (failure: CancellationException) { println("child-cancel-caught: ${failure.message}") }
    println("done")
}
