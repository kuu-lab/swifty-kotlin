import kotlinx.coroutines.*
import kotlinx.coroutines.channels.*
import kotlinx.coroutines.flow.*

fun main() = runBlocking {
    val buffered = Channel<Int>(1)
    val sent = buffered.trySendBlocking(11)
    println(sent.isSuccess)
    println(sent.isFailure)
    println(sent.isClosed)
    println(buffered.receive())
    buffered.close()
    val rejected = buffered.trySendBlocking(12)
    println(rejected.isSuccess)
    println(rejected.isFailure)
    println(rejected.isClosed)

    val statuses = Channel<Int>(2)
    val values = mutableListOf<Int>()
    callbackFlow<Int> {
        val sender: SendChannel<Int> = this
        sender.trySendBlocking(21)
        close()
        val result = sender.trySendBlocking(22)
        statuses.trySendBlocking(if (result.isClosed && isClosedForSend) 1 else 0)
        awaitClose { statuses.trySendBlocking(2) }
    }.collect { values.add(it) }
    println(values)
    println(statuses.receive())
    println(statuses.receive())
}
