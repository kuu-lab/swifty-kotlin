// KUU-1133: the Channel and SendChannel extensions must coexist without
// shadowing ProducerScope's explicit or implicit receiver in bundled stdlib.
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.*
import kotlinx.coroutines.flow.*

fun main() = runBlocking {
    val channel = Channel<Int>()
    println("channel open: ${channel.isClosedForSend}")
    channel.close()
    println("channel closed: ${channel.isClosedForSend}")

    callbackFlow<Int> {
        val sink: SendChannel<Int> = this
        println("callbackFlow open: ${this.isClosedForSend},${isClosedForSend},${sink.isClosedForSend}")
        this.close()
        println("callbackFlow closed: ${this.isClosedForSend},${isClosedForSend},${sink.isClosedForSend}")
    }.collect { }

    channelFlow<Int> {
        val sink: SendChannel<Int> = this
        println("channelFlow open: ${this.isClosedForSend},${isClosedForSend},${sink.isClosedForSend}")
        this.close()
        println("channelFlow closed: ${this.isClosedForSend},${isClosedForSend},${sink.isClosedForSend}")
    }.collect { }

    val produced = produce<Int> {
        val sink: SendChannel<Int> = this
        println("produce open: ${this.isClosedForSend},${isClosedForSend},${sink.isClosedForSend}")
        this.close()
        println("produce closed: ${this.isClosedForSend},${isClosedForSend},${sink.isClosedForSend}")
    }
    for (value in produced) { }
}
