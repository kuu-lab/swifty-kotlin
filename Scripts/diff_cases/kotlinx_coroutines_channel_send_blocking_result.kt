import kotlinx.coroutines.*
import kotlinx.coroutines.channels.*
import kotlinx.coroutines.flow.*

fun main() = runBlocking {
    val channel = Channel<Int>(1)
    val sent = channel.trySendBlocking(11)
    println(sent.isSuccess)
    println(sent.getOrNull() != null)
    sent.getOrThrow()
    println(channel.receive())
    channel.close()
    val rejected = channel.trySendBlocking(12)
    println(rejected.isFailure)
    println(rejected.isClosed)
    println(rejected.getOrNull() == null)

    val results = mutableListOf<Boolean>()
    val values = mutableListOf<Int>()
    callbackFlow<Int> {
        val sender: SendChannel<Int> = this
        val result = sender.trySendBlocking(21)
        results.add(result.isSuccess)
        results.add(result.getOrNull() != null)
        result.getOrThrow()
        close()
        val closed = sender.trySendBlocking(22)
        results.add(closed.isFailure)
        results.add(closed.isClosed)
        results.add(closed.getOrNull() == null)
        awaitClose()
    }.collect { values.add(it) }
    println(results)
    println(values)
}
