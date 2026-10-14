import kotlinx.coroutines.*
import kotlinx.coroutines.channels.*

fun main() = runBlocking {
    val channel = Channel<Int>()
    val waiter = launch(start = CoroutineStart.UNDISPATCHED) {
        channel.send(42)
        println("sent")
    }
    println("receive")
    println(channel.receive())
    waiter.join()

    val closing = Channel<Int>()
    val failed = launch(start = CoroutineStart.UNDISPATCHED) {
        try {
            closing.send(1)
        } catch (e: ClosedSendChannelException) {
            println("closed")
        }
    }
    closing.cancel()
    failed.join()

    val stuck = Channel<Int>()
    val cancelled = launch(start = CoroutineStart.UNDISPATCHED) {
        try {
            stuck.send(1)
        } catch (e: CancellationException) {
            println("cancelled")
            throw e
        }
    }
    cancelled.cancelAndJoin()
    println(stuck.tryReceive().isSuccess)
}
