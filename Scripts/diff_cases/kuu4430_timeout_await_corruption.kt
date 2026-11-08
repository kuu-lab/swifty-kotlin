import kotlinx.coroutines.*

fun main() = runBlocking<Unit> {
    try { withTimeout(1) { delay(10000) } } catch (e: TimeoutCancellationException) { println("tce") }
    val a = async { delay(100); 5 }; println(a.await())
    val b = async<Int> { delay(10); 6 }; println(b.await())
    val c = async<Int> { delay(100); 7 }; println(c.await())
    val e = async<Int> { delay(100); 8 }; delay(200); println(e.await())
}
