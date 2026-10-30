// NOTE: Requires kotlinx-coroutines on classpath.
// KUU-3847: consumeEach/for-in on a cause-less closed channel completes
// normally instead of panicking (a raw channel handle flowing through an
// Any?/generic slot used to fail its `as Channel` check and escape as an
// unhandled ClassCastException). A channel closed WITH a cause still
// propagates the cause through the iterator hasNext after draining.
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.*

// Passing a channel through a generic receiver/lambda slot must not throw.
fun <T, R> T.myLet(block: (T) -> R): R = block(this)

fun main() = runBlocking {
    // 1. consumeEach on a cause-less closed channel completes normally.
    val ch1 = Channel<Int>()
    ch1.close()
    ch1.consumeEach { println("unreachable $it") }
    println("consumeEach closed: done")

    // 2. consumeEach drains buffered elements then ends.
    val ch2 = Channel<Int>(4)
    ch2.trySend(1)
    ch2.trySend(2)
    ch2.close()
    var sum = 0
    ch2.consumeEach { sum += it }
    println("sum: $sum")

    // 3. consume keeps working over a live channel.
    val ch3 = Channel<Int>(2)
    ch3.trySend(5)
    ch3.close()
    ch3.consume { println("in consume") }
    println("consume: done")

    // 4. close(cause) propagates the cause through consumeEach.
    val ch4 = Channel<Int>()
    ch4.close(IllegalStateException("boom"))
    try {
        ch4.consumeEach { println("unreachable $it") }
        println("consumeEach cause: no throw")
    } catch (e: IllegalStateException) {
        println("consumeEach cause threw: ${e.message}")
    }

    // 5. for-in drains buffered elements before propagating the close cause.
    val ch5 = Channel<Int>(2)
    ch5.trySend(7)
    ch5.close(IllegalStateException("late"))
    try {
        for (x in ch5) println("elem $x")
        println("for cause: no throw")
    } catch (e: IllegalStateException) {
        println("for cause threw: ${e.message}")
    }

    // 6. Channel handles answer is/as checks like kotlinx.
    val ch6 = Channel<Int>()
    val a: Any? = ch6
    println("is Channel: ${a is Channel<*>}")
    println("is SendChannel: ${a is SendChannel<*>}")
    println("is ReceiveChannel: ${a is ReceiveChannel<*>}")
    println("is Job: ${a is Job}")
    val back = a as Channel<*>
    back.close()

    // 7. ChannelIterator handles answer is checks too.
    val it: Any? = ch6.iterator()
    println("is ChannelIterator: ${it is ChannelIterator<*>}")

    // 8. A channel flowing through a generic lambda slot invokes normally.
    println("myLet: ${ch6.myLet { 42 }}")

    println("done")
}
