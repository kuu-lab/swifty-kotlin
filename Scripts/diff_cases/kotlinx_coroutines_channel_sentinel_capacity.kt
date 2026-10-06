// KUU-1403: Channel.Factory sentinel capacities must not be clamped to
// rendezvous. BUFFERED (-2) expands to the default 64-slot buffer,
// CONFLATED (-1) keeps only the latest value, UNLIMITED never fills, and
// invalid negative capacities throw IllegalArgumentException.
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.*

fun main() = runBlocking {
    // Issue repro: sentinel capacities must satisfy trySend.
    val ch = Channel<Int>(Channel.BUFFERED)
    println(ch.trySend(1).isSuccess)
    println(ch.tryReceive().getOrNull())
    println(Channel<Int>(Channel.CONFLATED).trySend(7).isSuccess)
    println(Channel<Int>(Channel.UNLIMITED).trySend(5).isSuccess)
    println(Channel<Int>(3).trySend(1).isSuccess)
    println(Channel<Int>(0).trySend(1).isSuccess)

    // CONFLATED keeps only the latest value.
    val conflated = Channel<Int>(Channel.CONFLATED)
    conflated.trySend(1)
    conflated.trySend(2)
    conflated.trySend(3)
    println(conflated.tryReceive().getOrNull())
    println(conflated.tryReceive().getOrNull())

    // BUFFERED drains FIFO through the default buffer.
    val buffered = Channel<Int>(Channel.BUFFERED)
    for (i in 1..3) buffered.trySend(i)
    println(buffered.tryReceive().getOrNull())
    println(buffered.tryReceive().getOrNull())

    // Invalid negative capacities throw IllegalArgumentException.
    try {
        Channel<Int>(-3)
    } catch (e: IllegalArgumentException) {
        println("iae1: ${e.message}")
    }
    try {
        Channel<Int>(-4)
    } catch (e: IllegalArgumentException) {
        println("iae2: ${e.message}")
    }
    try {
        Channel<Int>(Channel.CONFLATED, BufferOverflow.DROP_OLDEST)
    } catch (e: IllegalArgumentException) {
        println("iae3: ${e.message}")
    }

    // produce honors the sentinel through the same factory.
    val produced = produce(capacity = Channel.BUFFERED) {
        send(10)
        send(20)
    }
    for (v in produced) println("p$v")
    println("done")
}
