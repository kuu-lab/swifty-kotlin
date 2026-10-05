import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*

fun main() = runBlocking {
    val limit = 30
    println(flowOf(10, 20, 30, 40).filter { delay(1); it <= limit }.toList())
    println(flowOf(10, 20, 30, 40).filterNot { delay(1); it <= limit }.toList())
    println(flowOf(10, 20, 30, 40).dropWhile { delay(1); it < 20 }.toList())
    println(flowOf(10, 20, 30, 40).takeWhile { delay(1); it <= limit }.toList())
    try {
        flowOf(1, 2, 3).filter { delay(1); true }.collect {
            delay(1)
            println(it)
            if (it == 2) throw IllegalStateException("collector")
        }
    } catch (e: IllegalStateException) {
        println(e.message)
    }
    withContext(Dispatchers.Default) {
        println(flowOf(10, 20, 30).filter { delay(1); it <= 20 }.toList())
        println(flowOf(10, 20, 30).dropWhile { delay(1); it < 20 }.toList())
    }
}
