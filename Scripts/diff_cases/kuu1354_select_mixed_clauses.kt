// KUU-1354: mixing `onReceive` and `onAwait` clauses in one `select` SIGSEGV'd
// (the `launch` lambda's captured channel was clobbered by the launcherArgs
// scope slot — KUU-1400). When every clause is already ready at select time,
// registration order decides deterministically on both JVM and KSwiftK, so
// both orders are pinned here. A losing rendezvous sender stays parked while
// runBlocking waits for children — the same deadlock kotlinx shows — so the
// second half uses a buffered channel to keep the losing send completable.
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.*
import kotlinx.coroutines.selects.*

fun main() = runBlocking {
    // onReceive registered first: claims the already-parked sender.
    val rendezvous = Channel<Int>()
    val deferred = async { 10 }
    val sender = launch { rendezvous.send(20) }
    delay(50)
    println(select<Int> { rendezvous.onReceive { it * 10 }; deferred.onAwait { it * 100 } })
    sender.join()

    // onAwait registered first: claims the completed deferred; the buffered
    // channel lets the losing send complete instead of parking a child.
    val buffered = Channel<Int>(1)
    val deferred2 = async { 7 }
    launch { buffered.send(30) }
    delay(50)
    println(select<Int> { deferred2.onAwait { it * 100 }; buffered.onReceive { it * 10 } })
}
