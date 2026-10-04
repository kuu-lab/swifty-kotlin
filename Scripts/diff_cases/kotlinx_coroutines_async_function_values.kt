import kotlinx.coroutines.*
import kotlin.coroutines.EmptyCoroutineContext

fun main() = runBlocking {
    val scope = CoroutineScope(SupervisorJob())
    val captured = 17
    val block = { captured + 1 }
    println(scope.async {
        delay(10)
        block()
    }.await())
    val start = CoroutineStart.LAZY
    val deferred = scope.async(
        block = {
            println("named block")
            captured + 2
        },
        start = start,
        context = EmptyCoroutineContext
    )
    println("before named await")
    println(deferred.await())
    scope.cancel()
}
