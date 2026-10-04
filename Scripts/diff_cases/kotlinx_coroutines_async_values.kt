import kotlinx.coroutines.*

fun main() = runBlocking {
    val scope = CoroutineScope(SupervisorJob())
    val number = 19
    val text = "value"
    val first = scope.async { number + 2 }
    val second = scope.async { text + number }
    val value: Int = first.await()
    val message: String = second.await()
    println(value + 21)
    println(message.length)
    println(scope.async { 7 }.await() + 1)
    scope.cancel()
    println(async { 9 }.await())
}
