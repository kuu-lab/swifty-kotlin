import kotlinx.coroutines.*
import kotlinx.coroutines.channels.*
import kotlinx.coroutines.selects.*

fun main() = runBlocking {
    val first = Channel<Int>(2)
    val second = Channel<Int>(2)
    first.send(10)
    second.send(20)
    println(select<String> {
        first.onReceive { "first:$it" }
        second.onReceive { "second:$it" }
    })
    println(second.receive())
    println(select<String> {
        first.onReceive { "unexpected:$it" }
        onTimeout(0L) { "timeout" }
    })
    println(select<String> {
        first.onSend(30) { "sent" }
        onTimeout(0L) { "unexpected" }
    })
    println(first.receive())
    first.close()
    println(select<String> {
        first.onReceiveCatching { if (it.isClosed) "closed" else "unexpected" }
    })
    println("done")
}
