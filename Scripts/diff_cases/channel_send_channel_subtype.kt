import kotlinx.coroutines.*
import kotlinx.coroutines.channels.*

fun main() {
    val channel = Channel<Int>()
    val sink: SendChannel<Int> = channel
    println(sink.isClosedForSend)
    channel.close()
    println(sink.isClosedForSend)

    runBlocking {
        val buffered = Channel<Int>(2)
        val sender: SendChannel<Int> = buffered
        sender.send(7)
        println(sender.trySend(9).isSuccess)
        println(buffered.receive())
        println(buffered.receive())
        println(sender.close())
        println(sender.trySend(11).isClosed)

        val broad = Channel<Any>(1)
        val narrow: SendChannel<String> = broad
        println(narrow.trySend("value").isSuccess)
        println(broad.receive())
        println(narrow.close(null))
    }
}
