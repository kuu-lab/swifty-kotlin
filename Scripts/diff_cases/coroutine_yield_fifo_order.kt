import kotlinx.coroutines.*

// `yield()` must re-dispatch the current coroutine to the TAIL of
// runBlocking's event loop, so resumption order is FIFO and identical on every
// run. Before the fix there was no ready queue at all: every resumption hop
// went to the concurrent global dispatch pool and `yield()` additionally waited
// out a 1ms timer, so the interleavings below were decided by thread races and
// varied from run to run.

fun main() {
    // The reported repro. Queue after the first burst is [A, B, main], and each
    // yield moves the yielding coroutine behind the two others.
    runBlocking {
        launch { println("A1"); yield(); println("A2") }
        launch { println("B1"); yield(); println("B2") }
        println("M"); yield(); println("M2"); yield(); println("M3")
    }

    // Three children and two yields each: the round-robin has to hold over
    // several full passes, not just the first one.
    runBlocking {
        repeat(3) { index ->
            launch {
                println("child $index round 1")
                yield()
                println("child $index round 2")
            }
        }
        println("parent start")
        yield()
        println("parent middle")
        yield()
        println("parent end")
    }

    // A child that launches a grandchild: the grandchild joins the same queue,
    // behind whatever was already waiting, and a `join()` in the middle of the
    // chain resumes its waiter through the queue rather than out of band.
    // Everything is joined explicitly: `runBlocking` returning before its
    // children finish is a separate, pre-existing gap.
    runBlocking {
        val outer = launch {
            println("outer 1")
            val inner = launch { println("inner 1"); yield(); println("inner 2") }
            yield()
            println("outer 2")
            inner.join()
            println("outer 3")
        }
        println("root 1")
        yield()
        println("root 2")
        yield()
        println("root 3")
        outer.join()
        println("root 4")
    }
}
