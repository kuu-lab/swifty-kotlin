import kotlinx.coroutines.*
import kotlinx.coroutines.channels.*
import kotlin.coroutines.*

fun main() = runBlocking {
    val erased: Any = NonCancellable
    println("isJob=${erased is Job}")
    println("isElement=${erased is CoroutineContext.Element}")
    println("isContext=${erased is CoroutineContext}")
    println("notDeferred=${erased !is Deferred<*>}")
    println("safeJob=${(erased as? Job) === NonCancellable}")
    println("directJob=${(erased as Job) === NonCancellable}")
    println("key=${NonCancellable.key === Job}")
    println("string=${NonCancellable.toString()}")
    val job: Job = NonCancellable
    println("jobKey=${job.key === Job}")
    try { NonCancellable.join() }
    catch (e: UnsupportedOperationException) { println("join=${e.message}") }
    delay(1)
    try { job.join() }
    catch (e: UnsupportedOperationException) { println("jobJoin=${e.message}") }

    val original = coroutineContext.job
    val blockJob = withContext(NonCancellable) {
        val insideJob = coroutineContext.job
        println("inside=${coroutineContext.job === NonCancellable}")
        println("current=${currentCoroutineContext().job === NonCancellable}")
        println("blockActive=${insideJob.isActive}")
        delay(1)
        println("afterDelay=${coroutineContext.job === NonCancellable}")
        withContext(NonCancellable + CoroutineName("nested")) {
            println("nestedDistinct=${currentCoroutineContext().job !== insideJob}")
            delay(1)
        }
        println("nestedRestored=${currentCoroutineContext().job === insideJob}")
        insideJob
    }
    println("blockCompleted=${blockJob.isCompleted}")
    println("blockStillActive=${blockJob.isActive}")
    println("restored=${coroutineContext.job === original}")
    try {
        withContext(NonCancellable) { throw IllegalStateException("cleanup") }
    } catch (e: IllegalStateException) { println("thrown=${e.message}") }
    println("restoredAfterThrow=${coroutineContext.job === original}")

    try {
        withContext(NonCancellable) {
            currentCoroutineContext().job.cancel()
            delay(1)
            println("selfCancelFailed")
        }
    } catch (e: CancellationException) { println("selfCancelled=true") }
    println("restoredAfterCancel=${coroutineContext.job === original}")
    println("outerActive=${original.isActive}")

    val entered = Channel<Unit>(1)
    val release = Channel<Unit>(1)
    val finished = Channel<Unit>(1)
    val worker = launch {
        try { awaitCancellation() }
        finally {
            withContext(NonCancellable) {
                entered.send(Unit)
                release.receive()
                delay(1)
                println("cleanup=${coroutineContext.job === NonCancellable}")
                finished.send(Unit)
            }
        }
    }
    yield()
    worker.cancel()
    entered.receive()
    release.send(Unit)
    finished.receive()
    worker.join()
    println("cancelled=${worker.isCancelled}")

    val shielded = launch {
        withContext(NonCancellable) {
            entered.send(Unit)
            release.receive()
            delay(1)
            println("shielded=${currentCoroutineContext().job === NonCancellable}")
            finished.send(Unit)
        }
    }
    entered.receive()
    shielded.cancel()
    release.send(Unit)
    finished.receive()
    shielded.join()
    println("shieldCancelled=${shielded.isCancelled}")
}
