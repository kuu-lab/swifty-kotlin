// KUU-4072: `Channel<E>` is an interface upstream
// (`interface Channel<E> : SendChannel<E>, ReceiveChannel<E>`), so
// Turbine-style wrappers can delegate to it and override its members.
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.channels.ChannelResult
import kotlinx.coroutines.runBlocking

private class TurbineChannel<T>(private val channel: Channel<T>) : Channel<T> by channel {
    override fun tryReceive(): ChannelResult<T> =
        channel.tryReceive()

    override suspend fun receiveCatching(): ChannelResult<T> =
        channel.receiveCatching()
}

fun main() {
    runBlocking {
        val ch = Channel<Int>(Channel.UNLIMITED)
        ch.trySend(41)
        val wrapped = TurbineChannel(ch)
        println(wrapped.tryReceive().getOrNull())
        ch.trySend(1)
        println(wrapped.receiveCatching().getOrNull())
        println(ch.isClosedForSend)
        println(ch.isEmpty)
        ch.close()
        println(ch.isClosedForReceive)
        println(wrapped.isClosedForSend)
    }
}
