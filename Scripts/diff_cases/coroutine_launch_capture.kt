// BUG-049: a suspend lambda launched via launch { }, launch(dispatcher) { }, or
// CoroutineScope.launch { } that captures outer variables must forward those captures
// through the launcher continuation instead of failing coroutine lowering with
// KSWIFTK-CORO-0003 ("... passed 0 capture argument(s) ...").
import kotlinx.coroutines.*

suspend fun <T> doWork(action: () -> T): T = action()

fun main() = runBlocking {
    // Bare launch capturing a mutable outer variable.
    var bare = 0
    launch { doWork { bare++ } }.join()
    println("bare=$bare")

    // Dispatcher-aware launch capturing a mutable outer variable.
    var dispatched = 0
    launch(Dispatchers.Default) { doWork { dispatched++ } }.join()
    println("dispatched=$dispatched")

    // Explicit CoroutineScope.launch capturing a mutable outer variable.
    val scope = CoroutineScope(Dispatchers.Default)
    var scoped = 0
    scope.launch { doWork { scoped++ } }.join()
    println("scoped=$scoped")

    // Multiple captures forwarded together.
    var a = 3
    val b = 4
    scope.launch { doWork { a = a + b } }.join()
    println("multi=$a")
}
