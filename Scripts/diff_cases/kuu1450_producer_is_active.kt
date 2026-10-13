// KUU-1450: callbackFlow/channelFlow producer jobs must be .active while the
// producer body runs, so isActive / coroutineContext.job.isActive read true.
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.*
import kotlinx.coroutines.flow.*

fun main() = runBlocking {
    callbackFlow<Int> {
        println(isActive)
        println(coroutineContext[Job]?.isActive)
        val producer = this
        launch { producer.close() }
        awaitClose { }
    }.collect { }

    channelFlow<Int> {
        println(isActive)
        println(coroutineContext[Job]?.isActive)
        send(1)
        close()
    }.collect { println(it) }

    val produced = produce<Int> {
        println(isActive)
        println(coroutineContext[Job]?.isActive)
        send(2)
        close()
    }
    for (value in produced) { println(value) }
    println("done")
}
