import kotlinx.coroutines.*
import kotlinx.coroutines.channels.*
import kotlinx.coroutines.flow.*

fun main() = runBlocking {
    val cleanup = Channel<Int>(4)
    val values = mutableListOf<Int>()
    val source = callbackFlow<Int> {
        val result = trySendBlocking(7)
        if (result.isSuccess) close()
        awaitClose { cleanup.trySendBlocking(1) }
    }
    source.collect { values.add(it) }
    source.collect { values.add(it) }
    println(values)
    println(cleanup.receive())
    println(cleanup.receive())

    callbackFlow<Int> {
        val producer = this
        launch {
            delay(10)
            producer.close()
        }
        awaitClose { cleanup.trySendBlocking(2) }
    }.collect { }
    println(cleanup.receive())

    channelFlow<Int> {
        close()
        awaitClose()
    }.collect { }
    println("done")
}
