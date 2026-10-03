import kotlinx.coroutines.*

// KUU-964: `coroutineScope { }` / `supervisorScope { }` install their own Job
// into the block's coroutine context, so `coroutineContext.job` resolves
// inside the block instead of throwing.

fun main() = runBlocking {
    supervisorScope {
        println(currentCoroutineContext().job.isActive)
        launch {
            println("child job active: ${coroutineContext.job.isActive}")
        }.join()
        println("supervisor still active: ${coroutineContext.job.isActive}")
    }
    coroutineScope {
        println("coroutineScope job active: ${coroutineContext.job.isActive}")
    }
    println("done")
}
