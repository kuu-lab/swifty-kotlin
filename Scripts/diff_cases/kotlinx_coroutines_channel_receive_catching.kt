// KSP-1572: ReceiveChannel.receiveCatching() suspends until an element
// arrives or the channel closes, reporting a ChannelResult. (receiveOrNull
// is deprecated-error in the reference kotlinx-coroutines and is not usable
// in a diff case; it is an alias of receiveCatching().getOrNull().)
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.*

fun main() = runBlocking {
    // 1. receiveCatching drains a produce channel then reports isClosed.
    val ch = produce {
        send(1)
        send(2)
    }
    while (true) {
        val r = ch.receiveCatching()
        if (r.isClosed) break
        println(r.getOrThrow())
    }

    // 2. getOrNull on a closed result yields null.
    println(ch.receiveCatching().getOrNull())

    // 3. receiveCatching suspends for the next element on a rendezvous channel.
    val ch2 = Channel<Int>()
    launch {
        ch2.send(7)
        ch2.close()
    }
    println(ch2.receiveCatching().getOrThrow())
    println(ch2.receiveCatching().getOrNull())

    // 4. receiveCatching preserves receive order across a closed channel.
    val ch3 = Channel<Int>(capacity = 3)
    launch {
        ch3.send(10)
        ch3.send(20)
        ch3.close()
    }
    var sum = 0
    while (true) {
        val r = ch3.receiveCatching()
        if (r.isClosed) break
        sum += r.getOrThrow()
    }
    println(sum)
}
