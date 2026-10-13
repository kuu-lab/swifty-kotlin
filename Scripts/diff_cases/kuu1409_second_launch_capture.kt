// KUU-1409: a second bare `launch {}`/`async {}` after a suspend boundary must
// still observe locals declared before the suspension. Liveness did not count
// the callable's captureArguments, so the capture's backing register was never
// spilled and reloaded as 0/null after resume (object captures could SIGILL).
import kotlinx.coroutines.*

class Box(val v: Int)

suspend fun worker(p: Int) = coroutineScope {
    launch { println("param1:$p") }.join()
    launch { println("param2:$p") }.join()
}

fun main() = runBlocking {
    val a = "alpha"; val n = 41
    launch { println("one:$a") }.join()
    launch { println("two:$n") }.join()

    // async after a suspend boundary hits the same capture-loss hazard.
    println("sum:${async { n + 1 }.await()}")

    // var store into a pre-suspend local through a post-suspend launch.
    var c = 0
    launch { c = n + a.length }.join()
    println("c=$c")

    // Object reference capture read in a post-suspend launch (SIGILL shape).
    val o = Box(9)
    launch { println("box:${o.v}") }.join()

    // Local declared pre-suspend shared by both launches.
    launch { println("shared:$a$n") }.join()

    worker(7)
    println("done")
}
