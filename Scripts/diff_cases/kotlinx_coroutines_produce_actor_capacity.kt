// Regression coverage for KSP-1573 channel capacity semantics: the bundled
// Channel.Factory constants, BufferOverflow policy, and produce(capacity=...).
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.*

fun main() = runBlocking {
    // produce with an explicit buffer capacity
    val buffered = produce(capacity = 2) {
        send(1)
        send(2)
    }
    var sum = 0
    for (v in buffered) {
        sum += v
    }
    println("buffered sum: $sum")

    // Channel.Factory constants all resolve and construct
    val r = Channel<Int>(capacity = Channel.RENDEZVOUS)
    val u = Channel<Int>(capacity = Channel.UNLIMITED)
    val c = Channel<Int>(capacity = Channel.CONFLATED)
    val b = Channel<Int>(capacity = Channel.BUFFERED)

    // BufferOverflow policies construct without error
    val dropOldest = Channel<Int>(capacity = 2, onBufferOverflow = BufferOverflow.DROP_OLDEST)
    val dropLatest = Channel<Int>(capacity = 2, onBufferOverflow = BufferOverflow.DROP_LATEST)
    val suspendCh = Channel<Int>(capacity = 2, onBufferOverflow = BufferOverflow.SUSPEND)

    // invokeOnClose runs the handler once the channel closes, with a nil cause
    var closed = false
    val ch = Channel<Int>(capacity = 1)
    ch.invokeOnClose { cause ->
        closed = true
        println("cause is null: ${cause == null}")
    }
    ch.send(1)
    println("v: ${ch.receive()}")
    ch.close()
    println("closed: $closed")
    println("done")
}
