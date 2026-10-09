// KUU-1078: an unbound suspend reference accepts a receiver function type.
import kotlinx.coroutines.*

suspend fun String.report(extra: Int): String {
    delay(1)
    return "$this:$extra"
}

suspend fun invokeBody(body: suspend String.(Int) -> String) {
    println(body("receiver", 9))
}

fun main() {
    runBlocking {
        invokeBody(String::report)
        val typed: suspend String.(Int) -> String = String::report
        invokeBody(typed)
        val inferred = String::report
        invokeBody(inferred)
    }
}
