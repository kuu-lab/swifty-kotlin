import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.channels.*
import kotlinx.coroutines.flow.*

fun main() = runBlocking {
    val channel = Channel<Int>(3)
    channel.send(1)
    channel.send(2)
    channel.close()
    val received = channel.receiveAsFlow()
    println(received.toList())
    println(received.toList())

    val consumed = Channel<String>(2)
    consumed.send("a")
    consumed.send("b")
    consumed.close()
    val once = consumed.consumeAsFlow()
    println(once.toList())
    try {
        once.toList()
    } catch (e: IllegalStateException) {
        println(e.message)
    }
    println("done")
}
