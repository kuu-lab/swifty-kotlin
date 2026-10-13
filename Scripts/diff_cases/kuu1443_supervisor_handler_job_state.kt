import kotlinx.coroutines.*

// KUU-1443: a launch Job is cancelling (not active) when its exception handler
// runs; it becomes completed only after the handler returns.
fun main() {
    val parent = SupervisorJob()
    val handler = CoroutineExceptionHandler { ctx, _ ->
        val job = checkNotNull(ctx[Job])
        println("handler.completed=" + job.isCompleted)
        println("handler.active=" + job.isActive)
        println("handler.cancelled=" + job.isCancelled)
    }
    val scope = CoroutineScope(parent + handler)
    val job = scope.launch(start = CoroutineStart.UNDISPATCHED) {
        throw IllegalStateException("boom")
    }
    println("after-launch.completed=" + job.isCompleted)
    println("after-launch.active=" + job.isActive)
    println("after-launch.cancelled=" + job.isCancelled)
    runBlocking { job.join() }
    println("after-join.completed=" + job.isCompleted)
    println("after-join.active=" + job.isActive)
    println("after-join.cancelled=" + job.isCancelled)
}
