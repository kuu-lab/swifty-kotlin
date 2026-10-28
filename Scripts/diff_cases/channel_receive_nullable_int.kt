import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.runBlocking

fun main() = runBlocking {
    val numbers = Channel<Int?>(3)
    numbers.send(null)
    numbers.send(0)
    numbers.send(7)
    println(numbers.receive() ?: -1)
    println(numbers.receive() ?: -1)
    println(numbers.receive() ?: -1)
}
