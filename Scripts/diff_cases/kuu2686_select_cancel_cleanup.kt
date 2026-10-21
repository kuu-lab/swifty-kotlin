// KUU-2686: cancelling a select disposes its parked channel offers. The
// dead waiters must not consume later rendezvous traffic — the next
// receiver gets the element and a fresh select still works on the channel.
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.*
import kotlinx.coroutines.selects.*
import kotlin.coroutines.cancellation.CancellationException

fun main() = runBlocking {
    val ch = Channel<Int>()
    val other = Channel<Int>()
    val job = launch {
        try {
            select<Unit> {
                ch.onReceive { }
                other.onReceive { }
                onTimeout(5000L) { }
            }
            println("selected")
        } catch (e: CancellationException) {
            println("cancelled")
            throw e
        }
    }
    delay(100)
    job.cancel()
    job.join()
    println("joined")

    // The cancelled select's receive waiters must not steal this send.
    val delivered = Channel<Int>(1)
    launch { delivered.send(ch.receive() * 10) }
    ch.send(5)
    println(delivered.receive())

    // A new select on the same channel still pairs normally.
    launch { ch.send(9) }
    println(select<String> { ch.onReceive { "again:$it" }; onTimeout(2000L) { "timeout" } })
    println("done")
}
