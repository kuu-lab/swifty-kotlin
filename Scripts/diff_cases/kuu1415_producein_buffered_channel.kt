// KUU-1415: Flow.produceIn must use a buffered channel — upstream routes it
// through ChannelFlow.produceImpl with the default buffer size. A rendezvous
// channel parks the producer mid-collection and deadlocks runBlocking's
// child-join whenever the consumer takes fewer elements than the flow emits.
// Channel(capacity = ...) must also honor the Channel.Factory sentinels —
// BUFFERED used to be clamped to a rendezvous channel.
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.*
import kotlinx.coroutines.flow.*

fun main() = runBlocking {
    // Partial receive: the buffered producer runs to completion and closes
    // the channel even though the consumer only takes the first element.
    val partial = flowOf(1, 2).produceIn(this)
    println("partial: ${partial.receive()}")

    // produce(capacity = Channel.BUFFERED): sends complete without a waiting
    // receiver, so a partial receive still lets the producer finish.
    val explicit = produce(capacity = Channel.BUFFERED) {
        send(10)
        send(20)
    }
    println("explicit: ${explicit.receive()}")

    // Channel(Channel.BUFFERED) does not suspend a send with no receiver.
    val buffered = Channel<Int>(Channel.BUFFERED)
    buffered.send(7)
    println("buffered: ${buffered.receive()}")

    // Full drain still works and observes the channel closing.
    val drained = mutableListOf<Int>()
    for (item in flowOf(4, 5, 6).produceIn(this)) {
        drained.add(item)
    }
    println("drained: $drained")

    println("done")
}
