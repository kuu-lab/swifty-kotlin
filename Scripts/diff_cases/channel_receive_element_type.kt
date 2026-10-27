import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.channels.ReceiveChannel
import kotlinx.coroutines.runBlocking

class UserTypes {
    class Channel<T> { fun receive(): String = "custom" }
}

fun main() = runBlocking {
    val numbers = Channel<Int>(1)
    numbers.send(7)
    println(numbers.receive() * 3)
    numbers.send(8)
    val alias: ReceiveChannel<Int> = numbers
    println(alias.receive())
    val strings = Channel<String?>(2)
    strings.send(null)
    strings.send("value")
    println(strings.receive() ?: "null")
    println(strings.receive())
    println(UserTypes.Channel<Int>().receive())
}
