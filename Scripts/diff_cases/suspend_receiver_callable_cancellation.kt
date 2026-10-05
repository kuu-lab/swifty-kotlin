import kotlinx.coroutines.*

class Sink {
    val items = mutableListOf<Int>()
    fun append(value: Int) { items.add(value) }
}

suspend fun latest(transform: suspend Sink.(Int) -> Unit): List<Int> {
    val sink = Sink()
    coroutineScope {
        var previous: Job? = null
        for (value in listOf(1, 2)) {
            previous?.cancel()
            previous?.join()
            previous = launch(start = CoroutineStart.UNDISPATCHED) {
                sink.transform(value)
            }
        }
        previous?.join()
    }
    return sink.items
}

fun main() {
    runBlocking {
        println(latest {
            append(it)
            delay(20)
            append(it * 10)
        })
    }
}
