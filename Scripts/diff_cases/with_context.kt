// NOTE: Requires kotlinx-coroutines on classpath.
import kotlinx.coroutines.*

fun main() = runBlocking {
    // Basic withContext with dispatcher
    val result = withContext(Dispatchers.Default) {
        "hello from context"
    }
    println(result)

    // withContext with IO dispatcher
    val ioResult = withContext(Dispatchers.IO) {
        "hello from IO"
    }
    println(ioResult)

    // withContext with CoroutineName context element
    val namedResult = withContext(CoroutineName("myCoroutine")) {
        "hello from named coroutine"
    }
    println(namedResult)

    // withContext with context composition (+ operator)
    val composed = Dispatchers.Default + CoroutineName("composedCoroutine")
    val composedResult = withContext(composed) {
        "hello from composed context"
    }
    println(composedResult)

    // Nested withContext
    val nested = withContext(Dispatchers.Default) {
        val inner = withContext(Dispatchers.IO) {
            "inner"
        }
        "outer + $inner"
    }
    println(nested)

    println("done")
}
