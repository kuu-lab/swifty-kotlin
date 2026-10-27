import kotlinx.coroutines.channels.Channel
fun Channel<Int>.send(value: String): Int = value.length
fun Channel<Int>.send(action: (Int) -> String): Int = action(5).length
fun main() {
    val channel = Channel<Int>(1)
    println(channel.send("hello"))
    println(channel.send { it.toString() })
    val nullable: Channel<Int>? = null
    println(nullable?.send("hello"))
}
