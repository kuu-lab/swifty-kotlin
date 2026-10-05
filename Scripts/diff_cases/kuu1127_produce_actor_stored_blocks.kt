import kotlinx.coroutines.*
import kotlinx.coroutines.channels.*

fun CoroutineScope.forwardProducer(block: suspend ProducerScope<Int>.() -> Unit): ReceiveChannel<Int> =
    produce(block = block)

fun producerBlock(a: Int, b: Int): suspend ProducerScope<Int>.() -> Unit = {
    send(a)
    yield()
    send(b)
}

fun CoroutineScope.forwardActor(block: suspend ActorScope<Int>.() -> Unit): SendChannel<Int> =
    actor(block = block)

fun main() = runBlocking {
    val emptyCapture: suspend ProducerScope<Int>.() -> Unit = { send(1); send(2) }
    var total = 0
    for (v in produce(block = emptyCapture)) { total += v }
    println("uncaptured: $total")

    val seed = 6
    val singleCapture: suspend ProducerScope<Int>.() -> Unit = { yield(); send(seed) }
    total = 0
    for (v in forwardProducer(singleCapture)) { total += v }
    println("single: $total")

    val a = 4
    val b = 5
    val captured: suspend ProducerScope<Int>.() -> Unit = { send(a); yield(); send(b) }
    total = 0
    for (v in produce(capacity = 1, block = captured)) { total += v }
    println("captured: $total")

    total = 0
    for (v in forwardProducer(producerBlock(7, 8))) { total += v }
    println("forwarded: $total")

    val done = Channel<Int>(1)
    val bonus = 3
    val consumer: suspend ActorScope<Int>.() -> Unit = {
        var sum = bonus
        for (v in channel) { sum += v }
        done.send(sum)
    }
    val mailbox = forwardActor(consumer)
    mailbox.send(10)
    yield()
    mailbox.send(20)
    mailbox.close()
    println("actor: ${done.receive()}")
}
