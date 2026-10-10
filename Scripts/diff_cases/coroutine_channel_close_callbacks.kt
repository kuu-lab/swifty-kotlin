import kotlinx.coroutines.channels.*

fun registerClose(channel: SendChannel<Int>, handler: (Throwable?) -> Unit) {
    channel.invokeOnClose(handler)
}

fun referenceClose(cause: Throwable?) {
    println("reference:" + (cause == null))
}

fun main() {
    var calls = 0
    val label = "stored"
    val amount = 2
    val handler: (Throwable?) -> Unit = { cause ->
        calls += amount
        println(label + ":" + (cause == null))
    }
    val stored = Channel<Int>(1)
    registerClose(stored, handler)
    println("first:" + stored.close())
    println("second:" + stored.close())
    println("stored-calls:" + calls)

    val literal = Channel<Int>(1)
    literal.invokeOnClose { cause ->
        calls++
        println("literal:" + (cause == null))
    }
    literal.close()
    println("literal-calls:" + calls)

    val reference = Channel<Int>(1)
    reference.invokeOnClose(::referenceClose)
    reference.close()

    val closed = Channel<Int>(1)
    closed.close()
    closed.invokeOnClose { cause -> println("late:" + (cause == null)) }
}
