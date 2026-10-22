// KUU-2686: select waiters rendezvous atomically. A parked `onSend` offer is
// claimed by another select's `onReceive` (and vice versa) in a single
// channel-lock critical section, so the same rendezvous resolves exactly
// once — sequential readiness polling could never pair two selects.
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.*
import kotlinx.coroutines.selects.*

fun main() = runBlocking {
    // Parked onSend offer claimed by another select's onReceive.
    val ch = Channel<Int>()
    val inbox = Channel<String>(1)
    val sender = launch {
        val outcome = select<String> { ch.onSend(7) { "sent" }; onTimeout(2000L) { "send-timeout" } }
        inbox.send(outcome)
    }
    delay(50)
    println(select<String> { ch.onReceive { "got:$it" }; onTimeout(2000L) { "recv-timeout" } })
    println(inbox.receive())
    sender.join()

    // Symmetric: parked onReceive offer claimed by another select's onSend.
    val receiver = launch {
        val outcome = select<String> { ch.onReceive { "got2:$it" }; onTimeout(2000L) { "recv2-timeout" } }
        inbox.send(outcome)
    }
    delay(50)
    println(select<String> { ch.onSend(9) { "sent2" }; onTimeout(2000L) { "send2-timeout" } })
    println(inbox.receive())
    receiver.join()

    // Two selects racing one rendezvous: exactly one clause consumes it.
    val one = Channel<Int>()
    launch { one.send(42) }
    delay(50)
    val a = async { select<String> { one.onReceive { "got:$it" }; onTimeout(300L) { "timeout" } } }
    val b = async { select<String> { one.onReceive { "got:$it" }; onTimeout(300L) { "timeout" } } }
    println(listOf(a.await(), b.await()).sorted().joinToString(","))
    println("done")
}
