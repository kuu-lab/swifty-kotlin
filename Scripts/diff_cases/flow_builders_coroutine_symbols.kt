import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*

suspend fun compute(): Int = withContext(Dispatchers.Default) {
    var total = 0
    for (i in 1..100) {
        total += i
    }
    total
}

suspend fun ioTask(): String = withContext(Dispatchers.IO) {
    delay(1)
    "io-result"
}

fun main() = runBlocking {
    flowOf(1, 2, 3)
        .map { it * 10 }
        .collect { println(it) }

    listOf(4, 5, 6)
        .asFlow()
        .collect { println(it) }

    emptyFlow<Int>().collect { println(it) }
    println("empty-done")

    println("compute: ${compute()}")
    println("io: ${ioTask()}")

    val base = 1000
    flow {
        for (i in 1..3) {
            emit(base + i)
        }
    }.collect { println(it) }
}
