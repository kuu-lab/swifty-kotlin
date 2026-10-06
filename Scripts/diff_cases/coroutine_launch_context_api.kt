import kotlin.coroutines.CoroutineContext
import kotlinx.coroutines.*

fun launchValue(scope: CoroutineScope, context: CoroutineContext,
                block: suspend CoroutineScope.() -> Unit): Job =
    scope.launch(context, block = block)

fun main() = runBlocking {
    val parent: CompletableJob = Job()
    val child: CompletableJob = Job(parent)
    val supervisor: CompletableJob = SupervisorJob(parent)
    println(child.isActive)
    println(supervisor.isActive)
    child.complete()
    supervisor.complete()
    parent.complete()

    val context: CoroutineContext = CoroutineName("child")
    val bonus = 41
    val lazy = launch(context, CoroutineStart.LAZY) {
        val scope: CoroutineScope = this
        println(scope.coroutineContext[CoroutineName]?.name)
        println(bonus + 1)
    }
    println(lazy.isActive)
    lazy.join()
    println(lazy.isCompleted)
    val block: suspend CoroutineScope.() -> Unit = {
        println(this.coroutineContext[CoroutineName]?.name)
    }
    launchValue(this, context, block).join()
    this.launch(context, start = CoroutineStart.UNDISPATCHED) {
        println("inline")
    }.join()
    val nested = launch(context) {
        launch {
            delay(1)
            println(coroutineContext[CoroutineName]?.name)
            println("nested")
        }
    }
    nested.join()
    println("joined")
    println("done")
}
