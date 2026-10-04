import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*

fun <T> Flow<T>.myLaunchIn(scope: CoroutineScope): Job {
    val source = this
    return scope.launch { source.collect { println(it) } }
}

fun String.probeScope() = runBlocking {
    val scope: CoroutineScope = this
    println(this@probeScope)
    listOf(9).forEach {
        flowOf(it).myLaunchIn(this@runBlocking).join()
    }
    flowOf(10).myLaunchIn(scope).join()
}

fun main() {
    runBlocking {
        flowOf(7, 8).myLaunchIn(this).join()
        delay(1)
        flowOf(11).myLaunchIn(this).join()
        println("done")
    }
    "outer".probeScope()
}
