// KSP-1572: Channel.tryReceive() / SendChannel.trySend() returning ChannelResult.
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.*

fun main() = runBlocking {
    // 1. tryReceive drains a buffered channel without suspending.
    val ch = Channel<Int>(capacity = 2)
    ch.send(10)
    ch.send(20)
    val r1 = ch.tryReceive()
    println(r1.isSuccess)
    println(r1.getOrThrow())
    println(ch.tryReceive().getOrThrow())

    // 2. Empty but open channel reports failure without isClosed.
    val r3 = ch.tryReceive()
    println(r3.isFailure)
    println(r3.isClosed)

    // 3. Closed and drained reports isClosed; getOrNull yields null.
    ch.close()
    val r4 = ch.tryReceive()
    println(r4.isClosed)
    println(r4.getOrNull())

    // 4. Buffered elements sent before close() are still receivable.
    val ch2 = Channel<Int>(capacity = 2)
    ch2.send(30)
    ch2.close()
    println(ch2.tryReceive().getOrThrow())
    println(ch2.tryReceive().isClosed)

    // 5. getOrThrow on a closed result throws IllegalStateException.
    val closedResult = ch2.tryReceive()
    try {
        closedResult.getOrThrow()
    } catch (e: IllegalStateException) {
        println(e.message)
    }

    // 6. trySend reports ChannelResult inside a producer scope.
    val produced = produce(capacity = 1) {
        println(trySend(50).isSuccess)
        println(trySend(51).isFailure)
        println(trySend(51).isClosed)
    }
    println(produced.receiveCatching().getOrThrow())
    println(produced.receiveCatching().isClosed)
}
