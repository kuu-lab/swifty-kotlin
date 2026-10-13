@file:OptIn(kotlinx.coroutines.InternalCoroutinesApi::class)
import kotlinx.coroutines.*

fun main() = runBlocking {
    val scopeRoot = IllegalStateException("scope body root")
    var scopeJob: Job? = null
    try {
        coroutineScope { scopeJob = currentCoroutineContext().job; throw scopeRoot }
    } catch (failure: Throwable) { println("scope root identity: ${failure === scopeRoot}") }
    println("scope job cause identity: ${scopeJob!!.getCancellationException().cause === scopeRoot}")
    val supervisorRoot = IllegalStateException("supervisor body root")
    var supervisorJob: Job? = null
    try {
        supervisorScope { supervisorJob = currentCoroutineContext().job; throw supervisorRoot }
    } catch (failure: Throwable) { println("supervisor root identity: ${failure === supervisorRoot}") }
    println("supervisor job cause identity: ${supervisorJob!!.getCancellationException().cause === supervisorRoot}")
    val originalCancel = CancellationException("original cancellation")
    try {
        coroutineScope {
            currentCoroutineContext().job.cancel(originalCancel)
            ensureActive()
        }
    } catch (failure: CancellationException) { println("ensureActive identity: ${failure === originalCancel}") }
    val cleanupRoot = IllegalStateException("cleanup root")
    var cleanupJob: Job? = null
    try {
        coroutineScope {
            cleanupJob = currentCoroutineContext().job
            try { cleanupJob!!.cancel(originalCancel); ensureActive() }
            finally { throw cleanupRoot }
        }
    } catch (failure: Throwable) { println("cleanup root identity: ${failure === cleanupRoot}") }
    println("cleanup job cause identity: ${cleanupJob!!.getCancellationException().cause === cleanupRoot}")
    var escaped: CoroutineScope? = null
    coroutineScope { launch { escaped = this } }
    println("escaped scope job completed: ${escaped!!.coroutineContext.job.isCompleted}")
    println("failure contract done")
}
