import kotlinx.coroutines.*

fun main() {
    runBlocking {
        val parked = launch {
            try {
                awaitCancellation()
            } finally {
                println("parked cleanup")
            }
        }
        launch {
            yield()
            parked.cancel()
        }
        yield()
        println("body finished")
    }
    println("runBlocking returned")
}
