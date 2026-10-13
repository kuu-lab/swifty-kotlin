import kotlinx.coroutines.*

// KUU-1977: List.map and Iterable.map inherit suspension through inline lambdas.
inline fun direct(block: () -> Int): Int = block()

suspend fun awaitMapped(jobs: List<Deferred<Int>>): List<Int> = jobs.map { it.await() }

fun main() = runBlocking {
    val jobs = (1..3).map { n -> async { delay(1); n * n } }
    val iterable: Iterable<Deferred<Int>> = jobs
    println(jobs.map { it.await() })
    println(iterable.map { it.await() })
    println(jobs.map { direct { it.await() } })
    println(iterable.map { direct { it.await() } })
    println(awaitMapped(jobs))
}
