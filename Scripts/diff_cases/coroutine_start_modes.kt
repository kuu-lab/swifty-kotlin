import kotlinx.coroutines.*

// `launch(start = ...)` must honour the requested CoroutineStart.
// Lowering used to route ANY `CoroutineStart`-typed first argument to the lazy
// runtime and never read the value, so DEFAULT, ATOMIC and UNDISPATCHED all
// silently behaved as LAZY -- the body did not run until something joined it.

fun main() = runBlocking {
    // The reported repro: UNDISPATCHED runs the body inline on the calling
    // thread until its first suspension, so "undispatched1" precedes
    // "after launch".
    val undispatched = launch(start = CoroutineStart.UNDISPATCHED) {
        println("undispatched1")
        yield()
        println("undispatched2")
    }
    println("after launch")
    undispatched.join()

    // Capture-bearing UNDISPATCHED block: same inline start, but routed through
    // the launcher-thunk (continuation) shape instead of the bare functionID.
    val captured = "captured"
    val undispatchedCapturing = launch(start = CoroutineStart.UNDISPATCHED) {
        println("undispatched capture: $captured")
    }
    println("after capturing launch")
    undispatchedCapturing.join()

    // DEFAULT schedules the body immediately, so a single yield is enough to
    // run it -- no join required. Under LAZY it would still not have started.
    val default = launch(start = CoroutineStart.DEFAULT) { println("default body") }
    println("after default launch")
    yield()
    println("default completed without join: ${default.isCompleted}")
    default.join()

    // ATOMIC likewise starts without a join.
    val atomic = launch(start = CoroutineStart.ATOMIC) { println("atomic body") }
    println("after atomic launch")
    yield()
    println("atomic completed without join: ${atomic.isCompleted}")
    atomic.join()

    // LAZY still defers until join().
    val lazy = launch(start = CoroutineStart.LAZY) { println("lazy body") }
    println("after lazy launch")
    yield()
    println("lazy completed without join: ${lazy.isCompleted}")
    lazy.join()
    println("lazy completed after join: ${lazy.isCompleted}")
}
