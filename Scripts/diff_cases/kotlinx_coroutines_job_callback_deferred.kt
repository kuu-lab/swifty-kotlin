import kotlinx.coroutines.*

fun main() = runBlocking {
    val root = coroutineContext.job
    val deferred = async(start = CoroutineStart.LAZY) {
        val nested = launch(start = CoroutineStart.LAZY) {}
        println(nested.parent === coroutineContext.job)
        println(coroutineContext.job.children.toList().size)
        println(root.children.toList()[0] === coroutineContext.job)
        nested.join()
        42
    }
    println(deferred.parent === root)
    println(root.children.toList().size)
    var calls = 0
    deferred.invokeOnCompletion { cause ->
        calls++
        println(cause == null)
    }
    println(deferred.await())
    println(calls)
    println(deferred.parent == null)
    println(root.children.toList().size)
}
