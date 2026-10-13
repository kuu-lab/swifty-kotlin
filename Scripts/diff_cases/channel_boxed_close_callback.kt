import kotlinx.coroutines.channels.*

fun main() {
    val channel = Channel<Int>(1)
    var calls = 0
    val callback: (Throwable?) -> Unit = { cause ->
        calls++
        println(cause == null)
    }
    channel.invokeOnClose(callback)
    println(channel.close())
    println(calls)
}
