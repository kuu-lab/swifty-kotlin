import kotlinx.coroutines.*

fun main() = runBlocking {
    try {
        coroutineScope {
            val d = async { throw RuntimeException("boom") }
            d.await()
        }
    } catch (e: Throwable) {
        println("caught")
    }
}
