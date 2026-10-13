// KUU-1400: a launch/async block captures-first lowered coroutineScope-receiver
// lambda must receive the receiver scope in the launcherArgs slot AFTER all
// captures, not in the last capture's slot. `params.count - 1` landed the child
// scope on the last capture, corrupting it — a captured channel was replaced by
// a RuntimeCoroutineScope (SIGSEGV in kk_channel_send / waitForChildren) and a
// captured value arrived null.
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.*

fun main() = runBlocking {
    // Single capture read directly in the block: the child scope used to land
    // in the only capture slot, so `msg` arrived as the scope (null-printing).
    val msg = "hello"
    launch { println("launch:$msg") }.join()

    // Multiple captures: only the LAST one was clobbered.
    val first = "keep"
    val last = "last"
    launch { println("multi:$first,$last") }.join()

    // async block captures-first too.
    val who = "async"
    println("await:${async { who }.await()}")

    // Captured channel used inside a nested suspend call: the clobbered
    // handle reached kk_channel_send as a RuntimeCoroutineScope → SIGSEGV.
    val entered = Channel<Unit>(1)
    launch {
        withContext(NonCancellable) {
            entered.send(Unit)
        }
    }.join()
    println("channel:${entered.receive()}")

    println("done")
}
