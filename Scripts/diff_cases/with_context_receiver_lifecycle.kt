import kotlin.coroutines.EmptyCoroutineContext
import kotlinx.coroutines.*

fun main() = runBlocking {
    val parentJob = currentCoroutineContext().job
    withContext(EmptyCoroutineContext) {
        println("empty owns job: ${currentCoroutineContext().job !== parentJob}")
        println("empty receiver job: ${coroutineContext.job === currentCoroutineContext().job}")
    }
    var directFinished = false
    var contextFinished = false
    val captured = withContext(CoroutineName("child")) {
        launch { delay(10); directFinished = true }
        CoroutineScope(currentCoroutineContext()).launch { delay(10); contextFinished = true }
        println("body finished")
        this
    }
    println("direct child joined: $directFinished")
    println("context child joined: $contextFinished")
    println("escaped name: ${captured.coroutineContext[CoroutineName]?.name}")
    println("escaped job completed: ${captured.coroutineContext.job.isCompleted}")
    val failure = IllegalStateException("withContext child")
    try {
        withContext(CoroutineName("failing")) {
            CoroutineScope(currentCoroutineContext()).launch { delay(10); throw failure }
        }
    } catch (observed: Throwable) {
        println("child failure identity: ${observed === failure}")
    }
    withContext(CoroutineName("outer")) {
        try {
            withContext(CoroutineName("inner")) { throw failure }
        } catch (observed: Throwable) {
            println("caught withContext identity: ${observed === failure}")
        }
        try {
            coroutineScope { throw failure }
        } catch (observed: Throwable) {
            println("caught coroutineScope identity: ${observed === failure}")
        }
        try {
            supervisorScope { throw failure }
        } catch (observed: Throwable) {
            println("caught supervisorScope identity: ${observed === failure}")
        }
        println("outer body done")
    }
    println("outer returned")
    println("parent active: ${parentJob.isActive}")
}
