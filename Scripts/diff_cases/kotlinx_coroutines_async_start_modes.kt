import kotlinx.coroutines.*
import kotlin.coroutines.EmptyCoroutineContext

fun main() = runBlocking {
    val scope = CoroutineScope(SupervisorJob())
    val captured = 23
    val lazy = scope.async(start = CoroutineStart.LAZY) {
        println("lazy body: $captured")
        captured
    }
    println("before lazy await")
    println(lazy.await())
    val undispatched = scope.async(EmptyCoroutineContext, CoroutineStart.UNDISPATCHED) {
        println("undispatched before delay")
        delay(20)
        println("undispatched after delay")
        captured + 1
    }
    println("after undispatched builder")
    println(undispatched.await())

    val noncapturing = scope.async(start = CoroutineStart.UNDISPATCHED) {
        println("noncapturing before delay")
        delay(20)
        println("noncapturing after delay")
        42
    }
    println("after noncapturing builder")
    println(noncapturing.await())
    val atomic = scope.async(start = CoroutineStart.ATOMIC) { captured + 2 }
    println(atomic.await())
    scope.cancel()
}
