import kotlinx.coroutines.*
import kotlin.coroutines.EmptyCoroutineContext

fun CoroutineScope.g() {
    launch(EmptyCoroutineContext) {
        val nested = Job()
        try {
            throw IllegalStateException("root")
        } catch (cause: Throwable) {
            nested.cancel("boom", cause)
        }
        println("nested=${nested.isCancelled}")
    }.apply {
        invokeOnCompletion { println("handler") }
    }
}

fun main() = runBlocking {
    g()
    val second = Job()
    second.cancel("only message")
    println("second=${second.isCancelled}")
    println("done")
}
