import kotlinx.coroutines.*
import kotlinx.coroutines.channels.*

@Suppress("DEPRECATION", "DEPRECATION_ERROR")
@OptIn(ObsoleteCoroutinesApi::class)
fun main() = runBlocking {
    // runInterruptible
    val ri = runInterruptible { 40 + 2 }
    println(ri)
    val riCtx = runInterruptible(Dispatchers.Default) { "interruptible" }
    println(riCtx)

    // ExecutorCoroutineDispatcher.close()
    val dispatcher = newSingleThreadContext("worker")
    dispatcher.close()
    println("closed")

    // BroadcastChannel
    val bc = BroadcastChannel<Int>(8)
    val sub1 = bc.openSubscription()
    val sub2 = bc.openSubscription()
    bc.send(1)
    bc.send(2)
    println(sub1.receive())
    println(sub2.receive())
    println(sub1.receive())
    bc.close()
    println(sub1.isClosedForReceive)
    println(bc.isClosedForSend)

    // ConflatedBroadcastChannel
    val cb = ConflatedBroadcastChannel<String>()
    val csub = cb.openSubscription()
    cb.send("first")
    cb.send("second")
    println(cb.value)
    println(csub.receive())

    // trySend path
    val tb = BroadcastChannel<Int>(4)
    val tsub = tb.openSubscription()
    println(tb.trySend(7).isSuccess)
    println(tsub.receive())
    tb.cancel()
    println(tb.isClosedForSend)
}
