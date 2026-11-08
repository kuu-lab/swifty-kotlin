// NOTE: Requires kotlinx-coroutines on classpath.
// KUU-4366: a produce()/actor() receiver is the channel itself, so
// consumeEach / consume / `is`/`as` checks against the Channel-family types
// must answer like kotlinx instead of throwing
// "ProducerScope cannot be cast to Channel".
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.*

@OptIn(ObsoleteCoroutinesApi::class, ExperimentalCoroutinesApi::class)
fun main() = runBlocking {
    val p = produce<Int> { send(1); send(2) }
    for (x in p) println(x)
    println("iter-done")

    val p2 = produce<Int> { send(5) }
    println(p2.consumeEach { })
    println("consumeEach-done")

    // produce handles answer channel-family is/as checks like kotlinx.
    val p3 = produce<Int> { send(7) }
    val a: Any? = p3
    println("is Channel: ${a is Channel<*>}")
    println("is SendChannel: ${a is SendChannel<*>}")
    println("is ReceiveChannel: ${a is ReceiveChannel<*>}")
    (a as Channel<*>).cancel()
    println("cast-done")

    // consume (the block form) drains a produce result and cancels it.
    val p4 = produce<Int>(capacity = 2) { send(3); send(4) }
    p4.consume { for (e in this) println("consumed $e") }
    println("consume-done")

    // Inside a produce block the receiver answers channel checks too.
    val p5 = produce<Int> {
        println("scope is Channel: ${this is Channel<*>}")
        println("scope is SendChannel: ${this is SendChannel<*>}")
        println("channel is Channel: ${channel is Channel<*>}")
        send(9)
    }
    println("p5 recv: ${p5.receive()}")
    p5.cancel()

    // ActorScope: upstream declares ActorScope : ReceiveChannel; `channel`
    // returns the same handle under a Channel static type.
    val act = actor<Int> {
        println("actor scope is Channel: ${this is Channel<*>}")
        println("actor channel is Channel: ${channel is Channel<*>}")
        for (e in channel) println("actor got $e")
        println("actor done")
    }
    act.send(1)
    act.close()
    println("all-done")
}
