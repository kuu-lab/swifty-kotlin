import kotlinx.coroutines.*

// DEBT-CORO-005 / BUG-041 regression: a child launched with the default start
// mode that is cancelled synchronously (no intervening suspension point) before
// it begins executing must never run its body -- so the `finally` block does not
// run. kotlinx.coroutines/JVM prints only "done"; a scheduling race that let the
// child start would additionally print "finally".
fun main() = runBlocking {
    val job = launch {
        try {
            delay(Long.MAX_VALUE)
        } finally {
            println("finally")
        }
    }
    job.cancel()
    job.join()
    println("done")
}
