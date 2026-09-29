// NOTE: Requires kotlinx-coroutines on classpath.
// KSP-1571: bundled channel send/close/consume surface — trySend,
// close(cause), isClosedForSend, isClosedForReceive, isEmpty, consume,
// consumeEach, cancel, and the ChannelResult holder API.
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.*
import kotlinx.coroutines.flow.*

fun main() = runBlocking {
    // 1. trySend success path on a buffered channel
    val ch = Channel<Int>(2)
    val r1 = ch.trySend(7)
    println("r1 isSuccess: ${r1.isSuccess}")
    println("r1 isFailure: ${r1.isFailure}")
    println("r1 isClosed: ${r1.isClosed}")

    // 2. trySend on a full channel fails without being closed
    val full = Channel<Int>(1)
    full.trySend(1)
    val r2 = full.trySend(2)
    println("r2 isFailure: ${r2.isFailure}")
    println("r2 isClosed: ${r2.isClosed}")
    println("r2 getOrNull: ${r2.getOrNull()}")

    // 3. close(cause) retains the cause; trySend reports it via ChannelResult
    val ch3 = Channel<Int>()
    println("first close: ${ch3.close(IllegalStateException("boom"))}")
    println("second close: ${ch3.close()}")
    val r3 = ch3.trySend(9)
    println("r3 isClosed: ${r3.isClosed}")
    println("r3 cause: ${r3.exceptionOrNull()?.message}")
    try {
        r3.getOrThrow()
        println("getOrThrow: no throw")
    } catch (e: IllegalStateException) {
        println("getOrThrow threw: ${e.message}")
    }
    r3.onClosed { println("onClosed: ${it?.message}") }
    r3.onFailure { println("onFailure: ${it?.message}") }
    r3.getOrElse { println("getOrElse fallback") }

    // 4. SendChannel surface through callbackFlow's ProducerScope receiver
    callbackFlow<Int> {
        println("scope open: ${!this.isClosedForSend}")
        val pr = this.trySend(11)
        pr.onSuccess { println("scope trySend: ok") }
        println("scope closed: ${this.isClosedForSend}")
        this.close()
        println("scope closed: ${this.isClosedForSend}")
    }.collect { println("collected: $it") }

    // 5. isEmpty tracks buffer occupancy
    val ch5 = Channel<Int>(1)
    println("empty: ${ch5.isEmpty}")
    ch5.send(1)
    println("buffered: ${ch5.isEmpty}")
    ch5.receive()
    println("drained: ${ch5.isEmpty}")
    println("ch5 closed for receive: ${ch5.isClosedForReceive}")

    // 6. consumeEach drains a closed channel then cancels it
    val ch6 = Channel<Int>(3)
    ch6.send(1)
    ch6.send(2)
    ch6.close()
    var sum = 0
    ch6.consumeEach { sum += it }
    println("consumeEach sum: $sum")
    println("ch6 closed: ${ch6.isClosedForSend}")

    // 7. consume returns a value, then its implicit cancel closes the channel
    //    with a default CancellationException; remaining buffered elements stay
    //    (JVM semantics: cancel does not discard the buffer).
    val ch7 = Channel<Int>(3)
    ch7.send(5)
    ch7.send(6)
    val first = ch7.consume {
        val it = this.iterator()
        if (it.hasNext()) it.next() as Int else -1
    }
    println("consume first: $first")
    println("ch7 cancelled: ${ch7.isClosedForSend}")
    println("ch7 still has element: ${!ch7.isEmpty}")

    // 8. closed-without-cause result: trySend wraps a ClosedSendChannelException
    //    as the close cause (upstream sendException semantics)
    val ch8 = Channel<Int>()
    ch8.close()
    val r8 = ch8.trySend(3)
    println("r8 isClosed: ${r8.isClosed}")
    println("r8 cause null: ${r8.exceptionOrNull() == null}")
    try {
        r8.getOrThrow()
        println("r8 getOrThrow: no throw")
    } catch (e: ClosedSendChannelException) {
        println("r8 getOrThrow threw: ${e.message}")
    }

    // NOTE: ChannelResult.success/failure/closed are @InternalCoroutinesApi
    // upstream — the kotlinc reference refuses user calls, so they are
    // excluded from this diff case (the bundled surface still provides them).

    println("done")
}
