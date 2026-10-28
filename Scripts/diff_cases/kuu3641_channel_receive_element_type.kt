// KUU-3641: explicit Channel.receive() retains the element type, projections,
// nullable elements, safe-call nullability, and the existing runtime behavior.
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.channels.ClosedReceiveChannelException

suspend fun get(ch: Channel<Int>): Int = ch.receive()
suspend fun nullable(ch: Channel<String?>): String? = ch.receive()
suspend fun outProjected(ch: Channel<out String?>): String? = ch.receive()
suspend fun inProjected(ch: Channel<in String>): Any? = ch.receive()
suspend fun starProjected(ch: Channel<*>): Any? = ch.receive()
suspend fun safeNullable(ch: Channel<String?>?): String? = ch?.receive()
suspend fun safeNonNull(ch: Channel<Int>?): Int? = ch?.receive()

fun main() = runBlocking {
    val intChannel = Channel<Int>(1)
    intChannel.send(42)
    println(get(intChannel))

    val nullableChannel = Channel<String?>(1)
    nullableChannel.send(null)
    println(nullable(nullableChannel) == null)

    val outChannel = Channel<String?>(1)
    outChannel.send("out")
    println(outProjected(outChannel))

    val inChannel = Channel<Any?>(1)
    inChannel.send(9)
    println(inProjected(inChannel))

    val starChannel = Channel<Int>(1)
    starChannel.send(11)
    println(starProjected(starChannel))

    println(safeNullable(null))
    println(safeNonNull(null))

    val rendezvousChannel = Channel<Int>(0)
    val sender = launch { rendezvousChannel.send(13) }
    println(get(rendezvousChannel))
    sender.join()

    val closedChannel = Channel<Int>(1)
    closedChannel.close()
    try {
        closedChannel.receive()
        println("missing")
    } catch (_: ClosedReceiveChannelException) {
        println("closed")
    }
}
