import kotlin.coroutines.EmptyCoroutineContext
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.*

fun main() = runBlocking {
    val parent: CompletableJob = Job()
    val child: CompletableJob = Job(parent)
    val supervisor: CompletableJob = SupervisorJob(parent)
    println("jobs: ${parent.isActive} ${child.isActive} ${supervisor.isActive}")
    parent.cancel()
    println("cancelled: ${child.isCancelled} ${supervisor.isCancelled}")
    println("late child: ${Job(parent).isCancelled}")

    val completed = Job()
    println("completed: ${completed.complete()} ${completed.isCompleted}")
    println("empty active: ${EmptyCoroutineContext.isActive}")
    EmptyCoroutineContext.ensureActive()
    EmptyCoroutineContext.cancel()

    val scope = CoroutineScope(EmptyCoroutineContext)
    println("scope: ${scope.isActive} ${scope.coroutineContext.job.isActive}")
    val value = 42
    scope.launch { println("launched: $value") }.join()
    scope.ensureActive()
    scope.cancel(CancellationException("stopped"))
    println("scope stopped: ${scope.isActive}")
    val skipped = scope.launch { println("unexpected cancelled launch") }
    skipped.join()
    println("skipped: ${skipped.isCancelled}")
    try {
        scope.coroutineContext.ensureActive()
    } catch (e: CancellationException) {
        println("context cancelled")
    }
    try {
        scope.coroutineContext.job.ensureActive()
    } catch (e: CancellationException) {
        println("job cancelled")
    }

    val contextJob = Job()
    val customScope = object : CoroutineScope {
        override val coroutineContext = contextJob
    }
    customScope.launch { println("custom launched") }.join()
    contextJob.cancel()
    val customSkipped = customScope.launch { println("unexpected custom launch") }
    customSkipped.join()
    println("custom stopped: ${customScope.isActive} ${customSkipped.isCancelled}")

    val pendingScope = CoroutineScope(EmptyCoroutineContext)
    val pending = pendingScope.launch { delay(200); println("unexpected pending launch") }
    pendingScope.coroutineContext.cancel()
    pending.join()
    println("context stopped: ${pendingScope.isActive} ${pending.isCancelled}")

    println("global empty: ${GlobalScope.coroutineContext == EmptyCoroutineContext}")
    GlobalScope.launch { println("global launched") }.join()
    val mainScope = MainScope()
    println("main active: ${mainScope.isActive}")
    mainScope.cancel()
    println("main stopped: ${mainScope.isActive}")
    println("current active: ${currentCoroutineContext().isActive}")
}
