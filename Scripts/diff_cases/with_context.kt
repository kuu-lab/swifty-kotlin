// NOTE: Requires kotlinx-coroutines on classpath.
import kotlinx.coroutines.*

fun main() = runBlocking {
    // Basic withContext with Dispatchers.Default
    val result = withContext(Dispatchers.Default) {
        "hello from context"
    }
    println(result)

    // withContext with Dispatchers.IO
    val ioResult = withContext(Dispatchers.IO) {
        "hello from IO"
    }
    println(ioResult)

    // withContext with CoroutineName context element
    val namedResult = withContext(CoroutineName("myCoroutine")) {
        "hello from named coroutine"
    }
    println(namedResult)

    // withContext with composed context: Dispatchers.Default + CoroutineName
    val composedResult = withContext(Dispatchers.Default + CoroutineName("composedCoroutine")) {
        "hello from composed context"
    }
    println(composedResult)
}
