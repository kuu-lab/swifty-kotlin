// NOTE: Requires kotlinx-coroutines on classpath.
// KUU-1416 regression: `this` inside coroutine builder lambdas must evaluate
// to a real CoroutineScope — `is`/`as?` checks and member dispatch on it used
// to be broken because it lowered to unit / a raw untyped scope handle.
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*

fun <T> Flow<T>.myLaunchIn(scope: CoroutineScope): Job {
    val source = this
    return scope.launch { source.collect { println(it) } }
}

fun main() = runBlocking {
    println(this is CoroutineScope)
    launch {
        println(this is CoroutineScope)
        val s: CoroutineScope? = this as? CoroutineScope
        println(s != null)
        println(this.isActive)
        listOf(1).forEach {
            println(this is CoroutineScope)
        }
    }.join()
    println(async { this is CoroutineScope }.await())
    coroutineScope {
        println(this is CoroutineScope)
    }
    supervisorScope {
        println(this is CoroutineScope)
    }
    withContext(Dispatchers.Default) {
        println(this is CoroutineScope)
    }
    flowOf(7).myLaunchIn(this).join()
    println("done")
}
