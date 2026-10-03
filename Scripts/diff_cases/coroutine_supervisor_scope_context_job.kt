import kotlinx.coroutines.*

// KUU-964: `coroutineScope { }` / `supervisorScope { }` install their own Job
// into the block's coroutine context, so `coroutineContext.job` resolves
// inside the block instead of throwing. Exiting the block restores the
// enclosing coroutine's context, and cancelling a scope's own Job surfaces
// its JobCancellationException.

fun main() = runBlocking {
    val outer = coroutineContext.job
    supervisorScope {
        println(currentCoroutineContext().job.isActive)
        println(coroutineContext.job === outer)
        launch {
            println("child job active: ${coroutineContext.job.isActive}")
        }.join()
        println("supervisor still active: ${coroutineContext.job.isActive}")
    }
    println("outer job active: ${coroutineContext.job.isActive}")
    coroutineScope {
        println("coroutineScope job active: ${coroutineContext.job.isActive}")
        println(coroutineContext.job === outer)
    }
    println("outer job still active: ${coroutineContext.job.isActive}")
    try {
        coroutineScope {
            coroutineContext.job.cancel()
        }
    } catch (e: CancellationException) {
        println("caught: ${e.message}")
    }
    try {
        supervisorScope {
            coroutineContext.job.cancel()
        }
    } catch (e: CancellationException) {
        println("caught: ${e.message}")
    }
    withContext(Dispatchers.Default) {
        println("withContext job active: ${coroutineContext.job.isActive}")
    }
    println("done")
}
