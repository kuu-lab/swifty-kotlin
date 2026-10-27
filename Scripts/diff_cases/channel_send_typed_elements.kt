import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.channels.Channel

fun main() {
    runBlocking {
        val integers = Channel<Int>(1)
        integers.send(7)
        println(integers.receive())
        val nullable = Channel<String?>(1)
        nullable.send(null)
        println(nullable.receive())
    }
}
